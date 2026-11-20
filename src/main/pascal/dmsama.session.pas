unit DmSama.Session;

// DmSama.Session
// ==============
// Desktop session enumeration, privilege dropping, and session process spawning for dmsama.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, BaseUnix, ctypes;

type
  PPasswd = ^TPasswd;
  TPasswd = record
    pw_name   : PChar;
    pw_passwd : PChar;
    pw_uid    : cuint;
    pw_gid    : cuint;
    pw_gecos  : PChar;
    pw_dir    : PChar;
    pw_shell  : PChar;
  end;

  TSessionInfo = record
    Key     : string;
    Name    : string;
    Comment : string;
    ExecCmd : string;
  end;
  TSessionInfoArray = array of TSessionInfo;

  TDmSessionManager = class
  public
    class function EnumerateSessions(const ASessionsDir: string = '/usr/share/xsessions'): TSessionInfoArray;
    class function ResolveSessionExec(const ASessionKey: string; const ASessionsDir: string = '/usr/share/xsessions'): string;
    class function SpawnGreeter(const AGreeterCmd, AGreeterUser, ADisplay, AXAuth: string): pid_t;
    class function SpawnUserSession(const AUsername, ASessionExec, ADisplay, AXAuth: string; APamEnv: TStrings = nil): pid_t;
  end;

implementation

function getpwnam(name: PChar): PPasswd; cdecl; external 'c' name 'getpwnam';
function initgroups(user: PChar; group: gid_t): cint; cdecl; external 'c' name 'initgroups';
function setgid(gid: gid_t): cint; cdecl; external 'c' name 'setgid';
function setuid(uid: uid_t): cint; cdecl; external 'c' name 'setuid';
function setenv(name: PChar; value: PChar; overwrite: cint): cint; cdecl; external 'c' name 'setenv';
function execvp(file_: PChar; argv: PPChar): cint; cdecl; external 'c' name 'execvp';
function execl(path: PChar; arg0: PChar; arg1: PChar; arg2: PChar; arg3: PChar): cint; cdecl; external 'c' name 'execl';

class function TDmSessionManager.EnumerateSessions(const ASessionsDir: string): TSessionInfoArray;
var
  sr: TSearchRec;
  lines: TStringList;
  i: Integer;
  line, sName, sExec, sComment, key: string;
  count: Integer;
  dir: string;
begin
  SetLength(Result, 0);
  count := 0;
  dir := IncludeTrailingPathDelimiter(ASessionsDir);

  if FindFirst(dir + '*.desktop', faAnyFile, sr) = 0 then
  begin
    lines := TStringList.Create();
    try
      repeat
        if (sr.Attr and faDirectory) = 0 then
        begin
          lines.Clear();
          try
            lines.LoadFromFile(dir + sr.Name);
            sName := '';
            sExec := '';
            sComment := '';
            key := ChangeFileExt(sr.Name, '');

            for i := 0 to lines.Count - 1 do
            begin
              line := Trim(lines[i]);
              if (sName = '') and (Pos('Name=', line) = 1) then
                sName := Copy(line, 6, Length(line))
              else if (sExec = '') and (Pos('Exec=', line) = 1) then
                sExec := Copy(line, 6, Length(line))
              else if (sComment = '') and (Pos('Comment=', line) = 1) then
                sComment := Copy(line, 9, Length(line));
            end;

            if sName = '' then sName := key;
            Inc(count);
            SetLength(Result, count);
            Result[count - 1].Key := key;
            Result[count - 1].Name := sName;
            Result[count - 1].Comment := sComment;
            Result[count - 1].ExecCmd := sExec;
          except
          end;
        end;
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
      lines.Free();
    end;
  end;

  if count = 0 then
  begin
    SetLength(Result, 1);
    Result[0].Key := 'default';
    Result[0].Name := 'Default Session';
    Result[0].Comment := 'Default session';
    Result[0].ExecCmd := 'x-session-manager';
  end;
end;

class function TDmSessionManager.ResolveSessionExec(const ASessionKey, ASessionsDir: string): string;
var
  sessions: TSessionInfoArray;
  i: Integer;
