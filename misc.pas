Unit Misc;

{$I compiler.inc}

interface

uses
    Classes, SysUtils, md5;

const
    SpinnerChars: string = '|/-\';

procedure Spinner(i : Int64);
procedure PctProgress(i, tot : Int64);
function DummyMD5Hash: TMD5Digest;
function CheckHash(Hash, HeaderHash : TMD5Digest) : boolean;


implementation

procedure Spinner(i : Int64);
begin
    Write(SpinnerChars[((i - 1) mod Length(SpinnerChars)) + 1]);
    Write(#8);
end;


procedure PctProgress(i, tot : Int64);
var
    Pct : Int64;
begin
    Pct := (100*i) div tot;
    Write(Pct:3,'%');
    Write(#8,#8,#8,#8);
end;


function DummyMD5Hash: TMD5Digest;
var
    MD5 : TMD5Digest;
    i : Integer;
begin
    for i := 0 to 15 do MD5[i] := $FF;
    result := MD5;
end;

function CheckHash(Hash, HeaderHash : TMD5Digest) : boolean;
var
    i : Integer;
begin
    CheckHash := True;
    for i := 0 to 15 do begin
        if Hash[i] <> HeaderHash[i] then CheckHash := False;
    end;
end;

begin
end.

