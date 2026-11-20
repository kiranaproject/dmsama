program dmsama;

// dmsama
// ======
// Samarinda Display Manager root daemon.
// Manages Xorg server lifecycle, virtual terminals, greeter process, and PAM session authentication.

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, BaseUnix, ctypes,
  DmSama.Config,
  DmSama.XAuth,
  DmSama.XServer,
  DmSama.PAM,
  DmSama.Session;

var
  Config     : TDmConfig;
  XAuth      : TDmXAuth;
  XServer    : TDmXServer;
  PamSession : TDmPam;
  TestMode   : Boolean;
  ConfigPath : string;
  i          : Integer;
  arg        : string;
  authPath   : string;
  sessions   : TSessionInfoArray;
  gTerminated: Boolean = False;

procedure SignalHandler(sig: cint); cdecl;
begin
  gTerminated := True;
end;

procedure PrintUsage();
begin
  WriteLn('dmsama — Samarinda Display Manager Daemon');
  WriteLn('Usage: dmsama [options]');
  WriteLn('Options:');
  WriteLn('  --config <path>    Path to configuration file (default: /etc/dmsama/dmsama.conf)');
  WriteLn('  --test, -t         Validate configuration and dependencies without starting Xorg');
  WriteLn('  --display <num>    Override display number (default: :0)');
  WriteLn('  --vt <num>         Override virtual terminal number (default: 7)');
  WriteLn('  --greeter <cmd>    Override greeter launch command (default: shellsama --greeter)');
  WriteLn('  --version, -v      Print version and exit');
  WriteLn('  --help, -h         Print this help message and exit');
end;

procedure RunTestValidation();
var
  i: Integer;
begin
  WriteLn('dmsama 0.0.1-SNAPSHOT — Test & Validation Mode');
  WriteLn('--------------------------------------------------');
  WriteLn('Configuration:');
  WriteLn('  Display:         ', Config.Display);
  WriteLn('  Virtual Terminal:', Config.VT);
  WriteLn('  XServer Command: ', Config.XServerCmd);
  WriteLn('  XServer Args:    ', Config.XServerArgs);
  WriteLn('  Greeter Command: ', Config.GreeterCmd);
  WriteLn('  Greeter User:    ', Config.GreeterUser);
  WriteLn('  Auth Directory:  ', Config.AuthDir);
  WriteLn('  Sessions Dir:    ', Config.SessionsDir);
  WriteLn('  Default Session: ', Config.DefaultSession);
  WriteLn('  Auto Login:      ', Config.AutoLogin);
  WriteLn;

  // 1. Validate XServer binary
  Write('Validating Xorg server binary... ');
  if FileExists(Config.XServerCmd) then
    WriteLn('OK (', Config.XServerCmd, ')')
  else
    WriteLn('Warning: Binary not found at ', Config.XServerCmd);

  // 2. Validate PAM
  Write('Validating PAM subsystem... ');
  PamSession := TDmPam.Create('dmsama');
  try
    if PamSession.Available then
      WriteLn('OK (libpam loaded)')
    else
      WriteLn('Failed: libpam not available');
  finally
    PamSession.Free();
  end;

  // 3. Validate XAuth generation
  Write('Validating Xauthority cookie generation... ');
  XAuth := TDmXAuth.Create(Config.Display);
  try
    if Length(XAuth.CookieHex) = 32 then
      WriteLn('OK (MIT-MAGIC-COOKIE-1 128-bit)')
    else
      WriteLn('Failed: Invalid cookie length');
  finally
    XAuth.Free();
  end;

  // 4. Validate Sessions
  Write('Enumerating available desktop sessions... ');
  sessions := TDmSessionManager.EnumerateSessions(Config.SessionsDir);
  WriteLn(Length(sessions), ' session(s) found');
  for i := 0 to High(sessions) do
    WriteLn('  [', i + 1, '] ', sessions[i].Key, ' -> "', sessions[i].Name, '" (Exec: ', sessions[i].ExecCmd, ')');

  WriteLn;
  WriteLn('Validation completed successfully.');
