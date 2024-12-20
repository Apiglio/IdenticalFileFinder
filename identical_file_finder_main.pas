unit identical_file_finder_main;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, Grids,
  StdCtrls, Menus, Types, md5;

const
  _version_str_ = '0.1.0';
  _hash_size_ = 16;

  {$ifdef WINDOWS}
    CRLF = #13#10;
  {$else}
    CRLF = #10;
  {$endif}

type

  TFileRecord = record
    fname :PChar;
    fhash :PByte;
    fsize :Int64;
    nsize :Int16;
    hsize :Int8;
    same_size :Int8;
    //four int8 variables remain
    procedure GetHash;
  end;
  PFileRecord = ^TFileRecord;

  TFileListEnumerator = class;
  TFileList = class
  private
    FFileList:TList;
  public
    procedure Add(aname:string;asize:int64);
    procedure Remove(index:Integer);
    procedure Sort;
    procedure Clear;
    constructor Create;
    destructor Destroy; override;
  public
    function GetEnumerator: TFileListEnumerator;
  public
    procedure LoadFromFile(filename:string);
    procedure SaveToFile(filename:string);
  end;

  TFileListEnumerator = class
  private
    PFileList: TFileList;
    FPosition: Integer;
  public
    constructor Create(AFileList: TFileList);
    function GetCurrent: TFileRecord;
    function MoveNext: Boolean;
    property Current: TFileRecord read GetCurrent;
  end;

  { TForm_IdenticalFileFinder }

  TForm_IdenticalFileFinder = class(TForm)
    MainMenu_IFF: TMainMenu;
    MenuItem_Tool_About: TMenuItem;
    MenuItem_Tool: TMenuItem;
    MenuItem_Analysis_SaveDirectory: TMenuItem;
    MenuItem_Analysis_LoadResult: TMenuItem;
    MenuItem_Analysis_div01: TMenuItem;
    MenuItem_Popup_SameSizeTitle: TMenuItem;
    MenuItem_Popup_CompareAll: TMenuItem;
    MenuItem_Popup_MakeUnique: TMenuItem;
    MenuItem_Popup_Rename: TMenuItem;
    MenuItem_Popup_div_01: TMenuItem;
    MenuItem_Popup_Delete: TMenuItem;
    MenuItem_Popup_OpenDir: TMenuItem;
    MenuItem_Popup_Open: TMenuItem;
    MenuItem_Display_MultiByteUnit: TMenuItem;
    MenuItem_Display_SameSizeOnly: TMenuItem;
    MenuItem_Display: TMenuItem;
    MenuItem_Analysis_OpenDirectory: TMenuItem;
    MenuItem_Analysis: TMenuItem;
    OpenDialog: TOpenDialog;
    PopupMenu_IFF: TPopupMenu;
    SaveDialog: TSaveDialog;
    SelectDirectoryDialog: TSelectDirectoryDialog;
    StringGrid_FileList: TStringGrid;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of String);
    procedure FormResize(Sender: TObject);
    procedure MenuItem_Analysis_LoadResultClick(Sender: TObject);
    procedure MenuItem_Analysis_OpenDirectoryClick(Sender: TObject);
    procedure MenuItem_Analysis_SaveDirectoryClick(Sender: TObject);
    procedure MenuItem_Display_MultiByteUnitClick(Sender: TObject);
    procedure MenuItem_Display_SameSizeOnlyClick(Sender: TObject);
    procedure MenuItem_Popup_DeleteClick(Sender: TObject);
    procedure MenuItem_Popup_OpenClick(Sender: TObject);
    procedure MenuItem_Popup_OpenDirClick(Sender: TObject);
    procedure MenuItem_Popup_RenameClick(Sender: TObject);
    procedure MenuItem_Tool_AboutClick(Sender: TObject);
    procedure StringGrid_FileListDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure StringGrid_FileListMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  public
    function MenuFunc_OpenDirectory(afilename:string):boolean;
    function MenuFunc_DeleteFile(list_index:integer):boolean;
  private
    function SelectedFilePath:string;
    function SelectedFileListIndex:integer;
    procedure FileListToStringGrid;

  public
    FileList:TFileList;
    DispOption:record
      SameSizeOnly:boolean;
      AutoMultiUnit:boolean;
      Colors:record
        Highlight_1:TColor;
        Highlight_2:TColor;
      end;
    end;
  end;

