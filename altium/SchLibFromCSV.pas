{*****************************************************************************
  SchLibFromCSV.pas + SchLibFromCSV.dfm  -  Chila board (@chilaboard)
  Altium Designer (DelphiScript): window for building schematic symbols.

  Run:  File > Run Script...  >  CreateFromCSV
  In the window: paste a part table (or Load CSV / Demo), set pin spacing / lengths /
  placement, check the preview, choose "New library" or "Open library", press Generate.

  Accepted text (comma- or Tab-separated, so a copy from Excel works):
    1) merged format:   Part Number,VALUE,Description,...   (part row)
                        Pin No.,Pin Name,Type,Side          (pin table)   [blank line, next part]
    2) pins only:       Pin No.,Pin Name,Type,Side   or just rows "1,VDD,Power,Top"
       -> the part name / description / package come from the fields in the window.
  Type: Input IO Output OpenCollector Passive HiZ OpenEmitter Power (default Passive)
  Side: Left Right Top Bottom (empty = Left)

  NOTE: written without access to Altium. If a line fails, send the error text.
*****************************************************************************}

var
  PIN_SPACING        : Integer;   // mil
  LEN_LR             : Integer;   // mil, left/right pin length
  LEN_TB             : Integer;   // mil, top/bottom pin length
  CHAR_W             : Integer;   // mil per character of a pin name (body width estimate)
  ACTIVE_LOW_OVERBAR : Boolean;   // True: RESET# -> R\E\S\E\T\
  RIGHT_TOP_CCW      : Boolean;   // True: right/top pins listed bottom->top / right->left
  PLACE_MODE         : Integer;   // 0 = Side column, 1 = auto left/right split, 2 = all left

  GMode       : Integer;          // 0 scan only, 1 draw preview, 2 generate in Altium
  GPartSeq    : Integer;          // index of the part being processed
  GPreviewIdx : Integer;          // part to draw
  GNames      : String;           // part names separated by '|'
  GNameCount  : Integer;
  GWarn       : String;
  GPinTotal   : Integer;
  GCanvas     : TCanvas;
  GSc         : Double;
  GOx         : Integer;
  GOy         : Integer;

{ ---------- small helpers ---------- }
function Up100(V : Integer) : Integer;
begin
  Result := ((V + 99) div 100) * 100;
end;

function MaxI(A, B : Integer) : Integer;
begin
  if A > B then Result := A else Result := B;
end;

procedure Warn(Msg : String);
begin
  if GMode = 2 then ShowMessage(Msg)
  else GWarn := GWarn + Msg + '  ';
end;

{ split one line (RFC4180 quotes; Tab used as delimiter when the line contains a Tab) }
procedure ParseLine(Line : String; Fields : TStringList);
var
  i    : Integer;
  c    : String;
  Cell : String;
  InQ  : Boolean;
  Delim : String;
begin
  Fields.Clear;
  Delim := ',';
  if Pos(Chr(9), Line) > 0 then Delim := Chr(9);
  Cell := '';
  InQ  := False;
  i := 1;
  while i <= Length(Line) do
  begin
    c := Line[i];
    if InQ then
    begin
      if c = '"' then
      begin
        if (i < Length(Line)) and (Line[i + 1] = '"') then
        begin
          Cell := Cell + '"';
          Inc(i);
        end
        else InQ := False;
      end
      else Cell := Cell + c;
    end
    else
    begin
      if c = '"' then InQ := True
      else if c = Delim then
      begin
        Fields.Add(Trim(Cell));
        Cell := '';
      end
      else Cell := Cell + c;
    end;
    Inc(i);
  end;
  Fields.Add(Trim(Cell));
end;

function FieldAt(F : TStringList; Idx : Integer) : String;
begin
  if (Idx >= 0) and (Idx < F.Count) then Result := F.Strings[Idx] else Result := '';
end;

function IsBlankRow(F : TStringList) : Boolean;
var k : Integer;
begin
  Result := True;
  for k := 0 to F.Count - 1 do
    if Trim(F.Strings[k]) <> '' then Result := False;
end;

function Quote(S : String) : String;
begin
  Result := '"' + StringReplace(S, '"', '""', rfReplaceAll) + '"';
end;

