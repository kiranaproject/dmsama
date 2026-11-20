unit DmSama.XAuth;

// DmSama.XAuth
// ============
// MIT-MAGIC-COOKIE-1 generation and Xauthority binary file serialization for dmsama.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, BaseUnix, ctypes;

const
  FAMILY_LOCAL = 256;
  FAMILY_WILD  = 65535;
  AUTH_NAME    = 'MIT-MAGIC-COOKIE-1';
  COOKIE_LEN   = 16;

type
  TCookieBytes = array[0..COOKIE_LEN - 1] of Byte;

  TDmXAuth = class
  private
    FCookie     : TCookieBytes;
    FCookieHex  : string;
    FDisplayNum : string;
    FHostname   : string;

    function ToBigEndian16(v: Word): Word;
    procedure GenerateRandomCookie();
    procedure UpdateHex();
  public
    constructor Create(const ADisplay: string = ':0');

    function  Generate(): Boolean;
    function  WriteToStream(AStream: TStream): Boolean;
    function  WriteToFile(const AFilePath: string): Boolean;

    property Cookie: TCookieBytes read FCookie;
    property CookieHex: string read FCookieHex;
    property DisplayNum: string read FDisplayNum write FDisplayNum;
    property Hostname: string read FHostname write FHostname;
  end;

function ExtractDisplayNumber(const ADisplayStr: string): string;

implementation

function gethostname(name: PChar; len: size_t): cint; cdecl; external 'c' name 'gethostname';

function ExtractDisplayNumber(const ADisplayStr: string): string;
var
  colonPos, dotPos: Integer;
begin
  colonPos := Pos(':', ADisplayStr);
  if colonPos > 0 then
    Result := Copy(ADisplayStr, colonPos + 1, Length(ADisplayStr))
  else
    Result := Trim(ADisplayStr);

  dotPos := Pos('.', Result);
  if dotPos > 0 then
    Result := Copy(Result, 1, dotPos - 1);

  if Result = '' then
    Result := '0';
end;

constructor TDmXAuth.Create(const ADisplay: string = ':0');
var
  h: array[0..255] of Char;
begin
  inherited Create();
  FDisplayNum := ExtractDisplayNumber(ADisplay);
  FillChar(h, SizeOf(h), 0);
  if gethostname(@h[0], SizeOf(h) - 1) = 0 then
    FHostname := StrPas(@h[0])
  else
    FHostname := 'localhost';

  Generate();
end;

function TDmXAuth.ToBigEndian16(v: Word): Word;
begin
  Result := (v shr 8) or ((v and $FF) shl 8);
end;

procedure TDmXAuth.GenerateRandomCookie();
var
  fd: cint;
  readBytes: ssize_t;
  i: Integer;
begin
  FillChar(FCookie, SizeOf(FCookie), 0);
  fd := fpOpen('/dev/urandom', O_RDONLY);
  if fd >= 0 then
  begin
    readBytes := fpRead(fd, FCookie[0], COOKIE_LEN);
    fpClose(fd);
    if readBytes = COOKIE_LEN then Exit;
  end;

  // Fallback if /dev/urandom is unavailable
  Randomize();
  for i := 0 to COOKIE_LEN - 1 do
    FCookie[i] := Byte(Random(256));
end;

procedure TDmXAuth.UpdateHex();
var
  i: Integer;
begin
  FCookieHex := '';
  for i := 0 to COOKIE_LEN - 1 do
    FCookieHex := FCookieHex + IntToHex(FCookie[i], 2);
end;

function TDmXAuth.Generate(): Boolean;
begin
  GenerateRandomCookie();
  UpdateHex();
  Result := True;
end;

function TDmXAuth.WriteToStream(AStream: TStream): Boolean;
var
  w: Word;
begin
  Result := False;
  if AStream = nil then Exit;

  try
    // 1. Family (FamilyLocal = 256)
    w := ToBigEndian16(FAMILY_LOCAL);
    AStream.WriteBuffer(w, 2);

    // 2. Address (Hostname)
    w := ToBigEndian16(Length(FHostname));
    AStream.WriteBuffer(w, 2);
    if Length(FHostname) > 0 then
      AStream.WriteBuffer(FHostname[1], Length(FHostname));

    // 3. Display Number
    w := ToBigEndian16(Length(FDisplayNum));
    AStream.WriteBuffer(w, 2);
    if Length(FDisplayNum) > 0 then
      AStream.WriteBuffer(FDisplayNum[1], Length(FDisplayNum));

    // 4. Authorization Protocol Name (MIT-MAGIC-COOKIE-1)
    w := ToBigEndian16(Length(AUTH_NAME));
    AStream.WriteBuffer(w, 2);
    AStream.WriteBuffer(AUTH_NAME[1], Length(AUTH_NAME));

    // 5. Authorization Data (16 binary bytes)
    w := ToBigEndian16(COOKIE_LEN);
    AStream.WriteBuffer(w, 2);
    AStream.WriteBuffer(FCookie[0], COOKIE_LEN);

    // Also write a FamilyWild entry so localhost / unix domain sockets match
    w := ToBigEndian16(FAMILY_WILD);
    AStream.WriteBuffer(w, 2);

    w := ToBigEndian16(0);
    AStream.WriteBuffer(w, 2);

    w := ToBigEndian16(Length(FDisplayNum));
    AStream.WriteBuffer(w, 2);
    if Length(FDisplayNum) > 0 then
      AStream.WriteBuffer(FDisplayNum[1], Length(FDisplayNum));

    w := ToBigEndian16(Length(AUTH_NAME));
    AStream.WriteBuffer(w, 2);
    AStream.WriteBuffer(AUTH_NAME[1], Length(AUTH_NAME));

    w := ToBigEndian16(COOKIE_LEN);
    AStream.WriteBuffer(w, 2);
    AStream.WriteBuffer(FCookie[0], COOKIE_LEN);

    Result := True;
  except
    Result := False;
  end;
end;

function TDmXAuth.WriteToFile(const AFilePath: string): Boolean;
var
  fs: TFileStream;
  dir: string;
begin
  Result := False;
  try
    dir := ExtractFileDir(AFilePath);
    if (dir <> '') and not DirectoryExists(dir) then
      ForceDirectories(dir);

    fs := TFileStream.Create(AFilePath, fmCreate);
    try
      Result := WriteToStream(fs);
    finally
      fs.Free();
    end;

    // Secure permissions: 0600 (owner read/write only)
    fpChmod(PChar(AFilePath), &0600);
  except
    Result := False;
  end;
end;

end.
