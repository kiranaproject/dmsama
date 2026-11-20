unit DmSama.XServer;

// DmSama.XServer
// ==============
// Xorg server process lifecycle management and readiness probe for dmsama daemon.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, BaseUnix, ctypes;

type
  TDmXServer = class
  private
    FServerCmd : string;
    FDisplay   : string;
    FVT        : Integer;
    FAuthFile  : string;
    FArgs      : string;
    FPid       : pid_t;

    function GetIsRunning(): Boolean;
  public
    constructor Create(const AServerCmd, ADisplay: string; AVt: Integer; const AAuthFile, AArgs: string);
    destructor Destroy(); override;

    function Start(): Boolean;
    function Stop(): Boolean;
    function WaitForServer(ATimeoutMs: Integer = 5000): Boolean;

    property ServerCmd : string  read FServerCmd write FServerCmd;
    property Display   : string  read FDisplay   write FDisplay;
    property VT        : Integer read FVT        write FVT;
    property AuthFile  : string  read FAuthFile  write FAuthFile;
    property Args      : string  read FArgs      write FArgs;
    property PID       : pid_t   read FPid;
    property IsRunning : Boolean read GetIsRunning;
  end;

implementation

function execvp(file_: PChar; argv: PPChar): cint; cdecl; external 'c' name 'execvp';

constructor TDmXServer.Create(const AServerCmd, ADisplay: string; AVt: Integer; const AAuthFile, AArgs: string);
begin
  inherited Create();
  FServerCmd := AServerCmd;
  FDisplay   := ADisplay;
  FVT        := AVt;
  FAuthFile  := AAuthFile;
  FArgs      := AArgs;
  FPid       := 0;
end;

destructor TDmXServer.Destroy();
begin
  if IsRunning then
    Stop();
  inherited Destroy();
end;

function TDmXServer.GetIsRunning(): Boolean;
var
  status: cint;
  res: pid_t;
begin
  if FPid <= 0 then Exit(False);

  status := 0;
  res := fpWaitPid(FPid, status, WNOHANG);
  if res = 0 then
    Result := True
  else
  begin
    FPid := 0;
    Result := False;
  end;
end;

function TDmXServer.Start(): Boolean;
var
  argList: TStringList;
  pArgs: array of PChar;
  i: Integer;
  vtArg: string;
begin
  Result := False;
  if IsRunning then Exit(True);

  if not FileExists(FServerCmd) and (Pos('/', FServerCmd) > 0) then
    Exit(False);

  argList := TStringList.Create();
  try
    argList.Add(FServerCmd);
    argList.Add(FDisplay);

    if FVT > 0 then
    begin
      vtArg := Format('vt%d', [FVT]);
      argList.Add(vtArg);
    end;

    if FAuthFile <> '' then
    begin
      argList.Add('-auth');
      argList.Add(FAuthFile);
    end;

    // Parse additional args
    if FArgs <> '' then
    begin
      argList.Delimiter := ' ';
      argList.DelimitedText := FArgs;
    end;

    SetLength(pArgs, argList.Count + 1);
    for i := 0 to argList.Count - 1 do
      pArgs[i] := PChar(argList[i]);
    pArgs[argList.Count] := nil;

    FPid := fpFork();
    if FPid < 0 then
    begin
      FPid := 0;
      Exit(False);
    end;

    // Child process: execute Xorg
    if FPid = 0 then
    begin
      fpSetsid();
      execvp(PChar(FServerCmd), @pArgs[0]);
      // If exec fails, exit child immediately
      fpExit(127);
    end;

    Result := True;
  finally
    argList.Free();
  end;
end;

function TDmXServer.WaitForServer(ATimeoutMs: Integer = 5000): Boolean;
var
  dispNum: string;
  socketPath: string;
  colonPos: Integer;
  startTime: QWord;
begin
  Result := False;
  if not IsRunning then Exit;

  colonPos := Pos(':', FDisplay);
  if colonPos > 0 then
    dispNum := Copy(FDisplay, colonPos + 1, Length(FDisplay))
  else
    dispNum := '0';

  socketPath := '/tmp/.X11-unix/X' + dispNum;
  startTime := GetTickCount64();

  while (GetTickCount64() - startTime) < QWord(ATimeoutMs) do
  begin
    if not IsRunning then
      Exit(False);

    if FileExists(socketPath) then
    begin
      Result := True;
      Exit;
    end;

    Sleep(50);
  end;
end;

function TDmXServer.Stop(): Boolean;
var
  status: cint;
  startTime: QWord;
  res: pid_t;
begin
  Result := True;
  if FPid <= 0 then Exit;

  fpKill(FPid, SIGTERM);
  startTime := GetTickCount64();
  status := 0;

  while (GetTickCount64() - startTime) < 2000 do
  begin
    res := fpWaitPid(FPid, status, WNOHANG);
    if res = FPid then
    begin
      FPid := 0;
      Exit(True);
    end;
    Sleep(50);
  end;

  // Force termination if process refused SIGTERM
  fpKill(FPid, SIGKILL);
  fpWaitPid(FPid, status, 0);
  FPid := 0;
end;

end.