var
  Form_IdenticalFileFinder: TForm_IdenticalFileFinder;

implementation
uses iff_file_operation;

{$R *.lfm}

{ TFileRecord }
procedure TFileRecord.GetHash;
begin
  if not FileExists(fname) then exit;
  if fhash=nil then fhash:=GetMem(_hash_size_+1);
  PMDDigest(fhash)^:=md5.MD5File(fname);
  PMDDigest(fhash)^[_hash_size_]:=0;
  hsize:=_hash_size_;
end;

{ TFileList }

procedure TFileList.Add(aname:string;asize:int64);
var tmpFileRec:PFileRecord;
begin
  tmpFileRec:=GetMem(SizeOf(TFileRecord));
  with tmpFileRec^ do begin
    fsize:=asize;
    nsize:=length(aname);
    fname:=GetMem(nsize+1);
    StrCopy(fname,PChar(aname));
    fhash:=nil;
    hsize:=0;
    same_size:=0;
  end;
  FFileList.Add(tmpFileRec);
end;

procedure TFileList.Remove(index:Integer);
var tmpFileRec:TFileRecord;
begin
  if index>=FFileList.Count then raise Exception.Create('TFileList.Remore index out of bounds');
  if index<-FFileList.Count then raise Exception.Create('TFileList.Remore index out of bounds');
  if index<0 then index:=FFileList.Count+index;
  tmpFileRec:=PFileRecord(FFileList.Items[index])^;
  with tmpFileRec do FreeMem(fname,nsize+1);
  if tmpFileRec.hsize>0 then Freemem(tmpFileRec.fhash,tmpFileRec.hsize+1);
  FreeMem(FFileList.Items[index],SizeOf(TFileRecord));
  FFileList.Delete(index);
end;

function DoFileListSort(Item1,Item2:Pointer):Integer;
var difference:int64;
begin
  difference:=PFileRecord(Item2)^.fsize-PFileRecord(Item1)^.fsize;
  if difference>0 then result:=1 else if difference<0 then result:=-1 else result:=0;
end;

procedure TFileList.Sort;
var idx,curr_size,last_size:integer;
    curr_rec,last_rec:PFileRecord;
    same_flag:byte;//用来区分相邻的相同大小文件
begin
  FFileList.Sort(@DoFileListSort);
  idx:=0;
  same_flag:=1;
  last_size:=-1;
  last_rec:=PFileRecord(FFileList[0]);
  while idx<FFileList.Count do begin
    curr_rec:=PFileRecord(FFileList[idx]);
    curr_size:=curr_rec^.fsize;
    if last_size=curr_size then begin
      curr_rec^.same_size:=same_flag;
      last_rec^.same_size:=same_flag;
    end else begin
      if last_rec^.same_size<>0 then inc(same_flag);
    end;
    last_size:=curr_size;
    last_rec:=curr_rec;
    inc(idx);
  end;
end;

procedure TFileList.Clear;
var tmpFileRec:TFileRecord;
begin
  while FFileList.Count>0 do begin
    tmpFileRec:=PFileRecord(FFileList.Items[0])^;
    with tmpFileRec do FreeMem(fname,nsize+1);
    FreeMem(FFileList.Items[0],SizeOf(TFileRecord));
    FFileList.Delete(0);
  end;
end;

constructor TFileList.Create;
begin
  inherited Create;
  FFileList:=TList.Create;
end;

destructor TFileList.Destroy;
begin
  Clear;
  FFileList.Free;
  inherited Destroy;
end;

function TFileList.GetEnumerator: TFileListEnumerator;
begin
  result:=TFileListEnumerator.Create(Self);
end;

procedure TFileList.LoadFromFile(filename:string);
var Mem:TMemoryStream;
    tmpFileRec:PFileRecord;
