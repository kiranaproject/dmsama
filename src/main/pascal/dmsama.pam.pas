unit DmSama.PAM;

// DmSama.PAM
// ==========
// Root PAM transaction management for dmsama daemon (session opening, env, credentials).

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, dynlibs;

const
  PAM_SUCCESS              = 0;
  PAM_OPEN_ERR             = 1;
  PAM_SYMBOL_ERR           = 2;
  PAM_SERVICE_ERR          = 3;
  PAM_SYSTEM_ERR           = 4;
  PAM_BUF_ERR              = 5;
  PAM_PERM_DENIED          = 6;
  PAM_AUTH_ERR             = 7;
  PAM_CRED_INSUFFICIENT    = 8;
  PAM_AUTHINFO_UNAVAIL     = 9;
  PAM_USER_UNKNOWN         = 10;
  PAM_MAXTRIES             = 11;
  PAM_NEW_AUTHTOK_REQD     = 12;
  PAM_ACCT_EXPIRED         = 13;
  PAM_SESSION_ERR          = 14;
  PAM_CRED_UNAVAIL         = 15;
  PAM_CRED_EXPIRED         = 16;
  PAM_CRED_ERR             = 17;

  PAM_ESTABLISH_CRED       = 2;
  PAM_DELETE_CRED          = 4;
  PAM_REINITIALIZE_CRED    = 8;
  PAM_REFRESH_CRED         = 16;

  PAM_PROMPT_ECHO_OFF      = 1;
  PAM_PROMPT_ECHO_ON       = 2;
  PAM_ERROR_MSG            = 3;
  PAM_TEXT_INFO            = 4;

type
  PPamHandle = Pointer;

  PPamMessage = ^TPamMessage;
  TPamMessage = record
    msg_style : cint;
    msg       : PChar;
  end;
  PPPamMessage = ^PPamMessage;

  PPamResponse = ^TPamResponse;
  TPamResponse = record
    resp         : PChar;
    resp_retcode : cint;
  end;
  PPPamResponse = ^PPamResponse;

  TPamConvFunc = function(num_msg: cint; msg: PPPamMessage; var resp: PPamResponse; appdata_ptr: Pointer): cint; cdecl;

  TPamConv = record
    conv        : TPamConvFunc;
    appdata_ptr : Pointer;
  end;
  PPamConv = ^TPamConv;

  TDmPam = class
  private
    FLibHandle        : TLibHandle;
    FAvailable        : Boolean;
    FPamh             : PPamHandle;
    FSessionOpen      : Boolean;
    FCredEstablished  : Boolean;
    FServiceName      : string;
    FUsername         : string;
    FSeat             : string;
    FSessionType      : string;
    FSessionClass     : string;
    FVT               : Integer;

    Fpam_start        : function(service_name: PChar; user: PChar; pam_conversation: PPamConv; out pamh: PPamHandle): cint; cdecl;
    Fpam_authenticate : function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_acct_mgmt    : function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_setcred      : function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_open_session : function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_close_session: function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_end          : function(pamh: PPamHandle; pam_status: cint): cint; cdecl;
    Fpam_strerror     : function(pamh: PPamHandle; errnum: cint): PChar; cdecl;
    Fpam_putenv       : function(pamh: PPamHandle; name_value: PChar): cint; cdecl;
    Fpam_getenvlist   : function(pamh: PPamHandle): PPChar; cdecl;

    procedure LoadSymbols();
  public
    constructor Create(const AServiceName: string = 'dmsama');
    destructor Destroy(); override;

    function Authenticate(const AUsername, APassword: string; out AErrorMsg: string): Boolean;
    function StartSession(const AUsername: string; out AErrorMsg: string): Boolean;
    function OpenSession(out AErrorMsg: string): Boolean;
    function CloseSession(): Boolean;
    function PutEnv(const ANameValue: string): Boolean;
    function GetEnvList(): TStringList;

    property Available: Boolean read FAvailable;
    property SessionOpen: Boolean read FSessionOpen;
    property ServiceName: string read FServiceName write FServiceName;
    property Username: string read FUsername;
    property Seat: string read FSeat write FSeat;
    property SessionType: string read FSessionType write FSessionType;
    property SessionClass: string read FSessionClass write FSessionClass;
    property VT: Integer read FVT write FVT;
  end;

implementation

function malloc(size: csize_t): Pointer; cdecl; external 'c';
function strdup(const s: PChar): PChar; cdecl; external 'c';
function getpwnam(name: PChar): Pointer; cdecl; external 'c' name 'getpwnam';

