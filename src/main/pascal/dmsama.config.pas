unit DmSama.Config;

// DmSama.Config
// =============
// Configuration parser and default settings descriptor for dmsama daemon.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, IniFiles;

type
  TDmConfig = class
  private
    FDisplay        : string;
    FVT             : Integer;
    FGreeterCmd     : string;
    FGreeterUser    : string;
    FDefaultSession : string;
    FSessionsDir    : string;
    FAutoLogin      : Boolean;
    FAutoLoginUser  : string;
    FXServerCmd     : string;
    FXServerArgs    : string;
    FAuthDir        : string;

    procedure SetDefaults();
  public
    constructor Create();
    constructor CreateFromFile(const APath: string);

    function  LoadFromFile(const APath: string): Boolean;
    procedure SaveToFile(const APath: string);

    property Display        : string  read FDisplay        write FDisplay;
    property VT             : Integer read FVT             write FVT;
    property GreeterCmd     : string  read FGreeterCmd     write FGreeterCmd;
    property GreeterUser    : string  read FGreeterUser    write FGreeterUser;
    property DefaultSession : string  read FDefaultSession write FDefaultSession;
    property SessionsDir    : string  read FSessionsDir    write FSessionsDir;
    property AutoLogin      : Boolean read FAutoLogin      write FAutoLogin;
    property AutoLoginUser  : string  read FAutoLoginUser  write FAutoLoginUser;
    property XServerCmd     : string  read FXServerCmd     write FXServerCmd;
    property XServerArgs    : string  read FXServerArgs    write FXServerArgs;
    property AuthDir        : string  read FAuthDir        write FAuthDir;
  end;

implementation

constructor TDmConfig.Create();
begin
  inherited Create();
  SetDefaults();
end;

constructor TDmConfig.CreateFromFile(const APath: string);
begin
  Create();
  if FileExists(APath) then
    LoadFromFile(APath);
end;

procedure TDmConfig.SetDefaults();
begin
  FDisplay        := ':0';
  FVT             := 7;
  FGreeterCmd     := 'shellsama --greeter';
  FGreeterUser    := 'dmsama';
  FDefaultSession := 'mate';
  FSessionsDir    := '/usr/share/xsessions';
  FAutoLogin      := False;
  FAutoLoginUser  := '';

  if FileExists('/usr/lib/xorg/Xorg') then
    FXServerCmd   := '/usr/lib/xorg/Xorg'
  else if FileExists('/usr/bin/Xorg') then
    FXServerCmd   := '/usr/bin/Xorg'
  else
    FXServerCmd   := 'Xorg';

  FXServerArgs    := '-core -noreset -novtswitch';
  FAuthDir        := '/var/run/dmsama';
end;

function TDmConfig.LoadFromFile(const APath: string): Boolean;
var
  ini: TIniFile;
  sAutoLogin: string;
begin
  Result := False;
  if not FileExists(APath) then Exit;

  ini := TIniFile.Create(APath);
  try
    FDisplay        := ini.ReadString('Daemon', 'display', FDisplay);
    FVT             := ini.ReadInteger('Daemon', 'vt', FVT);
    FGreeterCmd     := ini.ReadString('Daemon', 'greeter', FGreeterCmd);
    FGreeterUser    := ini.ReadString('Daemon', 'greeter_user', FGreeterUser);
    FDefaultSession := ini.ReadString('Daemon', 'default_session', FDefaultSession);
    FSessionsDir    := ini.ReadString('Daemon', 'sessions_dir', FSessionsDir);
    sAutoLogin      := ini.ReadString('Daemon', 'auto_login', '');
    if sAutoLogin <> '' then
      FAutoLogin := SameText(sAutoLogin, 'true') or SameText(sAutoLogin, 'yes') or (sAutoLogin = '1');
    FAutoLoginUser  := ini.ReadString('Daemon', 'auto_login_user', FAutoLoginUser);

    FXServerCmd     := ini.ReadString('XServer', 'command', FXServerCmd);
    FXServerArgs    := ini.ReadString('XServer', 'args', FXServerArgs);
    FAuthDir        := ini.ReadString('XServer', 'auth_dir', FAuthDir);

    Result := True;
  finally
    ini.Free();
  end;
end;

procedure TDmConfig.SaveToFile(const APath: string);
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(APath);
  try
    ini.WriteString('Daemon', 'display', FDisplay);
    ini.WriteInteger('Daemon', 'vt', FVT);
    ini.WriteString('Daemon', 'greeter', FGreeterCmd);
    ini.WriteString('Daemon', 'greeter_user', FGreeterUser);
    ini.WriteString('Daemon', 'default_session', FDefaultSession);
    ini.WriteString('Daemon', 'sessions_dir', FSessionsDir);
    ini.WriteBool('Daemon', 'auto_login', FAutoLogin);
    ini.WriteString('Daemon', 'auto_login_user', FAutoLoginUser);

    ini.WriteString('XServer', 'command', FXServerCmd);
    ini.WriteString('XServer', 'args', FXServerArgs);
    ini.WriteString('XServer', 'auth_dir', FAuthDir);
  finally
    ini.Free();
  end;
end;

end.