begin
  Result := '';
  sessions := EnumerateSessions(ASessionsDir);
  for i := 0 to High(sessions) do
  begin
    if SameText(sessions[i].Key, ASessionKey) then
    begin
      Result := sessions[i].ExecCmd;
      Exit;
    end;
  end;

  if Length(sessions) > 0 then
    Result := sessions[0].ExecCmd;

  if Result = '' then
    Result := 'x-session-manager || mate-session || shellsama';
end;

class function TDmSessionManager.SpawnGreeter(const AGreeterCmd, AGreeterUser, ADisplay, AXAuth: string): pid_t;
var
  pid: pid_t;
  pw: PPasswd;
  args: TStringList;
  pArgs: array of PChar;
  i: Integer;
begin
  Result := -1;
  pid := fpFork();
  if pid < 0 then Exit;

  // Child process
  if pid = 0 then
  begin
    fpSetsid();

    // Drop privileges to greeter user if running as root
    if (fpGetUID() = 0) and (AGreeterUser <> '') then
    begin
      pw := getpwnam(PChar(AGreeterUser));
      if pw <> nil then
      begin
        initgroups(pw^.pw_name, pw^.pw_gid);
        setgid(pw^.pw_gid);
        setuid(pw^.pw_uid);
        setenv('HOME', pw^.pw_dir, 1);
        setenv('USER', pw^.pw_name, 1);
        setenv('LOGNAME', pw^.pw_name, 1);
        setenv('SHELL', pw^.pw_shell, 1);
        fpChDir(pw^.pw_dir);
      end;
    end;

    setenv('DISPLAY', PChar(ADisplay), 1);
    if AXAuth <> '' then
      setenv('XAUTHORITY', PChar(AXAuth), 1);
    setenv('XDG_SESSION_TYPE', 'x11', 1);
    setenv('XDG_SESSION_CLASS', 'greeter', 1);

    args := TStringList.Create();
    try
      args.Delimiter := ' ';
      args.DelimitedText := AGreeterCmd;
      SetLength(pArgs, args.Count + 1);
      for i := 0 to args.Count - 1 do
        pArgs[i] := PChar(args[i]);
      pArgs[args.Count] := nil;

      execvp(pArgs[0], @pArgs[0]);
    finally
      args.Free();
    end;

    fpExit(127);
  end;

  Result := pid;
end;

class function TDmSessionManager.SpawnUserSession(const AUsername, ASessionExec, ADisplay, AXAuth: string; APamEnv: TStrings): pid_t;
var
  pid: pid_t;
  pw: PPasswd;
  i, eqPos: Integer;
  envLine, envKey, envVal: string;
begin
  Result := -1;
  pid := fpFork();
  if pid < 0 then Exit;

  // Child process
  if pid = 0 then
  begin
    fpSetsid();

    pw := nil;
    if AUsername <> '' then
      pw := getpwnam(PChar(AUsername));

    // Drop privileges
    if (fpGetUID() = 0) and (pw <> nil) then
    begin
      initgroups(pw^.pw_name, pw^.pw_gid);
      setgid(pw^.pw_gid);
      setuid(pw^.pw_uid);
      setenv('HOME', pw^.pw_dir, 1);
      setenv('USER', pw^.pw_name, 1);
      setenv('LOGNAME', pw^.pw_name, 1);
      setenv('SHELL', pw^.pw_shell, 1);
      fpChDir(pw^.pw_dir);
    end;

    setenv('DISPLAY', PChar(ADisplay), 1);
    if AXAuth <> '' then
      setenv('XAUTHORITY', PChar(AXAuth), 1);
    setenv('XDG_SESSION_TYPE', 'x11', 1);
    setenv('XDG_SESSION_CLASS', 'user', 1);
    setenv('XDG_SEAT', 'seat0', 1);

    // Apply PAM environment variables
    if APamEnv <> nil then
    begin
      for i := 0 to APamEnv.Count - 1 do
      begin
        envLine := APamEnv[i];
        eqPos := Pos('=', envLine);
        if eqPos > 1 then
        begin
          envKey := Copy(envLine, 1, eqPos - 1);
          envVal := Copy(envLine, eqPos + 1, Length(envLine));
          setenv(PChar(envKey), PChar(envVal), 1);
        end;
      end;
    end;

    // Execute session wrapper via /bin/sh -c
    execl('/bin/sh', '/bin/sh', '-c', PChar(ASessionExec), nil);
    fpExit(127);
  end;

  Result := pid;
end;

end.