function DmPamConversation(num_msg: cint; msg: PPPamMessage; var resp: PPamResponse; appdata_ptr: Pointer): cint; cdecl;
var
  i: cint;
  resps: PPamResponse;
  pw: PChar;
begin
  pw := PChar(appdata_ptr);
  resps := PPamResponse(malloc(num_msg * SizeOf(TPamResponse)));
  if resps = nil then Exit(PAM_BUF_ERR);
  FillChar(resps^, num_msg * SizeOf(TPamResponse), 0);

  for i := 0 to num_msg - 1 do
  begin
    if (msg[i]^.msg_style = PAM_PROMPT_ECHO_OFF) or (msg[i]^.msg_style = PAM_PROMPT_ECHO_ON) then
    begin
      if pw <> nil then
        resps[i].resp := strdup(pw)
      else
        resps[i].resp := nil;
      resps[i].resp_retcode := 0;
    end;
  end;
  resp := resps;
  Result := PAM_SUCCESS;
end;

constructor TDmPam.Create(const AServiceName: string = 'dmsama');
begin
  inherited Create();
  FServiceName := AServiceName;
  FAvailable := False;
  FPamh := nil;
  FSessionOpen := False;
  FCredEstablished := False;
  FSeat := 'seat0';
  FSessionType := 'x11';
  FSessionClass := 'user';
  FVT := 7;

  FLibHandle := SafeLoadLibrary('libpam.so.0');
  if FLibHandle = NilHandle then
    FLibHandle := SafeLoadLibrary('libpam.so');

  if FLibHandle <> NilHandle then
  begin
    LoadSymbols();
    FAvailable := Assigned(Fpam_start) and Assigned(Fpam_authenticate) and Assigned(Fpam_end);
  end;
end;

destructor TDmPam.Destroy();
begin
  if FSessionOpen then
    CloseSession();

  if FPamh <> nil then
  begin
    if Assigned(Fpam_end) then
      Fpam_end(FPamh, PAM_SUCCESS);
    FPamh := nil;
  end;

  if FLibHandle <> NilHandle then
  begin
    UnloadLibrary(FLibHandle);
    FLibHandle := NilHandle;
  end;

  inherited Destroy();
end;

procedure TDmPam.LoadSymbols();
begin
  Pointer(Fpam_start)         := GetProcedureAddress(FLibHandle, 'pam_start');
  Pointer(Fpam_authenticate)  := GetProcedureAddress(FLibHandle, 'pam_authenticate');
  Pointer(Fpam_acct_mgmt)     := GetProcedureAddress(FLibHandle, 'pam_acct_mgmt');
  Pointer(Fpam_setcred)       := GetProcedureAddress(FLibHandle, 'pam_setcred');
  Pointer(Fpam_open_session)  := GetProcedureAddress(FLibHandle, 'pam_open_session');
  Pointer(Fpam_close_session) := GetProcedureAddress(FLibHandle, 'pam_close_session');
  Pointer(Fpam_end)           := GetProcedureAddress(FLibHandle, 'pam_end');
  Pointer(Fpam_strerror)      := GetProcedureAddress(FLibHandle, 'pam_strerror');
  Pointer(Fpam_putenv)        := GetProcedureAddress(FLibHandle, 'pam_putenv');
  Pointer(Fpam_getenvlist)    := GetProcedureAddress(FLibHandle, 'pam_getenvlist');
end;

function TDmPam.Authenticate(const AUsername, APassword: string; out AErrorMsg: string): Boolean;
var
  conv: TPamConv;
  rc: cint;
  svcToTry: string;
begin
  Result := False;
  AErrorMsg := '';
  FUsername := AUsername;

  if not FAvailable then
  begin
    AErrorMsg := 'PAM library not available';
    Exit;
  end;

  if FPamh <> nil then
  begin
    Fpam_end(FPamh, PAM_SUCCESS);
    FPamh := nil;
  end;

  conv.conv := @DmPamConversation;
  conv.appdata_ptr := PChar(APassword);

  svcToTry := FServiceName;
  rc := Fpam_start(PChar(svcToTry), PChar(AUsername), @conv, FPamh);
  if (rc <> PAM_SUCCESS) and (svcToTry <> 'other') then
  begin
    svcToTry := 'login';
    rc := Fpam_start(PChar(svcToTry), PChar(AUsername), @conv, FPamh);
    if rc <> PAM_SUCCESS then
    begin
      svcToTry := 'other';
      rc := Fpam_start(PChar(svcToTry), PChar(AUsername), @conv, FPamh);
    end;
  end;

  if rc <> PAM_SUCCESS then
  begin
    AErrorMsg := 'pam_start error: ' + string(Fpam_strerror(FPamh, rc));
    Exit;
  end;

  rc := Fpam_authenticate(FPamh, 0);
  if rc <> PAM_SUCCESS then
  begin
    AErrorMsg := string(Fpam_strerror(FPamh, rc));
    Exit;
  end;

  if Assigned(Fpam_acct_mgmt) then
  begin
    rc := Fpam_acct_mgmt(FPamh, 0);
    if rc <> PAM_SUCCESS then
    begin
      AErrorMsg := 'Account management error: ' + string(Fpam_strerror(FPamh, rc));
      Exit;
    end;
  end;

  Result := True;
