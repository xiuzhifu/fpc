{
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2009 by the Free Pascal development team

    TFCgiApplication class.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{ $define CGIDEBUG}
{$mode objfpc}
{$H+}

unit custfcgi;

Interface

uses
  Classes,SysUtils, httpdefs, Sockets, custweb, custcgi, fastcgi;

Type
  { TFCGIRequest }
  TCustomFCgiApplication = Class;
  TFCGIRequest = Class;
  TFCGIResponse = Class;

  TProtocolOption = (poNoPadding,poStripContentLength, poFailonUnknownRecord );
  TProtocolOptions = Set of TProtocolOption;

  TUnknownRecordEvent = Procedure (ARequest : TFCGIRequest; AFCGIRecord: PFCGI_Header) Of Object;

  TFCGIRequest = Class(TCGIRequest)
  Private
    FHandle: THandle;
    FKeepConnectionAfterRequest: boolean;
    FPO: TProtoColOptions;
    FRequestID : Word;
    FCGIParams : TSTrings;
    FUR: TUnknownRecordEvent;
    procedure GetNameValuePairsFromContentRecord(const ARecord : PFCGI_ContentRecord; NameValueList : TStrings);
  Protected
    Function GetFieldValue(Index : Integer) : String; override;
    procedure ReadContent; override;
  Public
    destructor Destroy; override;
    function ProcessFCGIRecord(AFCGIRecord : PFCGI_Header) : boolean; virtual;
    property RequestID : word read FRequestID write FRequestID;
    property Handle : THandle read FHandle write FHandle;
    property KeepConnectionAfterRequest : boolean read FKeepConnectionAfterRequest;
    Property ProtocolOptions : TProtoColOptions read FPO Write FPO;
    Property OnUnknownRecord : TUnknownRecordEvent Read FUR Write FUR;
  end;

  { TFCGIResponse }

  TFCGIResponse = Class(TCGIResponse)
  private
    FPO: TProtoColOptions;
    procedure Write_FCGIRecord(ARecord : PFCGI_Header);
  Protected
    Procedure DoSendHeaders(Headers : TStrings); override;
    Procedure DoSendContent; override;
    Property ProtocolOptions : TProtoColOptions Read FPO Write FPO;
  end;

  TReqResp = record
             Request : TFCgiRequest;
             Response : TFCgiResponse;
             end;

  { TFCgiHandler }

  TFCgiHandler = class(TWebHandler)
  Private
    FOnUnknownRecord: TUnknownRecordEvent;
    FPO: TProtoColOptions;
    FRequestsArray : Array of TReqResp;
    FRequestsAvail : integer;
    FHandle : THandle;
    Socket: longint;
    FAddress: string;
    FPort: integer;
    function Read_FCGIRecord : PFCGI_Header;
  protected
    function  ProcessRecord(AFCGI_Record: PFCGI_Header; out ARequest: TRequest;  out AResponse: TResponse): boolean; virtual;
    procedure SetupSocket(var IAddress: TInetSockAddr;  var AddressLength: tsocklen); virtual;
    function  WaitForRequest(out ARequest : TRequest; out AResponse : TResponse) : boolean; override;
    procedure EndRequest(ARequest : TRequest;AResponse : TResponse); override;
  Public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Port: integer read FPort write FPort;
    property Address: string read FAddress write FAddress;
    Property ProtocolOptions : TProtoColOptions Read FPO Write FPO;
    Property OnUnknownRecord : TUnknownRecordEvent Read FOnUnknownRecord Write FOnUnknownRecord;
  end;

  { TCustomFCgiApplication }

  TCustomFCgiApplication = Class(TCustomWebApplication)
  private
    function GetAddress: string;
    function GetFPO: TProtoColOptions;
    function GetOnUnknownRecord: TUnknownRecordEvent;
    function GetPort: integer;
    procedure SetAddress(const AValue: string);
    procedure SetOnUnknownRecord(const AValue: TUnknownRecordEvent);
    procedure SetPort(const AValue: integer);
    procedure SetPO(const AValue: TProtoColOptions);
  protected
    function InitializeWebHandler: TWebHandler; override;
  Public
    property Port: integer read GetPort write SetPort;
    property Address: string read GetAddress write SetAddress;
    Property ProtocolOptions : TProtoColOptions Read GetFPO Write SetPO;
    Property OnUnknownRecord : TUnknownRecordEvent Read GetOnUnknownRecord Write SetOnUnknownRecord;
  end;

ResourceString
  SNoInputHandle    = 'Failed to open input-handle passed from server. Socket Error: %d';
  SNoSocket         = 'Failed to open socket. Socket Error: %d';
  SBindFailed       = 'Failed to bind to port %d. Socket Error: %d';
  SListenFailed     = 'Failed to listen to port %d. Socket Error: %d';
  SErrReadingSocket = 'Failed to read data from socket. Error: %d';
  SErrReadingHeader = 'Failed to read FastCGI header. Read only %d bytes';

Implementation

{$ifdef CGIDEBUG}
uses
  dbugintf;
{$endif}


{$undef nosignal}

{$if defined(FreeBSD) or defined(Linux)}
  {$define nosignal}
{$ifend}

Const 
   NoSignalAttr =  {$ifdef nosignal} MSG_NOSIGNAL{$else}0{$endif};

{ TFCGIHTTPRequest }

procedure TFCGIRequest.ReadContent;
begin
  // Nothing has to be done. This should never be called
end;

destructor TFCGIRequest.Destroy;
begin
  FCGIParams.Free;
  inherited Destroy;
end;

function TFCGIRequest.ProcessFCGIRecord(AFCGIRecord: PFCGI_Header): boolean;
var cl,rcl : Integer;
begin
  Result := False;
  case AFCGIRecord^.reqtype of
    FCGI_BEGIN_REQUEST : FKeepConnectionAfterRequest := (PFCGI_BeginRequestRecord(AFCGIRecord)^.body.flags and FCGI_KEEP_CONN) = FCGI_KEEP_CONN;
    FCGI_PARAMS :       begin
                        if AFCGIRecord^.contentLength=0 then
                          Result := False
                        else
                          begin
                          if not assigned(FCGIParams) then
                            FCGIParams := TStringList.Create;
                          GetNameValuePairsFromContentRecord(PFCGI_ContentRecord(AFCGIRecord),FCGIParams);
                          end;
                        end;
    FCGI_STDIN :        begin
                        if AFCGIRecord^.contentLength=0 then
                          begin
                          Result := True;
                          InitRequestVars;
                          ParseCookies;
                          end
                        else
                          begin
                          cl := length(FContent);
                          rcl := BetoN(PFCGI_ContentRecord(AFCGIRecord)^.header.contentLength);
                          SetLength(FContent, rcl+cl);
                          move(PFCGI_ContentRecord(AFCGIRecord)^.ContentData[0],FContent[cl+1],rcl);
                          FContentRead:=True;
                          end;
                        end;
  else
    if Assigned(FUR) then
      FUR(Self,AFCGIRecord)
    else
      if poFailonUnknownRecord in FPO then
        Raise EFPWebError.CreateFmt('Unknown FASTCGI record type: %s',[AFCGIRecord^.reqtype]);
  end;
end;

procedure TFCGIRequest.GetNameValuePairsFromContentRecord(const ARecord: PFCGI_ContentRecord; NameValueList: TStrings);

var
  i : integer;

  function GetVarLength : Integer;
  begin
    if (ARecord^.ContentData[i] and 128) = 0 then
      Result:=ARecord^.ContentData[i]
    else
      begin
//      Result:=BEtoN(PLongint(@(ARecord^.ContentData[i]))^);
      Result:=((ARecord^.ContentData[i] and $7f) shl 24) + (ARecord^.ContentData[i+1] shl 16)
                   + (ARecord^.ContentData[i+2] shl 8) + (ARecord^.ContentData[i+3]);
      inc(i,3);
      end;
    inc(i);
  end;

  function GetString(ALength : integer) : string;
  begin
    SetLength(Result,ALength);
    move(ARecord^.ContentData[i],Result[1],ALength);
    inc(i,ALength);
  end;

var
  NameLength, ValueLength : Integer;
  RecordLength : Integer;
  Name,Value : String;

begin
  i := 0;
  RecordLength:=BetoN(ARecord^.Header.contentLength);
  while i < RecordLength do
    begin
    NameLength:=GetVarLength;
    ValueLength:=GetVarLength;

    Name:=GetString(NameLength);
    Value:=GetString(ValueLength);
    NameValueList.Add(Name+'='+Value);
    end;
end;


Function TFCGIRequest.GetFieldValue(Index : Integer) : String;

Type THttpToCGI = array[1..CGIVarCount] of byte;

const HttpToCGI : THttpToCGI =
   (
     18,  //  1 'HTTP_ACCEPT'           - fieldAccept
     19,  //  2 'HTTP_ACCEPT_CHARSET'   - fieldAcceptCharset
     20,  //  3 'HTTP_ACCEPT_ENCODING'  - fieldAcceptEncoding
      0,  //  4
      0,  //  5
      0,  //  6
      0,  //  7
      0,  //  8
      2,  //  9 'CONTENT_LENGTH'
      3,  // 10 'CONTENT_TYPE'          - fieldAcceptEncoding
     24,  // 11 'HTTP_COOKIE'           - fieldCookie
      0,  // 12
      0,  // 13
      0,  // 14
     21,  // 15 'HTTP_IF_MODIFIED_SINCE'- fieldIfModifiedSince
      0,  // 16
      0,  // 17
      0,  // 18
     22,  // 19 'HTTP_REFERER'          - fieldReferer
      0,  // 20
      0,  // 21
      0,  // 22
     23,  // 23 'HTTP_USER_AGENT'       - fieldUserAgent
      1,  // 24 'AUTH_TYPE'             - fieldWWWAuthenticate
      5,  // 25 'PATH_INFO'
      6,  // 26 'PATH_TRANSLATED'
      8,  // 27 'REMOTE_ADDR'
      9,  // 28 'REMOTE_HOST'
     13,  // 29 'SCRIPT_NAME'
     15,  // 30 'SERVER_PORT'
     12,  // 31 'REQUEST_METHOD'
      0,  // 32
      7,  // 33 'QUERY_STRING'
     27,  // 34 'HTTP_HOST'
      0,  // 35 'CONTENT'
     36   // 36 'XHTTPREQUESTEDWITH'
    );

var ACgiVarNr : Integer;

begin
  Result := '';
  if assigned(FCGIParams) and (index < high(HttpToCGI)) and (index > 0) and (index<>35) then
    begin
    ACgiVarNr:=HttpToCGI[Index];
    if ACgiVarNr>0 then
      Result:=FCGIParams.Values[CgiVarNames[ACgiVarNr]]
    else
      Result := '';
    end
  else
    Result:=inherited GetFieldValue(Index);
end;

{ TCGIResponse }
procedure TFCGIResponse.Write_FCGIRecord(ARecord : PFCGI_Header);

var BytesToWrite : Integer;
    BytesWritten  : Integer;
    P : PByte;
begin
  BytesToWrite := BEtoN(ARecord^.contentLength) + ARecord^.paddingLength+sizeof(FCGI_Header);
  P:=PByte(Arecord);
  Repeat
    BytesWritten := sockets.fpsend(TFCGIRequest(Request).Handle, P, BytesToWrite, NoSignalAttr);
    Inc(P,BytesWritten);
    Dec(BytesToWrite,BytesWritten);
//    Assert(BytesWritten=BytesToWrite);
  until (BytesToWrite=0) or (BytesWritten=0);
end;

procedure TFCGIResponse.DoSendHeaders(Headers : TStrings);
var
  cl : word;
  pl : byte;
  str : String;
  ARespRecord : PFCGI_ContentRecord;
  I : Integer;

begin
  For I:=Headers.Count-1 downto 0 do
    If (Headers[i]='') then
      Headers.Delete(I);
  // IndexOfName Does not work ?
  If (poStripContentLength in ProtocolOptions) then
    For I:=Headers.Count-1 downto 0 do
      If (Pos('Content-Length',Headers[i])<>0)  then
        Headers.Delete(i);
  str := Headers.Text+sLineBreak;
  cl := length(str);
  if ((cl mod 8)=0) or (poNoPadding in ProtocolOptions) then
    pl:=0
  else
    pl := 8-(cl mod 8);
  ARespRecord:=nil;
  Getmem(ARespRecord,8+cl+pl);
  try
    FillChar(ARespRecord^,8+cl+pl,0);
    ARespRecord^.header.version:=FCGI_VERSION_1;
    ARespRecord^.header.reqtype:=FCGI_STDOUT;
    ARespRecord^.header.paddingLength:=pl;
    ARespRecord^.header.contentLength:=NtoBE(cl);
    ARespRecord^.header.requestId:=NToBE(TFCGIRequest(Request).RequestID);
    move(str[1],ARespRecord^.ContentData,cl);
    Write_FCGIRecord(PFCGI_Header(ARespRecord));
  finally
    Freemem(ARespRecord);
  end;
end;

procedure TFCGIResponse.DoSendContent;

Const
  MaxBuf = $EFFF;

var
  bs,l : Integer;
  cl : word;
  pl : byte;
  str : String;
  ARespRecord : PFCGI_ContentRecord;
  EndRequest : FCGI_EndRequestRecord;

begin
  If Assigned(ContentStream) then
    begin
    setlength(str,ContentStream.Size);
    ContentStream.Position:=0;
    ContentStream.Read(str[1],ContentStream.Size);
    end
  else
    str := Contents.Text;
  L:=Length(Str);
  BS:=0;
  Repeat
    If (L-BS)>MaxBuf then
      cl := MaxBuf
    else
      cl:=L-BS ;
    if ((cl mod 8)=0) or (poNoPadding in ProtocolOptions) then
      pl:=0
    else
      pl := 8-(cl mod 8);
    ARespRecord:=Nil;
    Getmem(ARespRecord,8+cl+pl);
    try
      ARespRecord^.header.version:=FCGI_VERSION_1;
      ARespRecord^.header.reqtype:=FCGI_STDOUT;
      ARespRecord^.header.paddingLength:=pl;
      ARespRecord^.header.contentLength:=NtoBE(cl);
      ARespRecord^.header.requestId:=NToBE(TFCGIRequest(Request).RequestID);
      move(Str[BS+1],ARespRecord^.ContentData,cl);
      Write_FCGIRecord(PFCGI_Header(ARespRecord));
    finally
      Freemem(ARespRecord);
    end;
    Inc(BS,cl);
  Until (BS=L);
  FillChar(EndRequest,SizeOf(FCGI_EndRequestRecord),0);
  EndRequest.header.version:=FCGI_VERSION_1;
  EndRequest.header.reqtype:=FCGI_END_REQUEST;
  EndRequest.header.contentLength:=NtoBE(8);
  EndRequest.header.paddingLength:=0;
  EndRequest.header.requestId:=NToBE(TFCGIRequest(Request).RequestID);
  EndRequest.body.protocolStatus:=FCGI_REQUEST_COMPLETE;
  Write_FCGIRecord(PFCGI_Header(@EndRequest));
end;

{ TFCgiHandler }

constructor TFCgiHandler.Create(AOwner: TComponent);
begin
  Inherited Create(AOwner);
  FRequestsAvail:=5;
  SetLength(FRequestsArray,FRequestsAvail);
  FHandle := THandle(-1);
end;

destructor TFCgiHandler.Destroy;
begin
  SetLength(FRequestsArray,0);
  if (Socket<>0) then
    begin
    CloseSocket(Socket);
    Socket:=0;
    end;
  inherited Destroy;
end;

procedure TFCgiHandler.EndRequest(ARequest: TRequest; AResponse: TResponse);
begin
  with FRequestsArray[TFCGIRequest(ARequest).RequestID] do
    begin
    Assert(ARequest=Request);
    Assert(AResponse=Response);
    if (not TFCGIRequest(ARequest).KeepConnectionAfterRequest) then
      begin
      fpshutdown(FHandle,SHUT_RDWR);
      CloseSocket(FHandle);
      FHandle := THandle(-1);
      end;
    Request := Nil;
    Response := Nil;
    end;
  Inherited;
end;

function TFCgiHandler.Read_FCGIRecord : PFCGI_Header;
{ $DEFINE DUMPRECORD}
{$IFDEF DUMPRECORD}
  Procedure DumpFCGIRecord (Var Header :FCGI_Header; ContentLength : word; PaddingLength : byte; ResRecord : Pointer);

  Var
    s : string;
    I : Integer;

  begin
      Writeln('Dumping record ', Sizeof(Header),',',Contentlength,',',PaddingLength);
      For I:=0 to Sizeof(Header)+ContentLength+PaddingLength-1 do
        begin
        Write(Format('%:3d ',[PByte(ResRecord)[i]]));
        If PByte(ResRecord)[i]>30 then
          S:=S+char(PByte(ResRecord)[i]);
        if (I mod 16) = 0 then
           begin
           writeln('  ',S);
           S:='';
           end;
        end;
      Writeln('  ',S)
  end;
{$ENDIF DUMPRECORD}

  function ReadBytes(ReadBuf: Pointer; ByteAmount : Word) : Integer;

  Var
    P : PByte;
    Count : Integer;

  begin
    Result := 0;
    P:=ReadBuf;
    if (ByteAmount=0) then exit;
    Repeat
      Count:=sockets.fpRecv(FHandle, P, ByteAmount, NoSignalAttr);
      If (Count>0) then
        begin
        Dec(ByteAmount,Count);
        P:=P+Count;
        Inc(Result,Count);
        end
      else if (Count<0) then
        Raise HTTPError.CreateFmt(SErrReadingSocket,[Count]);
    until (ByteAmount=0) or (Count=0);
  end;

var Header : FCGI_Header;
    BytesRead : integer;
    ContentLength : word;
    PaddingLength : byte;
    ResRecord : pointer;
    ReadBuf : pointer;


begin
  Result := Nil;
  ResRecord:=Nil;
  ReadBuf:=@Header;
  BytesRead:=ReadBytes(ReadBuf,Sizeof(Header));
  If (BytesRead=0) then
    Exit // Connection closed gracefully.
  else If (BytesRead<>Sizeof(Header)) then
    Raise HTTPError.CreateFmt(SErrReadingHeader,[BytesRead]);
  ContentLength:=BetoN(Header.contentLength);
  PaddingLength:=Header.paddingLength;
  Getmem(ResRecord,BytesRead+ContentLength+PaddingLength);
  try
    PFCGI_Header(ResRecord)^:=Header;
    ReadBuf:=ResRecord+BytesRead;
    BytesRead:=ReadBytes(ReadBuf,ContentLength);
    ReadBuf:=ReadBuf+BytesRead;
    BytesRead:=ReadBytes(ReadBuf,PaddingLength);
    Result := ResRecord;
  except
    FreeMem(resRecord);
    Raise;
  end;
end;

procedure TFCgiHandler.SetupSocket(var IAddress : TInetSockAddr; Var AddressLength : tsocklen);

begin
  AddressLength:=Sizeof(IAddress);
  Socket := fpsocket(AF_INET,SOCK_STREAM,0);
  if Socket=-1 then
    raise EFPWebError.CreateFmt(SNoSocket,[socketerror]);
  IAddress.sin_family:=AF_INET;
  IAddress.sin_port:=htons(Port);
  if FAddress<>'' then
    Iaddress.sin_addr := StrToHostAddr(FAddress)
  else
    IAddress.sin_addr.s_addr:=0;
  if fpbind(Socket,@IAddress,AddressLength)=-1 then
    begin
    CloseSocket(socket);
    Socket:=0;
    Terminate;
    raise Exception.CreateFmt(SBindFailed,[port,socketerror]);
    end;
  if fplisten(Socket,1)=-1 then
    begin
    CloseSocket(socket);
    Socket:=0;
    Terminate;
    raise Exception.CreateFmt(SListenFailed,[port,socketerror]);
    end;
end;

function TFCgiHandler.ProcessRecord(AFCGI_Record  : PFCGI_Header; out ARequest: TRequest; out AResponse: TResponse): boolean;

var
  ARequestID    : word;
  ATempRequest  : TFCGIRequest;
begin
  Result:=False;
  ARequestID:=BEtoN(AFCGI_Record^.requestID);
  if AFCGI_Record^.reqtype = FCGI_BEGIN_REQUEST then
    begin
    if ARequestID>FRequestsAvail then
      begin
      inc(FRequestsAvail,10);
      SetLength(FRequestsArray,FRequestsAvail);
      end;
    assert(not assigned(FRequestsArray[ARequestID].Request));
    assert(not assigned(FRequestsArray[ARequestID].Response));
    ATempRequest:=TFCGIRequest.Create;
    ATempRequest.RequestID:=ARequestID;
    ATempRequest.Handle:=FHandle;
    ATempRequest.ProtocolOptions:=Self.Protocoloptions;
    ATempRequest.OnUnknownRecord:=Self.OnUnknownRecord;
    FRequestsArray[ARequestID].Request := ATempRequest;
    end;
  if FRequestsArray[ARequestID].Request.ProcessFCGIRecord(AFCGI_Record) then
    begin
    ARequest:=FRequestsArray[ARequestID].Request;
    FRequestsArray[ARequestID].Response := TFCGIResponse.Create(ARequest);
    FRequestsArray[ARequestID].Response.ProtocolOptions:=Self.ProtocolOptions;
    AResponse:=FRequestsArray[ARequestID].Response;
    Result := True;
    end;
end;

function TFCgiHandler.WaitForRequest(out ARequest: TRequest; out AResponse: TResponse): boolean;

var
  IAddress      : TInetSockAddr;
  AddressLength : tsocklen;
  AFCGI_Record  : PFCGI_Header;

begin
  Result := False;
  if Socket=0 then
    if Port<>0 then
      SetupSocket(IAddress,AddressLength)
    else
      Socket:=StdInputHandle;
  if FHandle=THandle(-1) then
    begin
    FHandle:=fpaccept(Socket,psockaddr(@IAddress),@AddressLength);
    if FHandle=THandle(-1) then
      begin
      Terminate;
      raise Exception.CreateFmt(SNoInputHandle,[socketerror]);
      end;
    end;
  repeat
    AFCGI_Record:=Read_FCGIRecord;
    if assigned(AFCGI_Record) then
    try
      Result:=ProcessRecord(AFCGI_Record,ARequest,AResponse);
    Finally
      FreeMem(AFCGI_Record);
      AFCGI_Record:=Nil;
    end;
  until Result;
end;

{ TCustomFCgiApplication }

function TCustomFCgiApplication.GetAddress: string;
begin
  result := TFCgiHandler(WebHandler).Address;
end;

function TCustomFCgiApplication.GetFPO: TProtoColOptions;
begin
  result := TFCgiHandler(WebHandler).ProtocolOptions;
end;

function TCustomFCgiApplication.GetOnUnknownRecord: TUnknownRecordEvent;
begin
  result := TFCgiHandler(WebHandler).OnUnknownRecord;
end;

function TCustomFCgiApplication.GetPort: integer;
begin
  result := TFCgiHandler(WebHandler).Port;
end;

procedure TCustomFCgiApplication.SetAddress(const AValue: string);
begin
  TFCgiHandler(WebHandler).Address := AValue;
end;

procedure TCustomFCgiApplication.SetOnUnknownRecord(const AValue: TUnknownRecordEvent);
begin
  TFCgiHandler(WebHandler).OnUnknownRecord := AValue;
end;

procedure TCustomFCgiApplication.SetPort(const AValue: integer);
begin
  TFCgiHandler(WebHandler).Port := AValue;
end;

procedure TCustomFCgiApplication.SetPO(const AValue: TProtoColOptions);
begin
  TFCgiHandler(WebHandler).ProtocolOptions := AValue;
end;

function TCustomFCgiApplication.InitializeWebHandler: TWebHandler;
begin
  Result:=TFCgiHandler.Create(self);
end;

end.