begin
  FFileList.Clear;
  Mem:=TMemoryStream.Create;
  try
    Mem.LoadFromFile(filename);
    Mem.Position:=0;
    while Mem.Position<Mem.Size do begin
      tmpFileRec:=GetMem(SizeOf(TFileRecord));
      with tmpFileRec^ do begin
        fsize:=Mem.ReadQWord;        //file size
        nsize:=Mem.ReadWord;         //path size
        hsize:=Mem.ReadByte;         //hash size
        same_size:=Mem.ReadByte;     //same-size id
        Mem.Seek(4,soFromCurrent);   //preserve four bytes
        fname:=GetMem(nsize+1);
        Mem.ReadBuffer(fname^,nsize);
        (fname+nsize)^:=#0;
        if hsize>0 then begin
          fhash:=GetMem(hsize+1);
          Mem.ReadBuffer(fhash^,hsize);
          (fhash+hsize)^:=0;
        end;
      end;
      FFileList.Insert(0,tmpFileRec);
    end;
  finally
    Mem.Free;
  end;
end;

procedure TFileList.SaveToFile(filename:string);
var Mem:TMemoryStream;
    Idx:Integer;
begin
  Mem:=TMemoryStream.Create;
  try
    Mem.Position:=0;
    for Idx:=FFileList.Count-1 downto 0 do begin
      with PFileRecord(FFileList.Items[Idx])^ do begin;
        Mem.WriteQWord(fsize);       //file size
        Mem.WriteWord(nsize);        //path size
        Mem.WriteByte(hsize);        //hash size
        Mem.WriteByte(same_size);    //same-size id
        Mem.Seek(4,soFromCurrent);   //preserve four bytes
        Mem.WriteBuffer(fname^,nsize);
        if hsize>0 then Mem.WriteBuffer(fhash^,hsize);
      end;
    end;
    Mem.Position:=0;
    Mem.SaveToFile(filename);
  finally
    Mem.Free;
  end;
end;

{ TFileListEnumerator }
constructor TFileListEnumerator.Create(AFileList: TFileList);
begin
  PFileList:=AFileList;
  FPosition:=-1;
end;

function TFileListEnumerator.GetCurrent: TFileRecord;
begin
  result:=PFileRecord(PFileList.FFileList.Items[FPosition])^;
end;

function TFileListEnumerator.MoveNext: Boolean;
begin
  FPosition:=FPosition+1;
  result:=FPosition<PFileList.FFileList.Count;
end;


{ TForm_IdenticalFileFinder }

procedure TForm_IdenticalFileFinder.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  FileList.Free;
end;

procedure TForm_IdenticalFileFinder.FormCreate(Sender: TObject);
begin
  FileList:=TFileList.Create;
  with DispOption do begin
    SameSizeOnly:=false;
    AutoMultiUnit:=true;
    with Colors do begin
      Highlight_1:=$ffeedd;
      Highlight_2:=$eeccbb;
    end;
  end;
end;

procedure TForm_IdenticalFileFinder.FormDropFiles(Sender: TObject;
  const FileNames: array of String);
var ext:string;
begin
  if Length(FileNames)=1 then begin
    if DirectoryExists(FileNames[0]) then
      MenuFunc_OpenDirectory(FileNames[0])
    else begin
      ext:=ExtractFileExt(FileNames[0]);
      if lowercase(ext)='.ifs' then
      try
        FileList.LoadFromFile(FileNames[0]);
        FileListToStringGrid;
      except
        ShowMessage('导入ifs文件失败');
      end else ShowMessage('仅支持拖拽单个文件夹进行分析或导入ifs文件');
    end;
  end else ShowMessage('仅支持拖拽单个文件夹进行分析或导入ifs文件');
end;

procedure TForm_IdenticalFileFinder.FormResize(Sender: TObject);
begin
  StringGrid_FileList.DefaultColWidth:=32;
  StringGrid_FileList.Columns[0].Width:=120;
  StringGrid_FileList.Columns[1].Width:=StringGrid_FileList.Width-120-32-32;
  StringGrid_FileList.Columns[2].Width:=4;
end;

procedure TForm_IdenticalFileFinder.MenuItem_Analysis_LoadResultClick(
  Sender: TObject);
begin
  with OpenDialog do if Execute then begin
    FileList.LoadFromFile(FileName);
    FileListToStringGrid;
  end;