end;

function TDmPam.StartSession(const AUsername: string; out AErrorMsg: string): Boolean;
var
  conv: TPamConv;
  rc: cint;
  svcToTry: string;
begin
  Result := False;
  AErrorMsg := '';
  FUsername := AUsername;

  if (AUsername = '') or (getpwnam(PChar(AUsername)) = nil) then
  begin
    AErrorMsg := 'User not found: ' + AUsername;
    Exit;
  end;

  if not FAvailable then
  begin
    AErrorMsg := 'PAM library not available';
    Exit;
  end;

  if FPamh <> nil then
  begin
    CloseSession();
    Fpam_end(FPamh, PAM_SUCCESS);
    FPamh := nil;
  end;

  conv.conv := @DmPamConversation;
  conv.appdata_ptr := nil;

  svcToTry := FServiceName;
  rc := Fpam_start(PChar(svcToTry), PChar(AUsername), @conv, FPamh);
  if (rc <> PAM_SUCCESS) and (svcToTry <> 'other') then
  begin
    svcToTry := 'login';
    rc := Fpam_start(PChar(svcToTry), PChar(AUsername), @conv, FPamh);
    if rc <> PAM_SUCCESS then
    begin
      svcToTry := 'other';
      rc := Fpam_start(PChar(svcToTry), PChar(AUsername), @conv, FPamh);
    end;
  end;

  if rc <> PAM_SUCCESS then
  begin
    AErrorMsg := 'pam_start error: ' + string(Fpam_strerror(FPamh, rc));
    Exit;
  end;

  Result := OpenSession(AErrorMsg);
end;

function TDmPam.OpenSession(out AErrorMsg: string): Boolean;
var
  rc: cint;
begin
  Result := False;
  AErrorMsg := '';
  if FPamh = nil then Exit;

  // Set standard seat and session properties for pam_systemd
  if FSeat <> '' then
    PutEnv('XDG_SEAT=' + FSeat);
  if FSessionType <> '' then
    PutEnv('XDG_SESSION_TYPE=' + FSessionType);
  if FSessionClass <> '' then
    PutEnv('XDG_SESSION_CLASS=' + FSessionClass);
  if FVT > 0 then
    PutEnv('XDG_VTNR=' + IntToStr(FVT));

  if Assigned(Fpam_setcred) then
  begin
    rc := Fpam_setcred(FPamh, PAM_ESTABLISH_CRED);
    if rc = PAM_SUCCESS then
      FCredEstablished := True;
  end;

  if Assigned(Fpam_open_session) then
  begin
    rc := Fpam_open_session(FPamh, 0);
    if rc <> PAM_SUCCESS then
    begin
      AErrorMsg := 'pam_open_session error: ' + string(Fpam_strerror(FPamh, rc));
      Exit;
    end;
    FSessionOpen := True;
  end;

  Result := True;
end;

function TDmPam.CloseSession(): Boolean;
var
  rc: cint;
begin
  Result := True;
  if FPamh = nil then Exit;

  if FSessionOpen and Assigned(Fpam_close_session) then
  begin
    rc := Fpam_close_session(FPamh, 0);
    FSessionOpen := False;
    if rc <> PAM_SUCCESS then Result := False;
  end;

  if FCredEstablished and Assigned(Fpam_setcred) then
  begin
    Fpam_setcred(FPamh, PAM_DELETE_CRED);
    FCredEstablished := False;
  end;
end;

function TDmPam.PutEnv(const ANameValue: string): Boolean;
begin
  Result := False;
  if (FPamh <> nil) and Assigned(Fpam_putenv) then
    Result := (Fpam_putenv(FPamh, PChar(ANameValue)) = PAM_SUCCESS);
end;

function TDmPam.GetEnvList(): TStringList;
var
  pp: PPChar;
begin
  Result := TStringList.Create();
  if (FPamh <> nil) and Assigned(Fpam_getenvlist) then
  begin
    pp := Fpam_getenvlist(FPamh);
    if pp <> nil then
    begin
      while pp^ <> nil do
      begin
        Result.Add(string(pp^));
        Inc(pp);
      end;
    end;
  end;
end;

end.
