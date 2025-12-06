unit Hardware;

{$mode ObjFPC}{$H+}

interface

{$IFDEF Windows}
  uses Serial;
{$ENDIF}

const
  ChannelCount=4;

const
  MaxZprava=1023;

type TPole=array[0..MaxZprava] of byte;
     PPole=^TPole;

var
{$IFDEF linux}
  SerialPorts:array[0..ChannelCount-1] of integer;
{$ENDIF}
{$IFDEF Windows}
  SerialPorts:array[0..ChannelCount-1] of THandle;
  IntFreq:int64;
{$ENDIF}
LastSerialError:array[0..ChannelCount-1] of string;

procedure ClearBuffers(Port:integer);
function WriteSerial(Port:integer;Pole:PPole;Delka:integer):integer;
function ReadSerial(Port:integer;out Pole;Delka:integer):integer;
procedure CloseSerial(Port:integer);
procedure ClearSerialError(Port:integer);
function SerialOk(Port:integer):boolean;
function SerialAssigned(Port:integer):boolean;
function ReadSerialTimeout(Port:integer;out Zprava;Delka:integer;Cas:integer):integer;

implementation

uses SysUtils,DateUtils,
{$IFDEF Windows}
  Windows;
{$ENDIF}

{$IFDEF linux}
  BaseUnix,Termio,errors,Linux;
{$ENDIF}

procedure ClearBuffers(Port: integer);
begin
  if(Port<0)or(Port>High(SerialPorts)) then exit;
  {$IFDEF Windows}
    SerFlushInput(SerialPorts[Port]);
    SerFlushOutput(SerialPorts[Port]);
  {$ENDIF}
  {$IFDEF linux}
    tcflush(SerialPorts[Port],TCIOFLUSH);
  {$ENDIF}
end;

function WriteSerial(Port: integer; Pole: PPole; Delka: integer): integer;
begin
  Result:=0;
  if(Port<0)or(Port>High(SerialPorts)) then exit;
  {$IFDEF Windows}
    SerWrite(SerialPorts[Port],Pole^,Delka);
    SerDrain(SerialPorts[Port]);
  {$ENDIF}
  {$IFDEF linux}
    Result:=fpWrite(SerialPorts[Port],Pole^,Delka);
    if Result<>Delka then
    begin
      LastSerialError[Port]:=StrError(errno);
    end;
  {$ENDIF}
end;

function ReadSerial(Port: integer; out Pole; Delka: integer): integer;
begin
  Result:=0;
  if(Port<0)or(Port>High(SerialPorts)) then exit;
  {$IFDEF Windows}
    Result:=SerRead(SerialPorts[Port],Pole,Delka);
  {$ENDIF}
  {$IFDEF linux}
    Result:=fpRead(SerialPorts[Port],@Pole,Delka);
  {$ENDIF}
end;

procedure CloseSerial(Port: integer);
begin
  if(Port<0)or(Port>High(SerialPorts)) then exit;
  {$IFDEF Windows}
     SerClose(SerialPorts[Port]);
     SerialPorts[Port]:=0;
  {$ENDIF}
  {$IFDEF linux}
     if SerialPorts[Port]<>-1 then
     begin
       fpClose(SerialPorts[Port]);
       SerialPorts[Port]:=-1;
     end;
  {$ENDIF}
end;

procedure ClearSerialError(Port: integer);
begin
  if(Port<0)or(Port>High(SerialPorts)) then exit;
  LastSerialError[Port]:='';
end;

function SerialOk(Port: integer): boolean;
begin
  if(Port<0)or(Port>High(SerialPorts)) then
  begin
    Result:=false;
    exit;
  end;
  Result:=true;
  {$IFDEF Windows}
    if SerialPorts[Port]=0 then Result:=false;
  {$ENDIF}
  {$IFDEF linux}
    if SerialPorts[Port]<0 then Result:=false;
    if LastSerialError[Port]<>'' then Result:=false;
  {$ENDIF}
end;