end;

procedure TForm_IdenticalFileFinder.MenuItem_Analysis_OpenDirectoryClick(
  Sender: TObject);
begin
  if SelectDirectoryDialog.Execute then begin
    if not MenuFunc_OpenDirectory(SelectDirectoryDialog.FileName) then ShowMessage('未知错误');
  end;
end;

procedure TForm_IdenticalFileFinder.MenuItem_Analysis_SaveDirectoryClick(
  Sender: TObject);
begin
  with SaveDialog do if Execute then begin
    FileList.SaveToFile(FileName);
  end;
end;

procedure TForm_IdenticalFileFinder.MenuItem_Display_MultiByteUnitClick(
  Sender: TObject);
var ThisMenuItem:TMenuItem;
begin
  ThisMenuItem:=Sender as TMenuItem;
  if ThisMenuItem.Checked then begin
    DispOption.AutoMultiUnit:=false;
  end else begin
    DispOption.AutoMultiUnit:=true;
  end;
  ThisMenuItem.Checked:=DispOption.AutoMultiUnit;
  FileListToStringGrid;
end;

procedure TForm_IdenticalFileFinder.MenuItem_Display_SameSizeOnlyClick(
  Sender: TObject);
var ThisMenuItem:TMenuItem;
begin
  ThisMenuItem:=Sender as TMenuItem;
  if ThisMenuItem.Checked then begin
    DispOption.SameSizeOnly:=false;
  end else begin
    DispOption.SameSizeOnly:=true;
  end;
  ThisMenuItem.Checked:=DispOption.SameSizeOnly;
  FileListToStringGrid;
end;

procedure TForm_IdenticalFileFinder.MenuItem_Popup_DeleteClick(Sender: TObject);
var list_index:integer;
begin
  list_index:=StrToInt(StringGrid_FileList.Cells[3,StringGrid_FileList.Row]);
  if MenuFunc_DeleteFile(list_index) then
    FileListToStringGrid;
end;

procedure TForm_IdenticalFileFinder.MenuItem_Popup_OpenClick(Sender: TObject);
var filename:string;
begin
  filename:=StringGrid_FileList.Cells[2,StringGrid_FileList.Row];
  IFF_Open(filename);
end;

procedure TForm_IdenticalFileFinder.MenuItem_Popup_OpenDirClick(Sender: TObject
  );
var filename:string;
begin
  filename:=StringGrid_FileList.Cells[2,StringGrid_FileList.Row];
  IFF_OpenDir(filename);
end;

procedure TForm_IdenticalFileFinder.MenuItem_Popup_RenameClick(Sender: TObject);
var list_index:integer;
begin
  //临时用于测试，并非重命名功能
  list_index:=StrToInt(StringGrid_FileList.Cells[3,StringGrid_FileList.Row]);
  PFileRecord(FileList.FFileList[list_index])^.GetHash;
  //
end;

procedure TForm_IdenticalFileFinder.MenuItem_Tool_AboutClick(Sender: TObject);
begin
  MessageDlg(
    '关于',
    'Apiglio Identical File Finder '+_version_str_
    +CRLF+'重复文件查找器'+CRLF
    +CRLF+'　　递归搜索文件目录，并将所有文件按文件大小排列。'
    +CRLF+'　　涉及文件操作时再额外对比文件是否完全相同。',
    mtCustom, [mbOK], 0
  );
end;

