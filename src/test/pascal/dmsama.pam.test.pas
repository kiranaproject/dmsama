unit DmSama.PAM.Test;

// DmSama.PAM.Test
// ===============
// Unit tests for root PAM authentication wrapper in dmsama.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  DmSama.PAM;

type
  TDmPamTest = class(TTestCase)
  private
    FPam: TDmPam;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestPamSubsystemAvailability();
    procedure TestPamAuthenticationFailureWithNonExistentUser();
    procedure TestPamPutEnvWithoutSession();
  end;

implementation

procedure TDmPamTest.SetUp();
begin
  FPam := TDmPam.Create('dmsama');
end;

procedure TDmPamTest.TearDown();
begin
  if Assigned(FPam) then
  begin
    FPam.Free();
    FPam := nil;
  end;
end;

procedure TDmPamTest.TestPamSubsystemAvailability();
begin
  AssertNotNull('PAM wrapper must be initialized', FPam);
  AssertTrue('PAM subsystem must be available on Linux host', FPam.Available);
  AssertFalse('Session must not be open initially', FPam.SessionOpen);
end;

procedure TDmPamTest.TestPamAuthenticationFailureWithNonExistentUser();
var
  errMsg: string;
  ok: Boolean;
begin
  if not FPam.Available then Exit;

  errMsg := '';
  ok := FPam.Authenticate('non_existent_dmsama_user_99999', 'invalid_pw_99999', errMsg);
  AssertFalse('Authentication with non-existent user must return False', ok);
  AssertTrue('Error message must not be empty on rejection', Length(errMsg) > 0);
end;

procedure TDmPamTest.TestPamPutEnvWithoutSession();
begin
  // PutEnv on nil handle should safely return False without crashing
  AssertFalse('PutEnv on inactive PAM transaction should return False', FPam.PutEnv('TEST=1'));
end;

initialization
  RegisterTest(TDmPamTest);

end.