{ 'RST#/INT#' -> 'R\S\T\/I\N\T\' when ACTIVE_LOW_OVERBAR }
function DisplayName(N : String) : String;
var
  k, Start, j : Integer;
  Seg, Res : String;
begin
  if not ACTIVE_LOW_OVERBAR then
  begin
    Result := N;
    exit;
  end;
  Res := '';
  Start := 1;
  for k := 1 to Length(N) + 1 do
  begin
    if (k > Length(N)) or (N[k] = '/') then
    begin
      Seg := Copy(N, Start, k - Start);
      if (Length(Seg) > 1) and (Seg[Length(Seg)] = '#') then
      begin
        Seg := Copy(Seg, 1, Length(Seg) - 1);
        for j := 1 to Length(Seg) do Res := Res + Seg[j] + '\';
      end
      else Res := Res + Seg;
      if k <= Length(N) then Res := Res + '/';
      Start := k + 1;
    end;
  end;
  Result := Res;
end;

function PlainLen(N : String) : Integer;
begin
  Result := Length(N);
end;

function ElectricalOf(S : String) : TPinElectrical;
var T : String;
begin
  T := LowerCase(Trim(S));
  Result := eElectricPassive;
  if (T = 'input') or (T = 'in') or (T = 'i') then Result := eElectricInput
  else if (T = 'io') or (T = 'bidir') or (T = 'bidirectional') or (T = 'inout') then Result := eElectricIO
  else if (T = 'output') or (T = 'out') or (T = 'o') then Result := eElectricOutput
  else if (T = 'opencollector') or (T = 'oc') then Result := eElectricOpenCollector
  else if (T = 'passive') or (T = 'p') then Result := eElectricPassive
  else if (T = 'hiz') or (T = 'highz') then Result := eElectricHiZ
  else if (T = 'openemitter') or (T = 'oe') then Result := eElectricOpenEmitter
  else if (T = 'power') or (T = 'pwr') or (T = 'supply') then Result := eElectricPower;
end;

{ returns 'L','R','T','B'; '' when empty or unknown }
function SideOf(S : String) : String;
var T : String;
begin
  T := LowerCase(Trim(S));
  Result := '';
  if (T = 'l') or (T = 'left')   then Result := 'L';
  if (T = 'r') or (T = 'right')  then Result := 'R';
  if (T = 't') or (T = 'top')    then Result := 'T';
  if (T = 'b') or (T = 'bottom') then Result := 'B';
end;

{ ---------- preview drawing ---------- }
procedure DrawPin(No, Nm : String; X, Y : Integer; Rot : Integer; Len : Integer);
var
  x0, y0, x1, y1, dx, dy : Integer;
  Txt : String;
begin
  x0 := GOx + Round(X * GSc);
  y0 := GOy - Round(Y * GSc);
  dx := 0; dy := 0;
  if Rot = 0 then dx := 1;
  if Rot = 1 then dy := -1;
  if Rot = 2 then dx := -1;
  if Rot = 3 then dy := 1;
  x1 := x0 + dx * Round(Len * GSc);
  y1 := y0 + dy * Round(Len * GSc);
  GCanvas.Pen.Color := clMaroon;
  GCanvas.MoveTo(x0, y0);
  GCanvas.LineTo(x1, y1);
  GCanvas.Font.Color := clNavy;
  GCanvas.Font.Size := 7;
  Txt := DisplayName(Nm);
  GCanvas.Brush.Style := bsClear;
  if Rot = 2 then GCanvas.TextOut(x0 + 3, y0 - 6, Txt);
  if Rot = 0 then GCanvas.TextOut(x0 - 3 - GCanvas.TextWidth(Txt), y0 - 6, Txt);
  GCanvas.Font.Color := clRed;
  GCanvas.Font.Size := 6;
  if (Rot = 0) or (Rot = 2) then GCanvas.TextOut((x0 + x1) div 2 - 3, y0 - 11, No)
  else GCanvas.TextOut(x0 + 2, (y0 + y1) div 2 - 5, No);
end;

{ ---------- Altium object helpers ---------- }
procedure RegisterChild(Parent, Child : ISch_GraphicalObject);
begin
  Parent.AddSchObject(Child);
  SchServer.RobotManager.SendMessage(Parent.I_ObjectAddress, c_BroadCast,
                                     SCHM_PrimitiveRegistration, Child.I_ObjectAddress);
end;

procedure AddParam(Comp : ISch_Component; AName, AText : String);
var P : ISch_Parameter;
begin
  if AText = '' then exit;
  P := SchServer.SchObjectFactory(eParameter, eCreate_Default);
  P.Name     := AName;
  P.Text     := AText;
  P.IsHidden := True;
  P.Location := Point(MilsToCoord(-320), MilsToCoord(320));
  P.OwnerPartId := -1;
  RegisterChild(Comp, P);
end;

procedure AddPin(Comp : ISch_Component; No, Nm, Typ : String;
                 X, Y : Integer; Rot : TRotationBy90; RotNo : Integer; Len : Integer);
var Pin : ISch_Pin;
begin
  if GMode = 1 then
  begin
    DrawPin(No, Nm, X, Y, RotNo, Len);
    exit;
  end;
  Pin := SchServer.SchObjectFactory(ePin, eCreate_Default);
  Pin.Location        := Point(MilsToCoord(X), MilsToCoord(Y));
  Pin.Orientation     := Rot;
  Pin.PinLength       := MilsToCoord(Len);
  Pin.Designator      := No;
  Pin.Name            := DisplayName(Nm);
  Pin.Electrical      := ElectricalOf(Typ);
  Pin.ShowName        := True;
  Pin.ShowDesignator  := True;
  Pin.OwnerPartId     := Comp.CurrentPartID;
  Pin.OwnerPartDisplayMode := Comp.DisplayMode;
  RegisterChild(Comp, Pin);
end;

{ ---------- layout helpers (top level: DelphiScript handles these more reliably than nested routines) ---------- }
function MaxNameLen(Pins, L : TStringList) : Integer;
var
  q : Integer;
  F : TStringList;
begin
  Result := 0;
  F := TStringList.Create;
  for q := 0 to L.Count - 1 do
  begin
    ParseLine(Pins.Strings[StrToInt(L.Strings[q])], F);
    Result := MaxI(Result, PlainLen(DisplayName(FieldAt(F, 1))));
  end;
  F.Free;
end;

function SideOffset(Cnt, Span : Integer) : Integer;
begin
  Result := (Span div PIN_SPACING - (Cnt + 1)) div 2;
  if Result < 0 then Result := 0;
end;

procedure PlaceSide(Comp : ISch_Component; Pins, L : TStringList; Side : String; W, H : Integer);
var
  q, cnt, span, o : Integer;
  Order : TStringList;
  F     : TStringList;
begin
  cnt := L.Count;
  if cnt = 0 then exit;
  Order := TStringList.Create;
  F     := TStringList.Create;
  if RIGHT_TOP_CCW and ((Side = 'R') or (Side = 'T')) then
  begin
    for q := cnt - 1 downto 0 do Order.Add(L.Strings[q]);
  end
  else
  begin
    for q := 0 to cnt - 1 do Order.Add(L.Strings[q]);
  end;
  if (Side = 'L') or (Side = 'R') then span := H else span := W;
  o := SideOffset(cnt, span);
  for q := 0 to cnt - 1 do
  begin
    ParseLine(Pins.Strings[StrToInt(Order.Strings[q])], F);
    if Side = 'L' then AddPin(Comp, FieldAt(F,0), FieldAt(F,1), FieldAt(F,2), 0, -(q + 1 + o) * PIN_SPACING, eRotate180, 2, LEN_LR);
    if Side = 'R' then AddPin(Comp, FieldAt(F,0), FieldAt(F,1), FieldAt(F,2), W, -(q + 1 + o) * PIN_SPACING, eRotate0, 0, LEN_LR);
    if Side = 'T' then AddPin(Comp, FieldAt(F,0), FieldAt(F,1), FieldAt(F,2), (q + 1 + o) * PIN_SPACING, 0, eRotate90, 1, LEN_TB);
    if Side = 'B' then AddPin(Comp, FieldAt(F,0), FieldAt(F,1), FieldAt(F,2), (q + 1 + o) * PIN_SPACING, -H, eRotate270, 3, LEN_TB);
  end;
  Order.Free;
  F.Free;
end;

{ ---------- build (or draw) one component ---------- }
{ Pins: lines  "no","name",type,side }
procedure BuildComponent(SchLib : ISch_Lib; HdrNames, InfoVals : TStringList; Pins : TStringList);
var
  Comp : ISch_Component;
  Rect : ISch_Rectangle;
  Lbl  : ISch_Label;
  Impl : ISch_Implementation;
  Fld  : TStringList;
  SL, SR, ST, SB : TStringList;   // pin line indices per side
  k, i, nLR, nTB, W, H, MaxL, MaxR, MaxT, MaxB, PW, PH : Integer;
  Half : Integer;
  Sc1, Sc2 : Double;
  PartNo, Desc, Value, Foot, FootDesc, HName, S : String;
begin
  Fld := TStringList.Create;
  SL := TStringList.Create; SR := TStringList.Create;
  ST := TStringList.Create; SB := TStringList.Create;

  PartNo := ''; Desc := ''; Value := ''; Foot := ''; FootDesc := '';
  for k := 0 to HdrNames.Count - 1 do
  begin
    HName := UpperCase(Trim(HdrNames.Strings[k]));
    S := FieldAt(InfoVals, k);
    if HName = 'PART NUMBER' then PartNo := S
    else if HName = 'DESCRIPTION' then Desc := S
    else if HName = 'VALUE' then Value := S
    else if HName = 'FOOTPRINT' then Foot := S
    else if HName = 'FOOTPRINT DESCRIPTION' then FootDesc := S;
  end;
  if Value = '' then Value := PartNo;

  // sort pin lines into sides
  Half := (Pins.Count + 1) div 2;
  for i := 0 to Pins.Count - 1 do
  begin
    ParseLine(Pins.Strings[i], Fld);
    S := SideOf(FieldAt(Fld, 3));
    if PLACE_MODE = 1 then
    begin
      if i < Half then S := 'L' else S := 'R';
    end
    else if PLACE_MODE = 2 then S := 'L'
    else if (S = '') and (Trim(FieldAt(Fld, 3)) <> '') then
      Warn(PartNo + ': pin ' + FieldAt(Fld, 0) + ' has unknown Side "' + FieldAt(Fld, 3) + '" - placed Left.');
    if S = '' then S := 'L';
    if S = 'L' then SL.Add(IntToStr(i))
    else if S = 'R' then SR.Add(IntToStr(i))
    else if S = 'T' then ST.Add(IntToStr(i))
    else SB.Add(IntToStr(i));
  end;

  // body size (mil)
  nLR := MaxI(SL.Count, SR.Count);
  nTB := MaxI(ST.Count, SB.Count);
  MaxL := MaxNameLen(Pins, SL); MaxR := MaxNameLen(Pins, SR);
  MaxT := MaxNameLen(Pins, ST); MaxB := MaxNameLen(Pins, SB);
  H := MaxI(MaxI(Up100((nLR + 1) * PIN_SPACING), Up100((MaxT + MaxB) * CHAR_W + 200)), 200);
  W := MaxI(MaxI(Up100((nTB + 1) * PIN_SPACING), Up100((MaxL + MaxR) * CHAR_W + 200)), 400);

  if GMode = 1 then
  begin
    // preview: scale the symbol into the paint box
    PW := FormGen.pbPrev.Width;
    PH := FormGen.pbPrev.Height;
    Sc1 := (PW - 30) / (W + 2 * LEN_LR);
    Sc2 := (PH - 30) / (H + 2 * LEN_TB);
    if Sc1 < Sc2 then GSc := Sc1 else GSc := Sc2;
    if GSc > 0.3 then GSc := 0.3;
    if GSc <= 0 then GSc := 0.05;
    GOx := (PW - Round(W * GSc)) div 2;
    GOy := (PH + Round(H * GSc)) div 2;
    GCanvas.Pen.Color := clMaroon;
    GCanvas.Brush.Color := $B0FFFF;
    GCanvas.Brush.Style := bsSolid;
    GCanvas.Rectangle(GOx, GOy - Round(H * GSc), GOx + Round(W * GSc), GOy);
    GCanvas.Brush.Style := bsClear;
    GCanvas.Font.Color := clNavy;
    GCanvas.Font.Size := 9;
    GCanvas.TextOut(GOx + (Round(W * GSc) - GCanvas.TextWidth(Value)) div 2, GOy - Round(H * GSc / 2) - 6, Value);
    PlaceSide(nil, Pins, SL, 'L', W, H); PlaceSide(nil, Pins, SR, 'R', W, H);
    PlaceSide(nil, Pins, ST, 'T', W, H); PlaceSide(nil, Pins, SB, 'B', W, H);
  end
  else
  begin
    // component
    Comp := SchServer.SchObjectFactory(eSchComponent, eCreate_Default);
    Comp.CurrentPartID := 1;
    Comp.DisplayMode   := 0;
    Comp.LibReference  := PartNo;
    Comp.ComponentDescription := Desc;
    Comp.Designator.Text := 'U?';
    SchLib.AddSchComponent(Comp);
    SchServer.RobotManager.SendMessage(SchLib.I_ObjectAddress, c_BroadCast,
                                       SCHM_PrimitiveRegistration, Comp.I_ObjectAddress);

    // parameters: MANF_P# first, then every other column (except the ones used above)
    AddParam(Comp, 'MANF_P#', PartNo);
    for k := 0 to HdrNames.Count - 1 do
    begin
      HName := UpperCase(Trim(HdrNames.Strings[k]));
      if (HName = 'PART NUMBER') or (HName = 'DESCRIPTION') or (HName = 'FOOTPRINT') or
         (HName = 'FOOTPRINT DESCRIPTION') or (HName = 'VERIFY') or (HName = '') then continue;
      AddParam(Comp, HName, FieldAt(InfoVals, k));
    end;

    // body rectangle
    Rect := SchServer.SchObjectFactory(eRectangle, eCreate_Default);
    Rect.Location  := Point(MilsToCoord(0), MilsToCoord(-H));
    Rect.Corner    := Point(MilsToCoord(W), MilsToCoord(0));
    Rect.LineWidth := eSmall;
    Rect.Color     := $000080;
    Rect.AreaColor := $B0FFFF;
    Rect.IsSolid   := True;
    Rect.OwnerPartId := Comp.CurrentPartID;
    Rect.OwnerPartDisplayMode := Comp.DisplayMode;
    RegisterChild(Comp, Rect);

    // "=VALUE" label in the body centre
    Lbl := SchServer.SchObjectFactory(eLabel, eCreate_Default);
    Lbl.Location := Point(MilsToCoord(W div 2), MilsToCoord(-(H div 2)));
    Lbl.Justification := eJustify_Center;
    Lbl.Text := '=VALUE';
    Lbl.OwnerPartId := Comp.CurrentPartID;
    Lbl.OwnerPartDisplayMode := Comp.DisplayMode;
    RegisterChild(Comp, Lbl);

    // pins
    PlaceSide(Comp, Pins, SL, 'L', W, H); PlaceSide(Comp, Pins, SR, 'R', W, H);
    PlaceSide(Comp, Pins, ST, 'T', W, H); PlaceSide(Comp, Pins, SB, 'B', W, H);

    // optional footprint link
    if Foot <> '' then
    begin
      try
        Impl := Comp.AddSchImplementation;
        Impl.ModelName   := Foot;
        Impl.ModelType   := 'PCBLIB';
        Impl.Description := FootDesc;
        Impl.IsCurrent   := True;
        Impl.AddDataFileLink(Foot, '', 'PCBLib');
      except
        ShowMessage(PartNo + ': footprint link could not be created (pins/symbol are fine).');
      end;
    end;
  end;

  Fld.Free; SL.Free; SR.Free; ST.Free; SB.Free;
end;

{ called once per parsed part; behaviour depends on GMode }
procedure HandlePart(SchLib : ISch_Lib; Hdr, Info, Pins : TStringList);
var
  k, Idx : Integer;
  Nm : String;
begin
  Nm := '';
  for k := 0 to Hdr.Count - 1 do
    if UpperCase(Trim(Hdr.Strings[k])) = 'PART NUMBER' then Nm := FieldAt(Info, k);
  GNames := GNames + Nm + '|';
  Inc(GNameCount);
  GPinTotal := GPinTotal + Pins.Count;
  Idx := GPartSeq;
  Inc(GPartSeq);
  if GMode = 0 then exit;
  if (GMode = 1) and (Idx <> GPreviewIdx) then exit;
  BuildComponent(SchLib, Hdr, Info, Pins);
end;

{ ---------- text -> parts ---------- }
{ FreePart/FreeDesc/FreePkg/FreeFoot: used when the text holds only pin rows }
function ProcessText(Lines : TStringList; SchLib : ISch_Lib;
                     FreePart, FreeDesc, FreePkg, FreeFoot : String) : Integer;
var
  F, Hdr, Info, Pins : TStringList;
  i, Count : Integer;
  First : String;
  AnyBlock : Boolean;
begin
  F := TStringList.Create; Hdr := TStringList.Create;
  Info := TStringList.Create; Pins := TStringList.Create;
  Count := 0;
  AnyBlock := False;
  // drop chatbot code-fence lines (```csv ... ```)
  for i := Lines.Count - 1 downto 0 do
    if Copy(Trim(Lines.Strings[i]), 1, 3) = '```' then Lines.Delete(i);
  i := 0;
  while i < Lines.Count do
  begin
    ParseLine(Lines.Strings[i], F);
    First := LowerCase(Trim(FieldAt(F, 0)));
    // Pos() also tolerates a UTF-8 BOM in front of the first header
    if Pos('part number', First) > 0 then
    begin
      AnyBlock := True;
      ParseLine(Lines.Strings[i], Hdr);
      Hdr.Strings[0] := 'Part Number';
      Info.Clear;
      if i + 1 < Lines.Count then ParseLine(Lines.Strings[i + 1], Info);
      i := i + 2;
      Pins.Clear;
      F.Clear;
      if i < Lines.Count then ParseLine(Lines.Strings[i], F);
      if LowerCase(Trim(FieldAt(F, 0))) = 'pin no.' then
      begin
        Inc(i);
        while i < Lines.Count do
        begin
          ParseLine(Lines.Strings[i], F);
          if IsBlankRow(F) then break;
          if Pos('part number', LowerCase(FieldAt(F, 0))) > 0 then break;
          Pins.Add(Quote(FieldAt(F, 0)) + ',' + Quote(FieldAt(F, 1)) + ',' + FieldAt(F, 2) + ',' + FieldAt(F, 3));
          Inc(i);
        end;
        if (Info.Count > 0) and (Pins.Count > 0) then
        begin
          HandlePart(SchLib, Hdr, Info, Pins);
          Inc(Count);
        end;
      end
      else Warn('No "Pin No." table after the part row (line ' + IntToStr(i + 1) + ').');
    end
    else Inc(i);
  end;

  // pins-only text: every non-blank row (except a "Pin No." header) is a pin
  if not AnyBlock then
  begin
    Pins.Clear;
    for i := 0 to Lines.Count - 1 do
    begin
      ParseLine(Lines.Strings[i], F);
      if IsBlankRow(F) then continue;
      if LowerCase(Trim(FieldAt(F, 0))) = 'pin no.' then continue;
      if Trim(FieldAt(F, 1)) = '' then continue;
      Pins.Add(Quote(FieldAt(F, 0)) + ',' + Quote(FieldAt(F, 1)) + ',' + FieldAt(F, 2) + ',' + FieldAt(F, 3));
    end;
    if Pins.Count > 0 then
    begin
      if Trim(FreePart) = '' then FreePart := 'NEW_PART';
      Hdr.Clear; Info.Clear;
      Hdr.Add('Part Number');  Info.Add(FreePart);
      Hdr.Add('VALUE');        Info.Add(FreePart);
      Hdr.Add('Description');  Info.Add(FreeDesc);
      Hdr.Add('Package');      Info.Add(FreePkg);
      Hdr.Add('Footprint');    Info.Add(FreeFoot);
      HandlePart(SchLib, Hdr, Info, Pins);
      Inc(Count);
    end;
  end;

  F.Free; Hdr.Free; Info.Free; Pins.Free;
  Result := Count;
end;

{ ---------- Altium library handling ---------- }
function GetLibrary(NewLib : Boolean) : ISch_Lib;
var
  LibDlg    : TOpenDialog;
  ServerDoc : IServerDocument;
  LibPath   : String;
begin
  Result := nil;
  if NewLib then
  begin
    try
      ServerDoc := Client.OpenNewDocument('SCHLIB', 'ChilaLib.SchLib', '', False);
      if ServerDoc <> nil then Client.ShowDocument(ServerDoc);
    except
      ShowMessage('Could not create a new library automatically. Create one with File > New > Library > Schematic Library, then choose "Open library".');
      exit;
    end;
    Result := SchServer.GetCurrentSchDocument;
    exit;
  end;

  Result := SchServer.GetCurrentSchDocument;
  if Result = nil then
  begin
    // focused document is not a schematic document: pick the .SchLib, open + focus it
    LibDlg := TOpenDialog.Create(nil);
    LibDlg.Filter := 'Schematic library (*.SchLib)|*.SchLib';
    LibDlg.Title  := 'Select the .SchLib to add components to';
    if LibDlg.Execute then
    begin
      LibPath := LibDlg.FileName;
      ServerDoc := Client.OpenDocument('SCHLIB', LibPath);
      if ServerDoc <> nil then Client.ShowDocument(ServerDoc);
      Result := SchServer.GetCurrentSchDocument;
    end;
    LibDlg.Free;
  end;
end;

{ remove the empty "Component_1" that a new library starts with (best effort) }
procedure RemoveDefaultComponent(SchLib : ISch_Lib);
var
  Iter : ISch_Iterator;
  C    : ISch_Component;
  Victim : ISch_Component;
begin
  Victim := nil;
  try
    Iter := SchLib.SchLibIterator_Create;
    Iter.AddFilter_ObjectSet(MkSet(eSchComponent));
    C := Iter.FirstSchObject;
    while C <> nil do
    begin
      if (C.LibReference = 'Component_1') and (Victim = nil) then Victim := C;
      C := Iter.NextSchObject;
    end;
    SchLib.SchIterator_Destroy(Iter);
    if Victim <> nil then SchLib.RemoveSchComponent(Victim);
  except
  end;
end;

{ ---------- window logic ---------- }
procedure ReadOptions;
begin
  PIN_SPACING := StrToIntDef(FormGen.eSpacing.Text, 100);
  if PIN_SPACING < 50 then PIN_SPACING := 50;
  LEN_LR := StrToIntDef(FormGen.eLenLR.Text, 300);
  LEN_TB := StrToIntDef(FormGen.eLenTB.Text, 100);
  CHAR_W := 80;
  ACTIVE_LOW_OVERBAR := FormGen.cbActive.ItemIndex = 1;
  RIGHT_TOP_CCW      := FormGen.cbOrder.ItemIndex = 0;
  PLACE_MODE         := FormGen.cbPlace.ItemIndex;
end;

procedure RefreshScan;
var
  Lines : TStringList;
  Old, n, k : Integer;
  Cur : String;
begin
  ReadOptions;
  Lines := TStringList.Create;
  Lines.Text := FormGen.memoIn.Lines.Text;
  GMode := 0; GPartSeq := 0; GPinTotal := 0; GWarn := '';
  GNames := ''; GNameCount := 0;
  n := ProcessText(Lines, nil, FormGen.ePart.Text, FormGen.eDesc.Text, FormGen.ePackage.Text, FormGen.eFootprint.Text);
  Lines.Free;
  Old := FormGen.cbPart.ItemIndex;
  FormGen.cbPart.Items.Clear;
  Cur := '';
  for k := 1 to Length(GNames) do
  begin
    if GNames[k] = '|' then
    begin
      FormGen.cbPart.Items.Add(Cur);
      Cur := '';
    end
    else Cur := Cur + GNames[k];
  end;
  if (Old >= 0) and (Old < GNameCount) then FormGen.cbPart.ItemIndex := Old
  else if GNameCount > 0 then FormGen.cbPart.ItemIndex := 0;
  FormGen.lblStatus.Caption := IntToStr(n) + ' part(s), ' + IntToStr(GPinTotal) + ' pin(s). ' + GWarn;
  FormGen.pbPrev.Invalidate;
end;

procedure TFormGen.optChange(Sender : TObject);
begin
  RefreshScan;
end;

procedure TFormGen.cbPartChange(Sender : TObject);
begin
  FormGen.pbPrev.Invalidate;
end;

procedure TFormGen.pbPrevPaint(Sender : TObject);
var
  Lines : TStringList;
  n : Integer;
begin
  GCanvas := FormGen.pbPrev.Canvas;
  GCanvas.Brush.Color := clWhite;
  GCanvas.Brush.Style := bsSolid;
  GCanvas.Pen.Color := clWhite;
  GCanvas.Rectangle(0, 0, FormGen.pbPrev.Width, FormGen.pbPrev.Height);
  if (FormGen.cbPart.ItemIndex < 0) or (FormGen.cbPart.Items.Count = 0) then exit;
  ReadOptions;
  Lines := TStringList.Create;
  Lines.Text := FormGen.memoIn.Lines.Text;
  GMode := 1; GPartSeq := 0; GPinTotal := 0; GWarn := '';
  GPreviewIdx := FormGen.cbPart.ItemIndex;
  GNames := ''; GNameCount := 0;
  n := ProcessText(Lines, nil, FormGen.ePart.Text, FormGen.eDesc.Text, FormGen.ePackage.Text, FormGen.eFootprint.Text);
  Lines.Free;
  GMode := 0;
end;

procedure LoadDemo;
begin
  FormGen.memoIn.Lines.Clear;
  FormGen.memoIn.Lines.Add('Part Number,VALUE,Description,PARAM,PARAM2,Package,Price,Footprint');
  FormGen.memoIn.Lines.Add('DEMO-MCU,DEMO-MCU,"MCU, Demo, 32-bit, 64KB, QFN-16",3.3V,-40~85C,QFN-16,,');
  FormGen.memoIn.Lines.Add('Pin No.,Pin Name,Type,Side');
  FormGen.memoIn.Lines.Add('1,VDD,Power,Top');
  FormGen.memoIn.Lines.Add('2,PA0/ADC0/TIM2_CH1,IO,Left');
  FormGen.memoIn.Lines.Add('3,PA1/ADC1/TIM2_CH2,IO,Left');
  FormGen.memoIn.Lines.Add('4,PA2/USART2_TX,IO,Left');
  FormGen.memoIn.Lines.Add('5,PA3/USART2_RX,IO,Left');
  FormGen.memoIn.Lines.Add('6,RESET#,Input,Left');
  FormGen.memoIn.Lines.Add('7,BOOT0,Input,Left');
  FormGen.memoIn.Lines.Add('8,PB0/SPI1_NSS,IO,Right');
  FormGen.memoIn.Lines.Add('9,PB1/SPI1_SCK,IO,Right');
  FormGen.memoIn.Lines.Add('10,PB2/SPI1_MISO,IO,Right');
  FormGen.memoIn.Lines.Add('11,PB3/SPI1_MOSI,IO,Right');
  FormGen.memoIn.Lines.Add('12,SWDIO,IO,Right');
  FormGen.memoIn.Lines.Add('13,SWCLK,Input,Right');
  FormGen.memoIn.Lines.Add('14,GND,Power,Bottom');
  FormGen.memoIn.Lines.Add('15,VSSA,Power,Bottom');
  FormGen.memoIn.Lines.Add('16,VDDA,Power,Top');
end;

procedure TFormGen.bDemoClick(Sender : TObject);
begin
  LoadDemo;
  RefreshScan;
end;

procedure TFormGen.bClearClick(Sender : TObject);
begin
  FormGen.memoIn.Lines.Clear;
  RefreshScan;
end;

procedure TFormGen.bLoadClick(Sender : TObject);
var Dlg : TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  Dlg.Filter := 'CSV / text (*.csv;*.txt)|*.csv;*.txt|All files (*.*)|*.*';
  Dlg.Title  := 'Select parts CSV (part info + Pin table)';
  if Dlg.Execute then
  begin
    FormGen.memoIn.Lines.LoadFromFile(Dlg.FileName);
    RefreshScan;
  end;
  Dlg.Free;
end;

procedure TFormGen.FormGenShow(Sender : TObject);
begin
  if FormGen.memoIn.Lines.Count = 0 then LoadDemo;
  RefreshScan;
end;

procedure TFormGen.bCloseClick(Sender : TObject);
begin
  FormGen.Close;
end;

procedure TFormGen.bGenerateClick(Sender : TObject);
var
  Lines  : TStringList;
  SchLib : ISch_Lib;
  n      : Integer;
begin
  ReadOptions;
  RefreshScan;
  if GNameCount = 0 then
  begin
    ShowMessage('Nothing to generate: no pins found in the text.');
    exit;
  end;
  SchLib := GetLibrary(FormGen.rgTarget.ItemIndex = 0);
  if SchLib = nil then
  begin
    ShowMessage('No schematic library available. Open a .SchLib (or choose "New library") and try again.');
    exit;
  end;
  Lines := TStringList.Create;
  Lines.Text := FormGen.memoIn.Lines.Text;
  GMode := 2; GPartSeq := 0; GPinTotal := 0; GWarn := '';
  GNames := ''; GNameCount := 0;
  SchServer.ProcessControl.PreProcess(SchLib, '');
  n := ProcessText(Lines, SchLib, FormGen.ePart.Text, FormGen.eDesc.Text, FormGen.ePackage.Text, FormGen.eFootprint.Text);
  SchServer.ProcessControl.PostProcess(SchLib, '');
  if FormGen.rgTarget.ItemIndex = 0 then RemoveDefaultComponent(SchLib);
  SchLib.GraphicallyInvalidate;
  GMode := 0;
  Lines.Free;
  RefreshScan;
  ShowMessage(IntToStr(n) + ' component(s) created. Review them in the SCH Library panel, then save the library.');
end;

{ ---------- entry point ---------- }
procedure CreateFromCSV;
begin
  // make sure the schematic server is running (it is not started until a schematic document has been opened)
  try
    Client.StartServer('SCH');
  except
  end;
  FormGen.ShowModal;
end;

procedure Run;
begin
  CreateFromCSV;
end;
