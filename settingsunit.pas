unit SettingsUnit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  Buttons, Edits;

type

  { TSettingsForm }

  TSettingsForm = class(TForm)
    BitBtn1: TBitBtn;
    FontBtn: TBitBtn;
    ChannelCB: TComboBox;
    BitsEdit: TRangeInput;
    FontDialog1: TFontDialog;
    ParityCB: TComboBox;
    StopsCB: TComboBox;
    Label1: TLabel;
    Label2: TLabel;
    RychlostEdit: TRangeInput;
    Shape1: TShape;
    procedure BitsEditChange(Sender: TObject);
    procedure ChannelCBChange(Sender: TObject);
    procedure FontBtnClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ParityCBChange(Sender: TObject);
    procedure RychlostEditChange(Sender: TObject);
    procedure StopsCBChange(Sender: TObject);
  private

  public

  end;

var
  SettingsForm: TSettingsForm;

implementation

uses Hardware, MainUnit;

{$R *.lfm}

{ TSettingsForm }

procedure TSettingsForm.FormCreate(Sender: TObject);
var f:integer;
begin
  ChannelCB.Items.Clear;
  for f:=1 to ChannelCount do ChannelCB.Items.Add(IntToStr(f));
  ChannelCB.ItemIndex:=0;
end;

procedure TSettingsForm.ParityCBChange(Sender: TObject);
var Index:integer;
begin
  Index:=SettingsForm.ChannelCB.ItemIndex;
  MainForm.PortParams[Index].Parity:=ParityCB.ItemIndex;
end;

procedure TSettingsForm.RychlostEditChange(Sender: TObject);
var Index:integer;
begin
  Index:=SettingsForm.ChannelCB.ItemIndex;
  if RychlostEdit.IsOK then MainForm.PortParams[Index].BitRate:=RychlostEdit.Value;
end;

procedure TSettingsForm.StopsCBChange(Sender: TObject);
var Index:integer;
begin
  Index:=SettingsForm.ChannelCB.ItemIndex;
  MainForm.PortParams[Index].Stops:=StopsCB.ItemIndex+1;
end;

procedure TSettingsForm.ChannelCBChange(Sender: TObject);
var Component:TComponent;
    Index:integer;
begin
  Index:=SettingsForm.ChannelCB.ItemIndex;
  Component:=MainForm.FindComponent('Shape'+IntToStr(Index+1));
  if Component is TShape then Shape1.Brush.Color:=(Component as TShape).Brush.Color;
  RychlostEdit.Value:=MainForm.PortParams[Index].BitRate;
  BitsEdit.Value:=MainForm.PortParams[Index].Bits;
  StopsCB.ItemIndex:=MainForm.PortParams[Index].Stops-1;
  ParityCB.ItemIndex:=MainForm.PortParams[Index].Parity;
end;

procedure TSettingsForm.FontBtnClick(Sender: TObject);
begin
  FontDialog1.Font:=MainForm.Output.Font;
  if FontDialog1.Execute then MainForm.Output.Font:=FontDialog1.Font;
end;

procedure TSettingsForm.BitsEditChange(Sender: TObject);
var Index:integer;
begin
  Index:=SettingsForm.ChannelCB.ItemIndex;
  if BitsEdit.IsOK then MainForm.PortParams[Index].Bits:=BitsEdit.Value;
end;

end.