procedure TForm_IdenticalFileFinder.StringGrid_FileListDrawCell(
  Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
var number:string;
    background:TColor;
begin
  if aCol=0 then exit;
  if gdSelected in aState then exit;
  background:=StringGrid_FileList.Canvas.Brush.Color;
  number:=StringGrid_FileList.Cells[0,aRow];
  if number<>'' then begin
    StringGrid_FileList.Canvas.Brush.Style:=bsSolid;
    if ord(number[length(number)]) mod 2 = 0 then
      StringGrid_FileList.Canvas.Brush.Color:=DispOption.Colors.Highlight_1
    else
      StringGrid_FileList.Canvas.Brush.Color:=DispOption.Colors.Highlight_2;
    StringGrid_FileList.Canvas.FillRect(aRect);
  end;
  StringGrid_FileList.DefaultDrawCell(aCol,aRow,aRect,aState);
  StringGrid_FileList.Canvas.Brush.Color:=background;
end;

procedure TForm_IdenticalFileFinder.StringGrid_FileListMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var tmpCol,tmpRow:Longint;
begin
  StringGrid_FileList.MouseToCell(X,Y,tmpCol,tmpRow);
  if tmpCol<=0 then exit;
  if tmpRow<=0 then exit;
  StringGrid_FileList.Row:=tmpRow;
  StringGrid_FileList.Col:=tmpCol;
  StringGrid_FileList.SetFocus;
  if Button=mbRight then PopupMenu_IFF.PopUp;
end;

function ShowBytes_MultiUnit(byte_count:int64):string;
begin
  if byte_count>$80000000 then begin
    result:=FloatToStrF(byte_count / $40000000,ffFixed,8,3)+' GiB';
  end else if byte_count>$200000 then begin
    result:=FloatToStrF(byte_count / $100000,ffFixed,8,3)+' MiB';
  end else if byte_count>$800 then begin
    result:=FloatToStrF(byte_count / $400,ffFixed,8,3)+' KiB';
  end else begin
    result:=IntToStr(byte_count)+' B';
  end;
end;

function TForm_IdenticalFileFinder.SelectedFilePath:string;
begin
  result:=StringGrid_FileList.Cells[2,StringGrid_FileList.Row];
end;

function TForm_IdenticalFileFinder.SelectedFileListIndex:integer;
var list_index_str:string;
    codee:integer;
begin
  list_index_str:=StringGrid_FileList.Cells[3,StringGrid_FileList.Row];
  val(list_index_str, result, codee);
  if codee<0 then result:=-1;
end;

procedure TForm_IdenticalFileFinder.FileListToStringGrid;
var tmpFileRec:TFileRecord;
    idx,list_idx,sel_idx:int64;
    ShowFileSize:function(byte_count:int64):string;
begin
  if DispOption.AutoMultiUnit then ShowFileSize:=@ShowBytes_MultiUnit else ShowFileSize:=@IntToStr;

  sel_idx:=SelectedFileListIndex;
  if sel_idx<0 then sel_idx:=0;

  StringGrid_FileList.Clear;
  StringGrid_FileList.RowCount:=FileList.FFileList.Count+2;
  idx:=1;
  list_idx:=-1;
  for tmpFileRec in FileList do begin
    inc(list_idx);
    if DispOption.SameSizeOnly and (tmpFileRec.same_size=0) then continue;
    StringGrid_FileList.Cells[1,idx]:=ShowFileSize(tmpFileRec.fsize);
    StringGrid_FileList.Cells[2,idx]:=tmpFileRec.fname;
    if tmpFileRec.same_size<>0 then begin
      StringGrid_FileList.Cells[0,idx]:=IntToStr(tmpFileRec.same_size);
    end;
    StringGrid_FileList.Cells[3,idx]:=IntToStr(list_idx);
    if sel_idx=list_idx then StringGrid_FileList.Row:=idx;
    inc(idx);
  end;
  StringGrid_FileList.RowCount:=idx+1;
  FormResize(nil);
end;

function TForm_IdenticalFileFinder.MenuFunc_OpenDirectory(afilename:string):boolean;
var fsize:int64;
    tmpList:TStringList;
    filename:string;
begin
  result:=false;
  FileList.Clear;
  tmpList:=TStringList.Create;
  try
    FindAllFiles(tmpList,afilename,'*.*',true,faAnyFile);
    for filename in tmpList do begin
      fsize:=FileSize(filename);
      FileList.Add(filename,fsize);
    end;
  finally
    tmpList.Free;
  end;
  FileList.Sort;
  FileListToStringGrid;
  result:=true;
end;

function TForm_IdenticalFileFinder.MenuFunc_DeleteFile(list_index:integer):boolean;
var filename:string;
begin
  result:=false;
  filename:=PFileRecord(FileList.FFileList[list_index])^.fname;
  if IFF_Delete(filename,false) then begin
    FileList.Remove(list_index);
    result:=true;
  end;
end;

end.

