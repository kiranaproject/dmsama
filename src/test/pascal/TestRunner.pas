program TestRunner;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, fpcunit, testregistry, consoletestrunner,
  DmSama.Config.Test,
  DmSama.XAuth.Test,
  DmSama.Session.Test,
  DmSama.PAM.Test;

var
  Application: TTestRunner;

begin
  Application := TTestRunner.Create(nil);
  try
    Application.Initialize();
    Application.Run();
  finally
    Application.Free();
  end;
end.
