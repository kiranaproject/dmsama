unit DmSama.Session.Test;

// DmSama.Session.Test
// ===================
// Unit tests for desktop session enumeration and command resolution.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  DmSama.Session;

type
  TDmSessionTest = class(TTestCase)
  published
    procedure TestEnumerateSessionsFromSystem();
    procedure TestEnumerateSessionsFromMockDir();
    procedure TestResolveSessionExecCommand();
    procedure TestFallbackWhenDirectoryEmpty();
  end;

implementation

procedure TDmSessionTest.TestEnumerateSessionsFromSystem();
var
  sessions: TSessionInfoArray;
begin
  sessions := TDmSessionManager.EnumerateSessions('/usr/share/xsessions');
  AssertTrue('System xsessions must return at least one session', Length(sessions) > 0);
  AssertTrue('First session must have non-empty key', Length(sessions[0].Key) > 0);
  AssertTrue('First session must have non-empty name', Length(sessions[0].Name) > 0);
end;

procedure TDmSessionTest.TestEnumerateSessionsFromMockDir();
var
  tmpDir: string;
  sl: TStringList;
  sessions: TSessionInfoArray;
begin
  tmpDir := IncludeTrailingPathDelimiter(GetTempFileName('', 'dmsama_xsess_'));
  ForceDirectories(tmpDir);
  sl := TStringList.Create();
  try
    sl.Add('[Desktop Entry]');
    sl.Add('Name=Test Desktop');
    sl.Add('Exec=test-session-cmd');
    sl.Add('Comment=Mock session for unit test');
    sl.SaveToFile(tmpDir + 'testdesk.desktop');

    sessions := TDmSessionManager.EnumerateSessions(tmpDir);
    AssertEquals('Must find exactly 1 mock session', 1, Length(sessions));
    AssertEquals('Key must match file stem', 'testdesk', sessions[0].Key);
    AssertEquals('Name must match entry', 'Test Desktop', sessions[0].Name);
    AssertEquals('Exec must match entry', 'test-session-cmd', sessions[0].ExecCmd);
  finally
    sl.Free();
    if FileExists(tmpDir + 'testdesk.desktop') then
      DeleteFile(tmpDir + 'testdesk.desktop');
    RemoveDir(tmpDir);
  end;
end;

procedure TDmSessionTest.TestResolveSessionExecCommand();
var
  tmpDir: string;
  sl: TStringList;
  execCmd: string;
begin
  tmpDir := IncludeTrailingPathDelimiter(GetTempFileName('', 'dmsama_resolv_'));
  ForceDirectories(tmpDir);
  sl := TStringList.Create();
  try
    sl.Add('[Desktop Entry]');
    sl.Add('Name=Samarinda');
    sl.Add('Exec=samarinda-session');
    sl.SaveToFile(tmpDir + 'samarinda.desktop');

    execCmd := TDmSessionManager.ResolveSessionExec('samarinda', tmpDir);
    AssertEquals('Resolved command must match session Exec', 'samarinda-session', execCmd);
  finally
    sl.Free();
    if FileExists(tmpDir + 'samarinda.desktop') then
      DeleteFile(tmpDir + 'samarinda.desktop');
    RemoveDir(tmpDir);
  end;
end;

procedure TDmSessionTest.TestFallbackWhenDirectoryEmpty();
var
  sessions: TSessionInfoArray;
begin
  sessions := TDmSessionManager.EnumerateSessions('/tmp/non_existent_xsessions_dir_xyz');
  AssertEquals('Empty or non-existent directory must fallback to 1 default session', 1, Length(sessions));
  AssertEquals('Fallback session key must be default', 'default', sessions[0].Key);
end;

initialization
  RegisterTest(TDmSessionTest);

end.
