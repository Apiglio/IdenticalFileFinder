unit iff_file_operation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, ShellApi, Windows, LazUTF8;


function IFF_Open(afilename:string):boolean;
function IFF_OpenDir(afilename:string):boolean;
function IFF_Delete(afilename:string;silent:boolean):boolean;

implementation

function IFF_Open(afilename:string):boolean;
var stmp:string;
begin
  result:=false;
  stmp:=Utf8ToWinCP(afilename);
  ShellExecute(0,'open',pchar('"'+stmp+'"'),'','',SW_NORMAL);
  result:=true;
end;

function IFF_OpenDir(afilename:string):boolean;
var stmp:string;
begin
  result:=false;
  stmp:=UTF8ToWinCP(afilename);
  ShellExecute(0,'open','explorer',pchar('/select,"'+StringReplace(stmp,'/','\',[rfReplaceAll])+'"'),nil,SW_NORMAL);
  result:=true;
end;

function IFF_Delete(afilename:string;silent:boolean):boolean;
var FileOp: TSHFileOpStruct;
begin
  if FileExists(afilename) then begin
    FillByte(FileOp, SizeOf(FileOp), 0);
    FileOp.wFunc := FO_DELETE;
    FileOp.pFrom := pchar(Utf8ToWinCP(afilename+#0));
    FileOp.fFlags := FOF_ALLOWUNDO;
    if silent then FileOp.fFlags:=FileOp.fFlags or FOF_SILENT or FOF_NOCONFIRMATION;
    Result:=SHFileOperation(FileOp)=0;
  end else Result:=false;
end;

end.

