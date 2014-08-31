{$ifndef ALLPACKAGES}
{$mode objfpc}{$H+}
program fpmake;

uses fpmkunit;

Var
  P : TPackage;
  T : TTarget;
begin
  With Installer do
    begin
{$endif ALLPACKAGES}

    P:=AddPackage('arosunits');
{$ifdef ALLPACKAGES}
    P.Directory:=ADirectory;
{$endif ALLPACKAGES}
    P.Version:='2.7.1';

    P.Author := 'Marcus Sackrow';
    P.License := 'LGPL with modification';
    P.HomepageURL := 'www.freepascal.org';
    P.Email := '';
    P.Description := 'A set of units for AROS. Currently i386 only';
    P.NeedLibC:= false;

    P.CPUs:=[i386];
    P.OSes:=[aros];

    P.SourcePath.Add('src');
    P.IncludePath.Add('src');

    T:=P.Targets.AddUnit('agraphics.pas');
    T:=P.Targets.AddUnit('amigados.pas');
    T:=P.Targets.AddUnit('exec.pas');
    T:=P.Targets.AddUnit('hardware.pas');
    T:=P.Targets.AddUnit('inputevent.pas');
    T:=P.Targets.AddUnit('intuition.pas');
    T:=P.Targets.AddUnit('keymap.pas');
    T:=P.Targets.AddUnit('layers.pas');
    T:=P.Targets.AddUnit('longarray.pas');
    T:=P.Targets.AddUnit('tagsarray.pas');
    T:=P.Targets.AddUnit('timer.pas');
    T:=P.Targets.AddUnit('utility.pas');
    T:=P.Targets.AddUnit('diskfont.pas');
    T:=P.Targets.AddUnit('iffparse.pas');
    T:=P.Targets.AddUnit('clipboard.pas');
    T:=P.Targets.AddUnit('workbench.pas');
    T:=P.Targets.AddUnit('icon.pas');

{$ifndef ALLPACKAGES}
    Run;
    end;
end.
{$endif ALLPACKAGES}