function SerialAssigned(Port: integer): boolean;
begin
  if(Port<0)or(Port>High(SerialPorts)) then
  begin
    Result:=false;
    exit;
  end;
  Result:=true;
  {$IFDEF Windows}
  if SerialPorts[Port]=0 then Result:=false;
  {$ENDIF}
  {$IFDEF linux}
  if SerialPorts[Port]<0 then Result:=false;
  {$ENDIF}
end;

{$IFDEF linux}
function LinuxReadSerial(SerialPort:integer;Buffer:PPole;Delka,WaitingTime:integer):integer;
var fasttime:Ttimespec;
    Cas1,Cas2:QWORD;
    readed,retval:integer;
    rfds:TFDSet;
    timeout:cint;
    i:integer;
begin
  Cas1:=0;
  if WaitingTime>0 then
  begin
    // Určíme pomocí přesného časovače Cas1 v ms, přičteme dobu čekání
    clock_gettime(CLOCK_MONOTONIC,@fasttime);
    Cas1:=fasttime.tv_sec;
    Cas1:=Cas1*1000;
    Cas1:=Cas1+fasttime.tv_nsec div 1000000;
    Cas1:=Cas1+WaitingTime;
  end;
  readed:=0;

  repeat
    if WaitingTime>0 then
    begin
      clock_gettime(CLOCK_MONOTONIC,@fasttime);
      Cas2:=fasttime.tv_sec;
      Cas2:=Cas2*1000;
      Cas2:=Cas2+fasttime.tv_nsec div 1000000;
      if Cas2>=Cas1 then
      begin
        // Překročen čas
        fpFD_ZERO(rfds);
        Result:=readed;
        Exit;
      end;
      timeout:=Cas1-Cas2;
      // Vynulujeme rfds
      fpFD_ZERO(rfds);
      // Přidáme do rfds sériový port (čekání na událost)
      fpFD_SET(SerialPort,rfds);
      errno:=0;
      retval:=fpSelect(SerialPort+1,@rfds,nil,nil,timeout);
    end else begin
      // Vynulujeme rfds
      fpFD_ZERO(rfds);
      // Přidáme do rfds sériový port (čekání na událost)
      fpFD_SET(SerialPort,rfds);
      errno:=0;
      retval:=fpSelect(SerialPort+1,@rfds,nil,nil,nil);
    end;
    // Pokud je splněna událost (čas nevypršel)
    if retval<>0 then
    begin
      // Pokud došlo k události od sériového portu
      if fpFD_ISSET(SerialPort,rfds)<>0 then
      begin
        // Přečteme příkaz (nebo alespoň část příkazu)
        Sleep(1);   // Bez sleep to vykazuje chyby!
        i:=fpRead(SerialPort,Buffer^[readed],Delka-readed);
        if i>0 then readed:=readed+i;
      end;
    end;
  until readed>=Delka;
  Result:=readed;
end;
{$ENDIF}

function ReadSerialTimeout(Port: integer; out Zprava; Delka: integer;
  Cas: integer): integer;
{$IFDEF Windows}
var a:array of byte;
    Readed:integer;
{$ENDIF}
begin
  Result:=0;
  if(Port<0)or(Port>High(SerialPorts)) then exit;
  {$IFDEF Windows}
    if Cas<0 then Cas:=0;
    SetLength(a,Delka);
    if Cas>0 then Readed:=SerReadTimeout(SerialPorts[Port],a,Delka,Cas)
             else Readed:=SerRead(SerialPorts[Port],a,Delka);
    if Readed>0 then move(a[0],Zprava,length(a));
    SetLength(a,0);
    Result:=Readed;
  {$ENDIF}
  {$IFDEF linux}
    if Cas<0 then Cas:=0;
    if Cas>0 then Result:=LinuxReadSerial(SerialPorts[Port],@Zprava,Delka,Cas)
             else Result:=fpRead(SerialPorts[Port],Zprava,Delka);
  {$ENDIF}
end;

begin
  {$IFDEF Windows}
    QueryPerformanceFrequency(IntFreq);
  {$ENDIF}
end.