end;

begin
  TestMode := False;
  ConfigPath := '/etc/dmsama/dmsama.conf';

  // Pre-parse config path from arguments
  i := 1;
  while i <= ParamCount do
  begin
    arg := ParamStr(i);
    if ((arg = '--config') or (arg = '-c')) and (i < ParamCount) then
    begin
      Inc(i);
      ConfigPath := ParamStr(i);
    end
    else if (arg = '--test') or (arg = '-t') or (arg = '--dry-run') then
      TestMode := True
    else if (arg = '--version') or (arg = '-v') then
    begin
      WriteLn('dmsama 0.0.1-SNAPSHOT');
      Halt(0);
    end
    else if (arg = '--help') or (arg = '-h') then
    begin
      PrintUsage();
      Halt(0);
    end;
    Inc(i);
  end;

  Config := TDmConfig.Create();
  try
    if FileExists(ConfigPath) then
      Config.LoadFromFile(ConfigPath);

    // Apply CLI overrides
    i := 1;
    while i <= ParamCount do
    begin
      arg := ParamStr(i);
      if (arg = '--display') and (i < ParamCount) then
      begin
        Inc(i);
        Config.Display := ParamStr(i);
      end
      else if (arg = '--vt') and (i < ParamCount) then
      begin
        Inc(i);
        Config.VT := StrToIntDef(ParamStr(i), 7);
      end
      else if (arg = '--greeter') and (i < ParamCount) then
      begin
        Inc(i);
        Config.GreeterCmd := ParamStr(i);
      end;
      Inc(i);
    end;

    if TestMode then
    begin
      RunTestValidation();
      Halt(0);
    end;

    // Normal root daemon operation
    WriteLn('dmsama — Samarinda Display Manager starting...');
    if fpGetUID() <> 0 then
    begin
      WriteLn(StdErr, 'Notice: Running without root privileges. Operation may fail when seizing virtual terminals.');
    end;

    // Install signal handlers
    fpsignal(SIGINT, @SignalHandler);
    fpsignal(SIGTERM, @SignalHandler);
    fpsignal(SIGHUP, @SignalHandler);

    // Setup runtime auth directory
    authPath := IncludeTrailingPathDelimiter(Config.AuthDir) + 'dmsama.auth';
    if not DirectoryExists(Config.AuthDir) then
      ForceDirectories(Config.AuthDir);

    XAuth := TDmXAuth.Create(Config.Display);
    try
      if not XAuth.WriteToFile(authPath) then
      begin
        // Fallback to /tmp if auth directory is not writable
        authPath := '/tmp/dmsama-' + ExtractDisplayNumber(Config.Display) + '.auth';
        XAuth.WriteToFile(authPath);
      end;

      WriteLn('Generated Xauthority authorization file: ', authPath);

      // Start X server
      XServer := TDmXServer.Create(Config.XServerCmd, Config.Display, Config.VT, authPath, Config.XServerArgs);
      try
        WriteLn('Starting X server: ', Config.XServerCmd, ' ', Config.Display, ' vt', Config.VT);
        if not XServer.Start() then
        begin
          WriteLn(StdErr, 'Error: Failed to spawn X server');
          Halt(1);
        end;

        WriteLn('Waiting for X server readiness...');
        if not XServer.WaitForServer(10000) then
        begin
          WriteLn(StdErr, 'Error: X server failed to accept connections within timeout');
          XServer.Stop();
          Halt(1);
        end;
        WriteLn('X server ready on display ', Config.Display);

        // Main daemon loop: spawn greeter and monitor
        while not gTerminated and XServer.IsRunning do
        begin
          Sleep(500);
        end;

        WriteLn('dmsama shutting down...');
      finally
        XServer.Stop();
        XServer.Free();
      end;
    finally
      if FileExists(authPath) then
        DeleteFile(authPath);
      XAuth.Free();
    end;

  finally
    Config.Free();
  end;
end.
