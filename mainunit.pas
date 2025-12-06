unit MainUnit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Buttons, SynHighlighterAny, SynEdit, SynHighlighterPosition, SynExportHTML,
  Hardware, LCLType;

const
  MaxDataLen=4096;

type
  TDeviceList=record
    Name,Description:string;
  end;
  TPortParam=record
    BitRate,Bits,Stops,Parity:integer;
  end;
  TRadek=record
    Time:TDateTime;
    Data:string;
    Completed,Timeout:boolean;
    Port:integer;
  end;

type

  { TMainForm }

  TMainForm = class(TForm)
    ClearBtn: TBitBtn;
    ColorDialog1: TColorDialog;
    EnCB1: TCheckBox;
    DeviceListTimer: TTimer;
    EnCB2: TCheckBox;
    EnCB3: TCheckBox;
    EnCB4: TCheckBox;
    DisplayTimeLabel: TLabel;
    ImageList1: TImageList;
    SetBtn: TBitBtn;
    ShapeInput: TShape;
    ShowCB1: TCheckBox;
    ShowCB2: TCheckBox;
    ShowCB3: TCheckBox;
    ShowCB4: TCheckBox;
    SendToCG: TCheckGroup;
    DeviceSelect1: TComboBox;
    DeviceSelect2: TComboBox;
    DeviceSelect3: TComboBox;
    DeviceSelect4: TComboBox;
    Input: TEdit;
    EOLRG: TRadioGroup;
    SendRG: TRadioGroup;
    Shape1: TShape;
    Shape2: TShape;
    Shape3: TShape;
    Shape4: TShape;
    Output: TSynEdit;
    DisplayTimeBtn: TSpeedButton;
    HistoryBtn: TSpeedButton;
    ShowAtOutputBtn: TSpeedButton;
    SynExporterHTML1: TSynExporterHTML;
    procedure ClearBtnClick(Sender: TObject);
    procedure DeviceListTimerTimer(Sender: TObject);
    procedure DeviceSelect1GetItems(Sender: TObject);
    procedure DisplayTimeBtnClick(Sender: TObject);
    procedure EnCB1Change(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure HistoryBtnClick(Sender: TObject);
    procedure InputChange(Sender: TObject);
    procedure InputUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
    procedure SetBtnClick(Sender: TObject);
    procedure Shape1MouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ShowAtOutputBtnClick(Sender: TObject);
    procedure ShowCB1Change(Sender: TObject);
  private
    PosHighlighter: TSynPositionHighlighter;
    LastFormat: TtkTokenKind;
    TextFormats: array[0..ChannelCount] of TtkTokenKind;
    InfoFormats: array[0..ChannelCount] of TtkTokenKind;
    DevList:array of TDeviceList;
    function OpenSerialPort(Port: integer; DeviceText: string):boolean;
    procedure CloseSerialPort(Port: integer);
    function NameExists(s:string):boolean;
  public
    Radky:array of TRadek;
    Displayed:integer;
    PortParams:array[0..ChannelCount-1] of TPortParam;
    DeviceListTimerRun:boolean;
    function IsDeviceUsed(DevName: string): integer;
    procedure AddFormatedText(Txt: string; Format: TtkTokenKind);
    procedure AddText(Txt: string);
    procedure DisplayLines;
  end;

  { TReceiveThread }

  TReceiveThread = class(TThread)
    procedure UpdateOutput;
    procedure PrepareOutput;
    procedure AddLine;
  protected
    procedure Execute; override;
  public
    Port:integer;
    s:string;
    Readed:integer;
    DataBuffer:array[0..MaxDataLen-1] of byte;
    TextBuffer:string;
    ReadPosition:integer;  // Pozice načtených dat
    ActiveLine:integer;
    Timeout:boolean;
    LinesAdded:boolean;
    ProcessingEnabled:boolean;
    constructor Create(CreateSuspended : boolean);
  end;

var
  MainForm: TMainForm;
  ReceiveThreads: array[0..ChannelCount-1] of TReceiveThread;

implementation

uses IniFiles,
     {$IFDEF linux}
       BaseUnix,Termio,
     {$ENDIF}
     {$IFDEF windows}
       Registry,Serial,
     {$ENDIF}
     LazUTF8,DateUtils,SettingsUnit,HistoryUnit;

{$R *.lfm}

{ TMainForm }

function MixColors(Col1,Col2:TColor):TColor;
var R,G,B:integer;
begin
  R:=(Red(Col1)+Red(Col2)) div 2;
  G:=(Green(Col1)+Green(Col2)) div 2;
  B:=(Blue(Col1)+Blue(Col2)) div 2;
  Result:=RGBToColor(R,G,B);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var f,x:integer;
    FColors:array[0..ChannelCount] of TColor;
    Soubor:TIniFile;
    Shape:TShape;
    Component:TComponent;
    CheckB:TCheckBox;
begin
  PosHighlighter := TSynPositionHighlighter.Create(MainForm);
  Output.Highlighter := PosHighlighter;
  FColors[0]:=Shape1.Brush.Color;
  FColors[1]:=Shape2.Brush.Color;
  FColors[2]:=Shape3.Brush.Color;
  FColors[3]:=Shape4.Brush.Color;
  FColors[4]:=ShapeInput.Brush.Color;
  DeviceListTimerRun:=false;

  for f:=0 to high(TextFormats) do
  begin
    TextFormats[f]:=PosHighlighter.CreateTokenID('Text_'+IntToStr(f), FColors[f], Output.Color, []);
    InfoFormats[f]:=PosHighlighter.CreateTokenID('Info_'+IntToStr(f), MixColors(FColors[f], Output.Color), Output.Color, [fsItalic]);
  end;
  LastFormat := tkText;

  SynExporterHTML1.Highlighter:=PosHighlighter;

  Displayed:=-1;

  {$IFDEF linux}
    Soubor:=TIniFile.Create(GetUserDir+'/.config/MUart.ini');
  {$ENDIF}
  {$IFDEF Windows}
    Soubor:=TIniFile.Create(GetAppConfigDir(true)+'MUart.ini');
  {$ENDIF}
  Output.Font.Name:=Soubor.ReadString('Font','Name',Output.Font.Name);
  Output.Font.Height:=Soubor.ReadInteger('Font','Height',Output.Font.Height);
  SendRG.ItemIndex:=Soubor.ReadInteger('Data','Send',SendRG.ItemIndex);
  EOLRG.ItemIndex:=Soubor.ReadInteger('Data','EOL',EOLRG.ItemIndex);
  x:=Soubor.ReadInteger('Data','To',1);
  for f:=0 to SendToCG.Items.Count-1 do SendToCG.Checked[f]:=x and (1 shl f)<>0;

  for f:=0 to ChannelCount-1 do
  begin
    PortParams[f].BitRate:=Soubor.ReadInteger('Ch'+IntToStr(f+1),'Bitrate',19200);
    PortParams[f].Bits:=Soubor.ReadInteger('Ch'+IntToStr(f+1),'Bits',8);
    PortParams[f].Parity:=Soubor.ReadInteger('Ch'+IntToStr(f+1),'Parity',0);
    PortParams[f].Stops:=Soubor.ReadInteger('Ch'+IntToStr(f+1),'Stops',1);
    Component:=FindComponent('Shape'+IntToStr(f+1));
    if Component<>nil then if Component is TShape then
    begin
      Shape:=Component as TShape;
      Shape.Brush.Color:=Soubor.ReadInteger('Ch'+IntToStr(f+1),'Color',Shape.Brush.Color);
    end;
    Component:=FindComponent('ShowCB'+IntToStr(f+1));
    if Component<>nil then if Component is TCheckBox then
    begin
      CheckB:=Component as TCheckBox;
      CheckB.Checked:=Soubor.ReadBool('Ch'+IntToStr(f+1),'Show',CheckB.Checked);
    end;
    ReceiveThreads[f]:=nil;
    {$IFDEF linux}
      SerialPorts[f]:=-1;
    {$ENDIF}
    {$IFDEF Windows}
      SerialPorts[f]:=0;
    {$ENDIF}
  end;
  ShapeInput.Brush.Color:=Soubor.ReadInteger('Input','Color',ShapeInput.Brush.Color);
  Soubor.Free;

  SendToCG.Checked[0]:=true;

  Output.Clear;
end;

procedure TMainForm.HistoryBtnClick(Sender: TObject);
begin
  HistoryForm.Visible:=not HistoryForm.Visible;
  HistoryForm.Left:=MainForm.Left+MainForm.Width;
  HistoryForm.Top:=MainForm.Top;
  HistoryForm.Height:=MainForm.Height;
end;

procedure TMainForm.InputChange(Sender: TObject);
begin

end;

procedure TMainForm.InputUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
var s:string;
    f,x,err,Vys:integer;
    Second:boolean;
    Pole:array of byte;
    ActiveLine:integer;
begin
  if SendRG.ItemIndex=0 then
  begin
    if UTF8Key=#13 then
    begin
      s:='';
      case EOLRG.ItemIndex of
        0:s:=#10;
        1:s:=#13;
        2:s:=#13#10;
      end;
      ActiveLine:=Length(Radky);
      Setlength(Radky,ActiveLine+1);
      Radky[ActiveLine].Completed:=true;
      Radky[ActiveLine].Time:=Now;
      Radky[ActiveLine].Port:=ChannelCount;
      Radky[ActiveLine].Timeout:=false;
      Radky[ActiveLine].Data:=Input.Text;
      DisplayLines;
      if s<>'' then
      begin
        for f:=0 to ChannelCount-1 do if (SerialAssigned(f))and(SendToCG.Checked[f]) then WriteSerial(f,@s[1],length(s));
      end;
      if HistoryForm.ListBox1.Items.IndexOf(Input.Text)=-1 then HistoryForm.ListBox1.Items.Add(Input.Text);
      Input.Clear;
    end else begin
      for f:=0 to ChannelCount-1 do if (SerialAssigned(f))and(SendToCG.Checked[f]) then WriteSerial(f,@UTF8Key[1],length(UTF8Key));
    end;
  end;
  if (SendRG.ItemIndex=1)and(UTF8Key=#13) then
  begin
    s:=Input.Text;
    case EOLRG.ItemIndex of
      0:s:=s+#10;
      1:s:=s+#13;
      2:s:=s+#13#10;
    end;
    ActiveLine:=Length(Radky);
    Setlength(Radky,ActiveLine+1);
    Radky[ActiveLine].Completed:=true;
    Radky[ActiveLine].Time:=Now;
    Radky[ActiveLine].Port:=ChannelCount;
    Radky[ActiveLine].Timeout:=false;
    Radky[ActiveLine].Data:=Input.Text;
    DisplayLines;
    for f:=0 to ChannelCount-1 do if (SerialAssigned(f))and(SendToCG.Checked[f]) then WriteSerial(f,@s[1],length(s));
    if HistoryForm.ListBox1.Items.IndexOf(Input.Text)=-1 then HistoryForm.ListBox1.Items.Add(Input.Text);
    Input.Clear;
  end;
  if (SendRG.ItemIndex=2)and(UTF8Key=#13) then
  begin
    s:=Input.Text;
    Second:=false;
    Vys:=0;
    SetLength(Pole,0);
    for f:=0 to length(s) do
    begin
      val('$'+s[f],x,err);
      if err=0 then
      begin
        if Second then
        begin
          vys:=(vys shl 4) or x;
          SetLength(Pole,Length(Pole)+1);
          Pole[High(Pole)]:=vys;
        end else vys:=x;
        Second:=not Second;
      end else if Second then
      begin
        SetLength(Pole,Length(Pole)+1);
        Pole[High(Pole)]:=vys;
        Second:=false;
      end;
    end;

    if Second then
    begin
      SetLength(Pole,Length(Pole)+1);
      Pole[High(Pole)]:=vys;
    end;

    ActiveLine:=Length(Radky);
    Setlength(Radky,ActiveLine+1);
    Radky[ActiveLine].Completed:=true;
    Radky[ActiveLine].Time:=Now;
    Radky[ActiveLine].Port:=ChannelCount;
    Radky[ActiveLine].Timeout:=false;
    Radky[ActiveLine].Data:=Input.Text;
    DisplayLines;

    for f:=0 to ChannelCount-1 do if (SerialAssigned(f))and(SendToCG.Checked[f]) then WriteSerial(f,@Pole[0],length(Pole));
    if HistoryForm.ListBox1.Items.IndexOf(Input.Text)=-1 then HistoryForm.ListBox1.Items.Add(Input.Text);
    Input.Clear;
    SetLength(Pole,0);
  end;
end;

procedure TMainForm.SetBtnClick(Sender: TObject);
var Component:TComponent;
    Index:integer;
begin
  Index:=SettingsForm.ChannelCB.ItemIndex;
  Component:=FindComponent('Shape'+IntToStr(Index+1));
  if Component is TShape then SettingsForm.Shape1.Brush.Color:=(Component as TShape).Brush.Color;
  SettingsForm.RychlostEdit.Value:=MainForm.PortParams[Index].BitRate;
  SettingsForm.BitsEdit.Value:=MainForm.PortParams[Index].Bits;
  SettingsForm.StopsCB.ItemIndex:=MainForm.PortParams[Index].Stops-1;
  SettingsForm.ParityCB.ItemIndex:=MainForm.PortParams[Index].Parity;
  SettingsForm.ShowModal;
end;

procedure TMainForm.Shape1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var Shape:TShape;
begin
  Shape:=Sender as TShape;
  ColorDialog1.Color:=Shape.Brush.Color;
  if ColorDialog1.Execute then
  begin
    Shape.Brush.Color:=ColorDialog1.Color;
    PosHighlighter.GetCopiedAttribute(TextFormats[Shape.Tag-1]).Foreground:=Shape.Brush.Color;
    PosHighlighter.GetCopiedAttribute(InfoFormats[Shape.Tag-1]).Foreground:= MixColors(Shape.Brush.Color, Output.Color);
  end;
end;

procedure TMainForm.ShowAtOutputBtnClick(Sender: TObject);
begin
  if ShowAtOutputBtn.Down then ShowAtOutputBtn.ImageIndex:=0
                          else ShowAtOutputBtn.ImageIndex:=1;
  Displayed:=-1;
  Output.Clear;
  DisplayLines;
end;

procedure TMainForm.ShowCB1Change(Sender: TObject);
begin
  Displayed:=-1;
  Output.Clear;
  DisplayLines;
end;

function TMainForm.OpenSerialPort(Port: integer; DeviceText: string):boolean;
var
{$IFDEF linux}
  SerialOptions:TermIOS;
  i:integer;
{$ENDIF}
{$IFDEF Windows}
  x:integer;
  s:string;
{$ENDIF}
  f:integer;
  SerialIndex:integer;
  SerialName:string;
begin
  Result:=false;

  if(Port<0)or(Port>High(SerialPorts)) then exit;

  // Pokud je port otevřený, zavřeme ho
  CloseSerialPort(Port);

  DeviceListTimer.Enabled:=false;

  SerialIndex:=-1;
  // Najdeme jméno sériového portu
  for f:=0 to High(DevList) do
  begin
    if DeviceText=DevList[f].Description+' ('+DevList[f].Name+')' then
    begin
      SerialIndex:=f;
      break;
    end;
  end;
  if SerialIndex=-1 then
  begin
    DeviceListTimer.Enabled:=true;
    exit;
  end;

  {$IFDEF Windows}
    SerialName:=DevList[SerialIndex].Name;
    s:='\\.\'+SerialName;
    SerialPorts[Port]:=SerOpen(s);
    if SerialPorts[Port]=0 then
    begin
      MessageDlg('Chyba otevírání sériového portu '+SerialName,mtError,[mbAbort],0);
      DeviceListTimer.Enabled:=true;
      exit;
    end;
    SerSetParams(SerialPorts[Port],PortParams[Port].BitRate,PortParams[Port].Bits,NoneParity,PortParams[Port].Stops,[]);
    Sleep(200);
    ClearBuffers(Port);
  {$ENDIF}
  {$IFDEF linux}
    SerialName:='/dev/'+DevList[SerialIndex].Name;
    if IsDeviceUsed(DevList[SerialIndex].Name)<>-1 then
    begin
      MessageDlg('Zařízení '+SerialName+' je již používáno jiným programem',mtError,[mbAbort],0);
      DeviceListTimer.Enabled:=true;
      exit;
    end;
    SerialPorts[Port]:=fpOpen(SerialName,O_RDWR or O_NOCTTY or O_NONBLOCK); // or O_NONBLOCK
    if (SerialPorts[Port]<0) then
    begin
      MessageDlg('Chyba otevírání sériového portu '+SerialName,mtError,[mbAbort],0);
      DeviceListTimer.Enabled:=true;
      exit;
    end;
    if fpfcntl(SerialPorts[Port],F_SETFL,0)<0 then
    begin
      MessageDlg('Chyba nastavení FCNTL '+SerialName,mtError,[mbAbort],0);
      DeviceListTimer.Enabled:=true;
      exit;
    end;
    if tcgetattr(SerialPorts[Port],SerialOptions)<0 then
    begin
      MessageDlg('Nemohu zjistit vlastnosti '+SerialName,mtError,[mbAbort],0);
      DeviceListTimer.Enabled:=true;
      exit;
    end;
    i:=B115200;
    case PortParams[Port].BitRate of
      50:i:=B50;
      75:i:=B75;
      110:i:=B110;
      134:i:=B134;
      150:i:=B150;
      200:i:=B200;
      300:i:=B300;
      600:i:=B600;
      1200:i:=B1200;
      1800:i:=B1800;
      2400:i:=B2400;
      4800:i:=B4800;
      9600:i:=B9600;
      19200:i:=B19200;
      38400:i:=B38400;
      57600:i:=B57600;
      115200:i:=B115200;
      230400:i:=B230400;
      460800:i:=B460800;
      500000:i:=B500000;
      576000:i:=B576000;
      921600:i:=B921600;
      1000000:i:=B1000000;
      1152000:i:=B1152000;
      1500000:i:=B1500000;
      2000000:i:=B2000000;
      2500000:i:=B2500000;
      3000000:i:=B3000000;
      3500000:i:=B3500000;
      4000000:i:=B4000000;
    end;
    cfsetispeed(SerialOptions,i);
    cfsetospeed(SerialOptions,i);
    SerialOptions.c_cflag:=SerialOptions.c_cflag and not (PARENB or CSTOPB or CSIZE or CRTSCTS);
    SerialOptions.c_lflag:=SerialOptions.c_lflag and not (ICANON or ECHO or ECHOE or ISIG or IXON or IXOFF or IXANY or OPOST);
    SerialOptions.c_iflag:=SerialOptions.c_iflag and not (INPCK or IXON or IXOFF or IXANY or INLCR or IGNCR or ICRNL or IUCLC or IMAXBEL);
    SerialOptions.c_oflag:=SerialOptions.c_oflag and not OPOST;
    i:=CS8;
    case PortParams[Port].Bits of
      5:i:=CS5;
      6:i:=CS6;
      7:i:=CS7;
    end;
    // 2 stop bity
    if PortParams[Port].Stops=2 then i:=i or CSTOPB;
    if PortParams[Port].Parity>0 then
    begin
      i:=i or PARENB;
      if PortParams[Port].Parity=1 then i:=i or PARODD;  // Lichá parita, jinak je sudá, když je PARENB
    end;
    SerialOptions.c_cflag:=SerialOptions.c_cflag or CLOCAL or CREAD or i;
    SerialOptions.c_cc[VTIME]:=0;
    SerialOptions.c_cc[VMIN]:=0;
    if tcsetattr(SerialPorts[Port],TCSANOW,SerialOptions)<0 then
    begin
      MessageDlg('Chyba nastavení parametrů linky '+SerialName,mtError,[mbAbort],0);
      DeviceListTimer.Enabled:=true;
      exit;
    end;
    Sleep(200);
    tcflush(SerialPorts[Port],TCIFLUSH);
  {$ENDIF}
  DeviceListTimer.Enabled:=true;
  ReceiveThreads[Port]:=TReceiveThread.Create(true);
  ReceiveThreads[Port].Port:=Port;
  ReceiveThreads[Port].ProcessingEnabled:=true;
  if Assigned(ReceiveThreads[Port].FatalException) then raise ReceiveThreads[Port].FatalException;
  ReceiveThreads[Port].Start;
  Result:=true;
end;

procedure TMainForm.CloseSerialPort(Port: integer);
begin
  if(Port<0)or(Port>High(SerialPorts)) then exit;

  if Assigned(ReceiveThreads[Port]) then
  begin
    ReceiveThreads[Port].Terminate;
    ReceiveThreads[Port].WaitFor;
    ReceiveThreads[Port]:=nil;
  end;
  if SerialAssigned(Port) then CloseSerial(Port);
end;

function TMainForm.NameExists(s: string): boolean;
var f:integer;
begin
  Result:=true;
  for f:=0 to High(DevList) do if DevList[f].Name=s then exit;
  Result:=false;
end;

// Prohledá adresář /proc a najde, jestli je již file descriptor používán jiným programem, vrací -1 (nepoužíváno) nebo PID
// Poměrně pomalé
function TMainForm.IsDeviceUsed(DevName: string): integer;
{$IFDEF linux}
var Src,fdList:TSearchRec;
    IsPID:boolean;
    f:integer;
    s:string;
{$ENDIF}
begin
  {$IFDEF linux}
    DevName:='/dev/'+DevName;
    if FindFirst('/proc/*',faDirectory,Src)=0 then
    repeat
      // Získám jen procesy (PID je číslo)
      IsPID:=true;
      for f:=1 to Length(Src.Name) do
        if (Src.Name[f]<'0')or(Src.Name[f]>'9') then
        begin
          IsPID:=false;
          break;
        end;
      if IsPID then
      begin
        // Každý proces obsahuje adresář fd, v něm jsou file descriptory, tedy i link na DevName
        if FindFirst('/proc/'+Src.Name+'/fd/*',faSymLink,fdList)=0 then
        repeat
          s:=fpReadLink('/proc/'+Src.Name+'/fd/'+fdList.Name);
          if s=DevName then
          begin
            val(Src.Name,Result,f);
            FindClose(fdList);
            FindClose(Src);
            Exit;
          end;
        until FindNext(fdList)<>0;
        FindClose(fdList);
      end;
    until FindNext(Src)<>0;
    FindClose(Src);
    Result:=-1;
  {$ELSE}
    Result:=-1;
  {$ENDIF}
end;

procedure TMainForm.DeviceListTimerTimer(Sender: TObject);
var
  {$IFDEF Windows}
    Reg:TRegistry;
    RegList:TStringList;
  {$ENDIF}
  {$IFDEF linux}
    Src,Src2:TSearchRec;
    Soubor:TextFile;
    Jmeno,s:string;
  {$ENDIF}
  f,g:integer;
  Comp:TComponent;
  DS:TComboBox;
  Found:boolean;
  Selected:string;
  //BylaZmena:boolean;
begin
  DeviceListTimerRun:=true;
  SetLength(DevList,0);
  {$IFDEF linux}
    // Hledáme jméno v /sys/bus/usb-serial/devices
    if FindFirst('/sys/bus/usb-serial/devices/*',faDirectory,Src)=0 then
    repeat
      if (Src.Attr and faDirectory)<>0 then
      begin
        s:=fpReadLink('/sys/bus/usb-serial/devices/'+Src.Name);
        if s<>'' then
        begin
          s:=ExpandFileName('/sys/bus/usb-serial/devices/'+s+'/../../product');
          // Jestliže soubor existuje a můžeme ho přečíst
          try
            AssignFile(Soubor,s);Reset(Soubor);
            ReadLn(Soubor,Jmeno);
            //s:=Jmeno + ' ('+Src.Name+')';
            SetLength(DevList,Length(DevList)+1);
            DevList[High(DevList)].Name:=Src.Name;
            DevList[High(DevList)].Description:=Jmeno;
          finally
            CloseFile(Soubor);
          end;
        end;
      end;
    until FindNext(Src)<>0;
    FindClose(Src);
    if FindFirst('/sys/bus/usb/drivers/cdc_acm/*',faDirectory,Src)=0 then
    repeat
      if DirectoryExists('/sys/bus/usb/drivers/cdc_acm/'+Src.Name+'/tty') then
      begin
        if FindFirst('/sys/bus/usb/drivers/cdc_acm/'+Src.Name+'/tty/*',faDirectory,Src2)=0 then
        repeat
          if ((Src.Attr and faDirectory)<>0)and(FileExists('/sys/bus/usb/drivers/cdc_acm/'+Src.Name+'/interface'))and(Src2.Name<>'.')and(Src2.Name<>'..') then
          begin
            try
              AssignFile(Soubor,'/sys/bus/usb/drivers/cdc_acm/'+Src.Name+'/interface');Reset(Soubor);
              ReadLn(Soubor,Jmeno);
              SetLength(DevList,Length(DevList)+1);
              DevList[High(DevList)].Name:=Src2.Name;
              DevList[High(DevList)].Description:=Jmeno;
            finally
              CloseFile(Soubor);
            end;
          end else if (Src2.Name<>'.')and(Src2.Name<>'..') then begin
            s:=copy(Src.Name,1,pos(':',Src.Name)-1);
            if FileExists('/sys/bus/usb/devices/'+s+'/product') then
            try
              AssignFile(Soubor,'/sys/bus/usb/devices/'+s+'/product');Reset(Soubor);
              ReadLn(Soubor,Jmeno);
              SetLength(DevList,Length(DevList)+1);
              DevList[High(DevList)].Name:=Src2.Name;
              DevList[High(DevList)].Description:=Jmeno;
            finally
              CloseFile(Soubor);
            end;
          end;
        until FindNext(Src2)<>0;
        FindClose(Src2);
      end;
    until FindNext(Src)<>0;
    FindClose(Src);
    // Add devices ttyUSBx without description
    if FindFirst('/dev/ttyUSB*',faSysFile,Src)=0 then
    repeat
      if not NameExists(Src.Name) then
      begin
        SetLength(DevList,Length(DevList)+1);
        DevList[High(DevList)].Name:=Src.Name;
        DevList[High(DevList)].Description:='?';
      end;
    until FindNext(Src)<>0;
    FindClose(Src);
    // Add devices ttyACMx without description
    if FindFirst('/dev/ttyACM*',faSysFile,Src)=0 then
    repeat
      if not NameExists(Src.Name) then
      begin
        SetLength(DevList,Length(DevList)+1);
        DevList[High(DevList)].Name:=Src.Name;
        DevList[High(DevList)].Description:='?';
      end;
    until FindNext(Src)<>0;
    FindClose(Src);
  {$ENDIF}

  {$IFDEF Windows}
    // Prohledat registry
    RegList:=TStringList.Create;
    Reg:=TRegistry.Create;
    try
      Reg.RootKey:=HKEY_LOCAL_MACHINE;
      if Reg.OpenKeyReadOnly('HARDWARE\DEVICEMAP\SERIALCOMM') then
      begin
        Reg.GetValueNames(RegList);
        SetLength(DevList,RegList.Count);
        for f:=0 to RegList.Count-1 do
        begin
          DevList[f].Name:=Reg.ReadString(RegList[f]);
          DevList[f].Description:=RegList[f];
        end;
      end;
    finally
      Reg.Free;
    end;
  {$ENDIF}

  // Pro jednotlivé USB zjistíme, jestli nedošlo k jejich odpojení
  for f:=0 to ChannelCount-1 do
  begin
    {$IFDEF linux}
    if SerialPorts[f]<>-1 then
    {$ENDIF}
    {$IFDEF Windows}
    if SerialPorts[f]<>0 then
    {$ENDIF}
    begin
      Comp:=FindComponent('DeviceSelect'+IntToStr(f+1));
      if Comp<>nil then
      begin
        if Comp is TComboBox then
        begin
          DS:=Comp as TComboBox;
          Selected:=DS.Text;
          Found:=false;
          for g:=0 to High(DevList) do
          begin
            if Selected=DevList[g].Description+' ('+DevList[g].Name+')' then Found:=true;
          end;
          if (not Found)and(SerialAssigned(f)) then CloseSerialPort(f);
        end;
      end;
    end;
  end;

  // Naplníme jednotlivé DeviceSelect
  {for f:=0 to ChannelCount-1 do
  begin
    Comp:=FindComponent('DeviceSelect'+IntToStr(f+1));
    if Comp<>nil then
    begin
      if Comp is TComboBox then
      begin
        DS:=Comp as TComboBox;
        BylaZmena:=false;
        if Length(DevList)<>DS.Items.Count then BylaZmena:=true
        else for g:=0 to High(DevList) do if IsDeviceUsed(DevList[g].Name)=-1 then
        begin
          if DS.Items[g]<>DevList[g].Description+' ('+DevList[g].Name+')' then BylaZmena:=true;
        end;
        if BylaZmena then
        begin
          DS.Items.Clear;
          for g:=0 to High(DevList) do if IsDeviceUsed(DevList[g].Name)=-1 then
          begin
            DS.Items.Add(DevList[g].Description+' ('+DevList[g].Name+')');
          end;
        end;
      end;
    end;
  end;}
  DeviceListTimerRun:=false;
end;

procedure TMainForm.DeviceSelect1GetItems(Sender: TObject);
var
  g:integer;
  DS:TComboBox;
  BylaZmena:boolean;
begin
  while DeviceListTimerRun do Sleep(1);
  DeviceListTimer.Enabled:=false;
  if Sender is TComboBox then
  begin
    DS:=Sender as TComboBox;
    BylaZmena:=false;
    if Length(DevList)<>DS.Items.Count then BylaZmena:=true
    else for g:=0 to High(DevList) do if IsDeviceUsed(DevList[g].Name)=-1 then
    begin
      if DS.Items[g]<>DevList[g].Description+' ('+DevList[g].Name+')' then BylaZmena:=true;
    end;
    if BylaZmena then
    begin
      DS.Items.Clear;
      for g:=0 to High(DevList) do if IsDeviceUsed(DevList[g].Name)=-1 then
      begin
        DS.Items.Add(DevList[g].Description+' ('+DevList[g].Name+')');
      end;
    end;
  end;
  DeviceListTimer.Enabled:=true;
end;

procedure TMainForm.DisplayTimeBtnClick(Sender: TObject);
begin
  DisplayTimeBtn.Tag:=DisplayTimeBtn.Tag+1;
  if DisplayTimeBtn.Tag>2 then DisplayTimeBtn.Tag:=0;
  case DisplayTimeBtn.Tag of
    0:DisplayTimeLabel.Caption:='Nezobrazovat';
    1:DisplayTimeLabel.Caption:='Zobrazit delta';
    2:DisplayTimeLabel.Caption:='Zobrazit čas';
  end;
  Displayed:=-1;
  Output.Clear;
  DisplayLines;
end;

// Vymaže řádky s tím, že něco může být v mezipaměti. To se nemaže.
procedure TMainForm.ClearBtnClick(Sender: TObject);
var f,MinActiveLine,MaxActiveLine:integer;
begin
  // Zastavit zpracování dat a počkat na dokončení možného zpracování
  for f:=0 to high(ReceiveThreads) do
    if Assigned(ReceiveThreads[f]) then ReceiveThreads[f].ProcessingEnabled:=false;
  Sleep(10);
  // Najdeme minimální a maximální ActiveLine
  MinActiveLine:=-1;
  MaxActiveLine:=-1;
  for f:=0 to high(ReceiveThreads) do if Assigned(ReceiveThreads[f]) then
  begin
    if (f=0)or(MinActiveLine<ReceiveThreads[f].ActiveLine) then MinActiveLine:=ReceiveThreads[f].ActiveLine;
    if (f=0)or(MaxActiveLine>ReceiveThreads[f].ActiveLine) then MaxActiveLine:=ReceiveThreads[f].ActiveLine;
  end;
  if MaxActiveLine>=0 then SetLength(Radky,MaxActiveLine-MinActiveLine+1)
                      else SetLength(Radky,0);
  for f:=0 to high(ReceiveThreads) do if Assigned(ReceiveThreads[f]) then
      if ReceiveThreads[f].ActiveLine>-1 then ReceiveThreads[f].ActiveLine:=ReceiveThreads[f].ActiveLine-MinActiveLine;
  Displayed:=-1;
  Output.Clear;
  // Povolit zpracování dat
  for f:=0 to high(ReceiveThreads) do
    if Assigned(ReceiveThreads[f]) then ReceiveThreads[f].ProcessingEnabled:=true;
end;

procedure TMainForm.EnCB1Change(Sender: TObject);
var
  TCB:TCheckBox;
  Comp:TComponent;
  DS:TComboBox;
begin
  TCB:=Sender as TCheckBox;
  if TCB.Checked then
  begin
    Comp:=FindComponent('DeviceSelect'+IntToStr(TCB.Tag));
    if Comp<>nil then
    begin
      if Comp is TComboBox then
      begin
        DS:=Comp as TComboBox;
        if DS.Items.IndexOf(DS.Text)<0 then
        begin
          TCB.Checked:=false;
          exit;
        end;
        if not OpenSerialPort(TCB.Tag-1,DS.Text) then TCB.Checked:=false;
      end;
    end;
  end else begin
    CloseSerialPort(TCB.Tag-1);
  end;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var f,x:integer;
    Soubor:TIniFile;
    Shape:TShape;
    Component:TComponent;
    CheckB:TCheckBox;
begin
  for f:=0 to ChannelCount-1 do CloseSerialPort(f);
  SetLength(Radky,0);
  {$IFDEF linux}
    Soubor:=TIniFile.Create(GetUserDir+'/.config/MUart.ini');
  {$ENDIF}
  {$IFDEF Windows}
    Soubor:=TIniFile.Create(GetAppConfigDir(true)+'MUart.ini');
  {$ENDIF}
  Soubor.WriteString('Font','Name',Output.Font.Name);
  Soubor.WriteInteger('Font','Height',Output.Font.Height);
  Soubor.WriteInteger('Data','Send',SendRG.ItemIndex);
  Soubor.WriteInteger('Data','EOL',EOLRG.ItemIndex);
  x:=0;
  for f:=0 to SendToCG.Items.Count-1 do if SendToCG.Checked[f] then x:=x or (1 shl f);
  Soubor.WriteInteger('Data','To',x);
  for f:=0 to ChannelCount-1 do
  begin
    Soubor.WriteInteger('Ch'+IntToStr(f+1),'Bitrate',PortParams[f].BitRate);
    Soubor.WriteInteger('Ch'+IntToStr(f+1),'Bits',PortParams[f].Bits);
    Soubor.WriteInteger('Ch'+IntToStr(f+1),'Parity',PortParams[f].Parity);
    Soubor.WriteInteger('Ch'+IntToStr(f+1),'Stops',PortParams[f].Stops);
    Component:=FindComponent('Shape'+IntToStr(f+1));
    if Component<>nil then if Component is TShape then
    begin
      Shape:=Component as TShape;
      Soubor.WriteInteger('Ch'+IntToStr(f+1),'Color',Shape.Brush.Color);
    end;
    Component:=FindComponent('ShowCB'+IntToStr(f+1));
    if Component<>nil then if Component is TCheckBox then
    begin
      CheckB:=Component as TCheckBox;
      Soubor.WriteBool('Ch'+IntToStr(f+1),'Show',CheckB.Checked);
    end;
  end;
  Soubor.WriteInteger('Input','Color',ShapeInput.Brush.Color);
  Soubor.Free;
end;

procedure TMainForm.AddFormatedText(Txt: string; Format: TtkTokenKind);
var
  Line, Col: integer;
  s: string;
begin
  Line := Output.Lines.Count - 1;
  if Line < 0 then
  begin
    Output.Lines.Add('');
    Line := 0;
    PosHighlighter.ClearAllTokens;
  end;
  Col := Length(Output.Lines[Line]);
  //Vypis.LineText:=Vypis.LineText+Txt;
  s   := Output.Lines[Line] + Txt;
  Output.Lines[Line] := s;
  if PosHighlighter.Tokens[Line] = nil then
    PosHighlighter.AddToken(Line, Col, LastFormat);
  PosHighlighter.AddToken(Line, Col + Length(Txt), Format);
  LastFormat := Format;
end;

procedure TMainForm.AddText(Txt: string);
var
  Line: integer;
  s:    string;
begin
  Line := Output.Lines.Count - 1;
  if Line < 0 then
  begin
    Output.Lines.Add('');
    Line := 0;
    PosHighlighter.ClearAllTokens;
  end;
  s := Output.Lines[Line] + Txt;
  Output.Lines[Line] := s;
end;

procedure TMainForm.DisplayLines;
var f,g:integer;
    Component:TComponent;
    CB:TCheckBox;
    Display:boolean;
    s:string;
begin
  for f:=Displayed+1 to High(Radky) do
  begin
    if not Radky[f].Completed then break;
    Displayed:=f;
    Display:=true;
    Component:=FindComponent('ShowCB'+IntToStr(Radky[f].Port+1));
    if Component<>nil then
    begin
      CB:=Component as TCheckBox;
      if not CB.Checked then Display:=false;
    end;
    if (Radky[f].Port=ChannelCount)and(not ShowAtOutputBtn.Down) then Display:=false;
    if Display then
    begin
      if f>0 then
      begin
        case DisplayTimeBtn.Tag of
          1:AddFormatedText('+'+IntToStr(MillisecondsBetween(Radky[f].Time,Radky[f-1].Time))+' ',InfoFormats[Radky[f].Port]);
          2:AddFormatedText(FormatDateTime('hh:nn:ss.zzz',Radky[f].Time)+' ',InfoFormats[Radky[f].Port]);
        end;
      end;
      if SendRG.ItemIndex=2 then
      begin
        s:='';
        for g:=1 to Length(Radky[f].Data) do s:=s+IntToHex(ord(Radky[f].Data[g]),2);
      end else begin
        s:='';
        for g:=1 to Length(Radky[f].Data) do
          if Radky[f].Data[g]>=' ' then s:=s+Radky[f].Data[g];
      end;
      AddFormatedText(s,TextFormats[Radky[f].Port]);
      if Radky[f].Timeout then AddFormatedText('<!>',InfoFormats[Radky[f].Port]);
      Output.Lines.Add('');
      Output.CaretY:=Output.Lines.Count+1;
    end;
  end;
end;

{ TReceiveThread }

procedure TReceiveThread.UpdateOutput;
begin
  if ActiveLine>High(MainForm.Radky) then exit;
  if ActiveLine=-1 then
  begin
    ActiveLine:=Length(MainForm.Radky);
    SetLength(MainForm.Radky,ActiveLine+1);
    if Length(MainForm.Radky)<2 then MainForm.Radky[ActiveLine].Time:=Now
                                else MainForm.Radky[ActiveLine].Time:=MainForm.Radky[ActiveLine-1].Time;
    MainForm.Radky[ActiveLine].Port:=Port;
  end;
  MainForm.Radky[ActiveLine].Data:=TextBuffer;
  MainForm.Radky[ActiveLine].Completed:=true;
  MainForm.Radky[ActiveLine].Timeout:=Timeout;
  MainForm.DisplayLines;
  ActiveLine:=-1;
end;

procedure TReceiveThread.PrepareOutput;
begin
  ActiveLine:=Length(MainForm.Radky);
  SetLength(MainForm.Radky,ActiveLine+1);
  MainForm.Radky[ActiveLine].Time:=Now;
  MainForm.Radky[ActiveLine].Completed:=false;
  MainForm.Radky[ActiveLine].Port:=Port;
end;

procedure TReceiveThread.AddLine;
begin
  if (ActiveLine>High(MainForm.Radky))or(ActiveLine<0) then exit;
  MainForm.Radky[ActiveLine].Data:=TextBuffer;
  MainForm.Radky[ActiveLine].Completed:=true;
  MainForm.Radky[ActiveLine].Timeout:=Timeout;
  ActiveLine:=-1;
  LinesAdded:=true;
end;

procedure TReceiveThread.Execute;
var f,g:integer;
    ReadTimeStart:TDateTime;
begin
  ReadPosition:=0;
  ActiveLine:=-1;
  LinesAdded:=false;
  while not Terminated do
  begin
    if not SerialAssigned(Port) then
    begin
      MainForm.CloseSerialPort(Port);
      exit;
    end;

    // CR, LF and CRLF waiting for its end
    if (MainForm.EOLRG.ItemIndex<3)and(ReadPosition>0) then
    begin
      Readed:=ReadSerialTimeout(Port,DataBuffer[ReadPosition],MaxDataLen-ReadPosition,0);
    end else begin
      Readed:=ReadSerialTimeout(Port,DataBuffer[ReadPosition],1,100);
    end;
    if not ProcessingEnabled then
    begin
      ReadPosition:=ReadPosition+Readed;
      Continue;
    end;
    if Readed>0 then
    begin
      ReadPosition:=ReadPosition+Readed;
      if ActiveLine=-1 then Synchronize(@PrepareOutput);
      ReadTimeStart:=Now;

      {Readed:=ReadSerialTimeout(Port,DataBuffer[ReadPosition],MaxDataLen-ReadPosition,1);
      if Readed>0 then ReadPosition:=ReadPosition+Readed;}

      // None
      f:=0;
      while f<ReadPosition do
      begin
        if ActiveLine=-1 then Synchronize(@PrepareOutput);
        case MainForm.EOLRG.ItemIndex of
          0: // LF
          begin
            if DataBuffer[f]=10 then
            begin
              TextBuffer:='';
              for g:=0 to f do TextBuffer:=TextBuffer+chr(DataBuffer[g]);
              if ReadPosition>f+1 then
              begin
                move(DataBuffer[f+1],DataBuffer[0],ReadPosition-f-1);
              end;
              ReadPosition:=ReadPosition-f-1;
              f:=0;
              Timeout:=false;
              AddLine;
              continue;
            end;
          end;
          1: // CR
          begin
            if DataBuffer[f]=13 then
            begin
              TextBuffer:='';
              for g:=0 to f do TextBuffer:=TextBuffer+chr(DataBuffer[g]);
              if ReadPosition>f+1 then
              begin
                move(DataBuffer[f+1],DataBuffer[0],ReadPosition-f-1);
              end;
              ReadPosition:=ReadPosition-f-1;
              f:=0;
              Timeout:=false;
              AddLine;
              continue;
            end;
          end;
          2: // CRLF
          begin
            if (f>0)and(DataBuffer[f-1]=13)and(DataBuffer[f]=10) then
            begin
              TextBuffer:='';
              for g:=0 to f do TextBuffer:=TextBuffer+chr(DataBuffer[g]);
              if ReadPosition>f+1 then
              begin
                move(DataBuffer[f+1],DataBuffer[0],ReadPosition-f-1);
              end;
              ReadPosition:=ReadPosition-f-1;
              f:=0;
              Timeout:=false;
              AddLine;
              continue;
            end;
          end;
        end;
        f:=f+1;
      end;
    end else if Readed=0 then
    begin
      if (ReadPosition>0)and((MainForm.EOLRG.ItemIndex=3)or(MilliSecondsBetween(ReadTimeStart,Now)>100)) then
      begin
        TextBuffer:='';
        for g:=0 to ReadPosition-1 do TextBuffer:=TextBuffer+chr(DataBuffer[g]);
        ReadPosition:=0;
        if MainForm.EOLRG.ItemIndex=3 then Timeout:=false
                                      else Timeout:=true;
        Synchronize(@UpdateOutput);
        LinesAdded:=false;
      end else if LinesAdded then
      begin
        Synchronize(@MainForm.DisplayLines);
        LinesAdded:=false;
      end;
    end;
  end;
end;

constructor TReceiveThread.Create(CreateSuspended: boolean);
begin
  FreeOnTerminate := True;
  inherited Create(CreateSuspended);
end;

end.

