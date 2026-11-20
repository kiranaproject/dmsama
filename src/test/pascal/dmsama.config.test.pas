unit DmSama.Config.Test;

// DmSama.Config.Test
// ==================
// Unit tests for dmsama configuration management and parsing.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  DmSama.Config;

type
  TDmConfigTest = class(TTestCase)
  private
    FConfig: TDmConfig;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestDefaultConfiguration();
    procedure TestLoadFromCustomFile();
    procedure TestSaveAndReloadConfiguration();
  end;

implementation

procedure TDmConfigTest.SetUp();
begin
  FConfig := TDmConfig.Create();
end;

procedure TDmConfigTest.TearDown();
begin
  if Assigned(FConfig) then
  begin
    FConfig.Free();
    FConfig := nil;
  end;
end;

procedure TDmConfigTest.TestDefaultConfiguration();
begin
  AssertNotNull('Config instance must be valid', FConfig);
  AssertEquals('Default display must be :0', ':0', FConfig.Display);
  AssertEquals('Default VT must be 7', 7, FConfig.VT);
  AssertEquals('Default greeter user must be dmsama', 'dmsama', FConfig.GreeterUser);
  AssertEquals('Default session must be mate', 'mate', FConfig.DefaultSession);
  AssertFalse('Auto login should be disabled by default', FConfig.AutoLogin);
  AssertTrue('XServer command must not be empty', Length(FConfig.XServerCmd) > 0);
end;

procedure TDmConfigTest.TestLoadFromCustomFile();
var
  tmpFile: string;
  sl: TStringList;
begin
  tmpFile := GetTempFileName('', 'dmsama_cfg_');
  sl := TStringList.Create();
  try
    sl.Add('[Daemon]');
    sl.Add('display=:2');
    sl.Add('vt=8');
    sl.Add('greeter=test-greeter');
    sl.Add('greeter_user=testuser');
    sl.Add('default_session=testsession');
    sl.Add('auto_login=true');
    sl.Add('auto_login_user=bob');
    sl.Add('[XServer]');
    sl.Add('command=/bin/true');
    sl.Add('args=-test');
    sl.Add('auth_dir=/tmp/testauth');
    sl.SaveToFile(tmpFile);

    AssertTrue('Loading valid config file should return True', FConfig.LoadFromFile(tmpFile));
    AssertEquals('Display must be updated to :2', ':2', FConfig.Display);
    AssertEquals('VT must be updated to 8', 8, FConfig.VT);
    AssertEquals('Greeter command must be updated', 'test-greeter', FConfig.GreeterCmd);
    AssertEquals('Greeter user must be updated', 'testuser', FConfig.GreeterUser);
    AssertEquals('Default session must be updated', 'testsession', FConfig.DefaultSession);
    AssertTrue('Auto login must be true', FConfig.AutoLogin);
    AssertEquals('Auto login user must be bob', 'bob', FConfig.AutoLoginUser);
    AssertEquals('XServer command must be updated', '/bin/true', FConfig.XServerCmd);
  finally
    sl.Free();
    if FileExists(tmpFile) then
      DeleteFile(tmpFile);
  end;
end;

procedure TDmConfigTest.TestSaveAndReloadConfiguration();
var
  tmpFile: string;
  loadedCfg: TDmConfig;
begin
  tmpFile := GetTempFileName('', 'dmsama_save_');
  try
    FConfig.Display := ':5';
    FConfig.VT := 9;
    FConfig.GreeterCmd := 'custom-greeter';
    FConfig.SaveToFile(tmpFile);

    loadedCfg := TDmConfig.Create();
    try
      AssertTrue('Reloading saved file must succeed', loadedCfg.LoadFromFile(tmpFile));
      AssertEquals('Display must match saved value', ':5', loadedCfg.Display);
      AssertEquals('VT must match saved value', 9, loadedCfg.VT);
      AssertEquals('Greeter command must match saved value', 'custom-greeter', loadedCfg.GreeterCmd);
    finally
      loadedCfg.Free();
    end;
  finally
    if FileExists(tmpFile) then
      DeleteFile(tmpFile);
  end;
end;

initialization
  RegisterTest(TDmConfigTest);

end.
