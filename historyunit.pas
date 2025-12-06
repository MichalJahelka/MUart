unit HistoryUnit;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls;

type

  { THistoryForm }

  THistoryForm = class(TForm)
    ListBox1: TListBox;
    procedure ListBox1Click(Sender: TObject);
    procedure ListBox1DblClick(Sender: TObject);
  private

  public

  end;

var
  HistoryForm: THistoryForm;

implementation

uses MainUnit,LCLType;

{$R *.lfm}

{ THistoryForm }

procedure THistoryForm.ListBox1Click(Sender: TObject);
begin
  MainForm.Input.Text:=ListBox1.GetSelectedText;
end;

procedure THistoryForm.ListBox1DblClick(Sender: TObject);
var UTF8Key: TUTF8Char;
begin
  MainForm.Input.Text:=ListBox1.GetSelectedText;
  UTF8Key:=#13;
  MainForm.InputUTF8KeyPress(Sender,UTF8Key);
end;

end.

