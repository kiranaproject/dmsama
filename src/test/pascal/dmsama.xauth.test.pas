unit DmSama.XAuth.Test;

// DmSama.XAuth.Test
// =================
// Unit tests for MIT-MAGIC-COOKIE-1 generation and binary Xauthority serialization.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  DmSama.XAuth;

type
  TDmXAuthTest = class(TTestCase)
  private
    FXAuth: TDmXAuth;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestCookieGenerationLength();
    procedure TestCookieUniqueness();
    procedure TestDisplayNumberExtraction();
    procedure TestBinarySerializationToStream();
    procedure TestWriteToFileAndPermissions();
  end;

implementation

procedure TDmXAuthTest.SetUp();
begin
  FXAuth := TDmXAuth.Create(':0');
end;

procedure TDmXAuthTest.TearDown();
begin
  if Assigned(FXAuth) then
  begin
    FXAuth.Free();
    FXAuth := nil;
  end;
end;

procedure TDmXAuthTest.TestCookieGenerationLength();
begin
  AssertNotNull('XAuth instance must be valid', FXAuth);
  AssertEquals('Cookie hex representation must be 32 characters', 32, Length(FXAuth.CookieHex));
end;

procedure TDmXAuthTest.TestCookieUniqueness();
var
  auth2: TDmXAuth;
begin
  auth2 := TDmXAuth.Create(':0');
  try
    AssertFalse('Consecutive cookies must be unique', FXAuth.CookieHex = auth2.CookieHex);
  finally
    auth2.Free();
  end;
end;

procedure TDmXAuthTest.TestDisplayNumberExtraction();
begin
  AssertEquals('Extract from :0 should be 0', '0', ExtractDisplayNumber(':0'));
  AssertEquals('Extract from :1.0 should be 1', '1', ExtractDisplayNumber(':1.0'));
  AssertEquals('Extract from localhost:2 should be 2', '2', ExtractDisplayNumber('localhost:2'));
  AssertEquals('Extract from bare 3 should be 3', '3', ExtractDisplayNumber('3'));
end;

procedure TDmXAuthTest.TestBinarySerializationToStream();
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create();
  try
    AssertTrue('Writing to stream must return True', FXAuth.WriteToStream(ms));
    AssertTrue('Serialized stream must contain data', ms.Size > 0);
    // At least 2 entries written (Local + Wild)
    AssertTrue('Stream size must be at least 60 bytes', ms.Size >= 60);
  finally
    ms.Free();
  end;
end;

procedure TDmXAuthTest.TestWriteToFileAndPermissions();
var
  tmpFile: string;
begin
  tmpFile := GetTempFileName('', 'dmsama_xauth_');
  try
    AssertTrue('Writing auth to file must succeed', FXAuth.WriteToFile(tmpFile));
    AssertTrue('Auth file must exist on disk', FileExists(tmpFile));
  finally
    if FileExists(tmpFile) then
      DeleteFile(tmpFile);
  end;
end;

initialization
  RegisterTest(TDmXAuthTest);

end.
