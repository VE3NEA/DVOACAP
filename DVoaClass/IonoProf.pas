//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is IonoProf.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit IonoProf;

interface

uses
  SysUtils, Math, VoaTypes, PathGeom;


const
  HmD = 70;  //D layer height
  HmE = 110; //E layer height
  YmE = 20;  //E layer semi-thickness

  BotE = HmE - 0.85 * YmE;
  TopE = HmE + YmE;

  Fnx = 1 - 0.85 * 0.85;
  Alp = 2 * (HmE - BotE) / (Fnx * Sqr(YmE));


type
  TIonoProfile = class
  private
    FcE, FcV_bot, FcV_top, FcF1, FcF2: Single;
    BotV, TopV, BotF1, TopF1, BotF2: Single;
    SlopeV: Single;
    SlopeF1: Single;
    LinearF1: boolean;

    FMhz: Single;
    FTrueH: Single;

    //electron density profile
    DensTrueHeight: TSingleArray;  //argument
    ElDensity: TSingleArray;       //function

    procedure AnalyzeLayers;
    procedure PopulateTrueHeightArray;
    procedure PopulateElectronDensityArray;
    function DensityToHeight(ADens: Single): Single;
    function HeightToDensity(AHeight: Single): Single;
  public
    Lat, MagLat: Single;
    LocalTimeE, LocalTimeF2: TDateTime;

    E, F1, F2: TLayerInfo;
    Layers: array[TIonoLayer] of PLayerInfo;

    //ionogram
    IgramVertFreq: TSingleArray;   //argument
    IgramTrueHeight: TSingleArray; //function
    IgramVirtHeight: TSingleArray; //function

    //deviative loss, function of IgramTrueHeight
    DevLoss: TSingleArray;

    //oblique frequency, function of IgramTrueHeight and angle index in Angles
    ObliqueFreq: array of array of Integer;

    //computed elsewhere and assigned to profile
    AbsorptionIndex: Single;
    ExcessiveSystemLoss: TDistribution;
    GyroFreq: Single;

    constructor Create;

    procedure ComputeElDensityProfile;
    function GetTrueHeight(AMhz: Single): Single;
    function GetVirtualHeightGauss(AMhz: Single): Single;

    procedure ComputeIonogram;
    procedure ComputeObliqueFreqs(AAngleCount: integer);
    procedure ComputeDeviativeLoss(Mufs: TMufInfoArray);
    function ComputePenetrationAngles(AMHz: Single): TLayerParamArray;
    procedure PopulateModeInfo(var AMode: TModeInfo; AIdx: integer; AFrac: Single = 0);
  end;


  TIonoProfiles = array of TIonoProfile;


function CorrToMartynsTheorem(const ARef: TReflection): Single;
function GetIndexOf(AValue: Single; AArray: TSingleArray): integer;
function InterpolateTable(X: Single; ArrX, ArrY: TSingleArray): Single;





implementation

//------------------------------------------------------------------------------
//                         helper functions
//------------------------------------------------------------------------------
function GetIndexOf(AValue: Single; AArray: TSingleArray): integer;
var
  f: integer;
begin
  if AValue <= AArray[1] then begin Result := 1; Exit; end;

  for f:=1 to High(AArray)-1 do
    if AArray[f] = AValue then
      begin Result := f; Exit; end
    else if Sign(AValue - AArray[f]) <> Sign(AValue - AArray[f+1]) then
      begin Result := f; Exit; end;

  Result := High(AArray);
end;


function InterpolateTable(X: Single; ArrX, ArrY: TSingleArray): Single;
var
  Idx: integer;
  r: Single;
begin
  Assert(Length(ArrY) = Length(ArrX));

  //before table start
  if X <= ArrX[1] then begin Result := ArrY[1]; Exit; end;
  Idx := GetIndexOf(X, ArrX);
  //after table end, or exact match
  if (Idx = High(ArrX)) or (X = ArrX[Idx]) then begin Result := ArrY[Idx]; Exit; end;
  //linear
  r := (X - ArrX[Idx]) / (ArrX[Idx+1] - ArrX[Idx]);
  Result := ArrY[Idx] * (1-r) + ArrY[Idx+1] * r;
end;


//populate table with linearly interpolated data
procedure Interpolate(StartH, EndH: integer; Arr: TSingleArray);
var
  Dif: Single; h: integer;
begin
  Dif := (Arr[EndH] - Arr[StartH]) / (EndH - StartH);
  for h:=StartH+1 to EndH-1 do Arr[h] := Arr[h-1] + Dif;
end;


function CorrToMartynsTheorem(const ARef: TReflection): Single;
var
  dH: Single;
begin
  dH := (ARef.VirtHeight - ARef.TrueHeight) / EarthR;
  Result := dH * (ARef.TrueHeight + 2 * (EarthR + ARef.TrueHeight) * dH);
end;




{ TIonospericProfile }

constructor TIonoProfile.Create;
begin
  //for convenience, layer info can be accessed either by layer or by index
  Layers[lrE] := @E;
  Layers[lrF1] := @F1;
  Layers[lrF2] := @F2;
end;






//------------------------------------------------------------------------------
//                  electron density profile, Ne=F(height)
//------------------------------------------------------------------------------
procedure TIonoProfile.ComputeElDensityProfile;
begin
  if DensTrueHeight <> nil then Exit;

  SetLength(DensTrueHeight, 51);
  SetLength(ElDensity, 51);

  AnalyzeLayers;
  PopulateTrueHeightArray;
  PopulateElectronDensityArray;
end;


procedure TIonoProfile.AnalyzeLayers;
const
  XLow = 0.8516;
var
  XUp, Htw: Single;
  Ys, Yb: Single;
begin
  //MUST CHECK ON F1 LAYER PARAMETERS FIRST
  XUp := 0.98 * E.Fo / F2.Fo;
  BotV := HmE + YmE * Sqrt(1 - Sqr(XLow));
  BotF2 := F2.Hm - F2.Ym;
  FcE := Sqr(E.Fo);
  FcF2 := Sqr(F2.Fo);

  //VALLEY FILLED FROM (FcV_bot,BotV) TO (FcV_top,TopV)
  TopV := BotF2 + F2.Ym * (1 - Sqrt(1 - Sqr(Xup)));
  FcV_top := Sqr(Xup) * FcF2;
  FcV_bot := Sqr(XLow) * FcE;
  if TopV > BotV
    then SlopeV := (FcV_top - FcV_bot) / (TopV - BotV)
    else SlopeV := 0;

  //F1 layer does not exist
  if F1.Fo <= 0 then Exit;

  FcF1 := Sqr(F1.Fo);
  BotF1 := F1.Hm - F1.Ym;
  TopF1 := F1.Hm + F1.Ym;

  //HEIGHT OF F2 AT F1 CRITICAL FREQUENCY
  Htw := BotF2 + F2.Ym * (1 - Sqrt(1 - FcF1 / FcF2));

  //FORCE F1 ABOVE E LAYER
  if Htw > (F1.Hm + 0.001) then
    begin
    LinearF1 := false;
    F1.Ym := Min(F1.Ym, F1.Hm - HmE + 1);
    Exit;
    end;

  //FORCE F1 AT CRITICAL FREQUENCY
  Ys := Max(1, Htw - BotF1);
  //SLOPE OF LINEAR F1
  SlopeF1 := FcF1 / Ys;
  F1.Hm := Htw;
  F1.Ym := Ys;

  //AVOID A SPURIOUS LAYER
  if BotF2 < BotF1 then
    begin
    LinearF1 := false;
    F1.Ym := F1.Hm - Max(BotF2, HmE - 1);
    Exit;
    end;

  //SET FLAG TO INDICATE LINEAR LAYER FOR F1
  LinearF1 := true;

  //F1 LINE NOT TO OBSCURE E LAYER
  Yb := 1 - Sqr(E.Fo / F1.Fo);
  Yb := Max(0.17, Yb);
  Yb := (F1.Hm - HmE) / Yb;

  //F1 PASSES THROUGH E NOSE
  if Ys >= Yb then
    begin
    Ys := Yb;
    F1.Ym := Ys;
    SlopeF1 := FcF1 / Ys;
    BotF1 := HmE;
    end;

  TopF1 := Htw;
end;


procedure TIonoProfile.PopulateTrueHeightArray;
var
  Dif: Single;
  i: integer;
begin
  Dif := Max(0, 0.25 * (BotE - HmD));
  DensTrueHeight[1] := HmD;
  DensTrueHeight[2] := DensTrueHeight[1] + Dif;
  DensTrueHeight[4] := BotE - Min(1, Dif);
  DensTrueHeight[3] := 0.5 * (DensTrueHeight[2] + DensTrueHeight[4]);
  DensTrueHeight[5] := BotE;

  //E  BELOW NOSE
  DensTrueHeight[11] := HmE;
  Interpolate(5, 11, DensTrueHeight);

  //E ABOVE  NOSE
  DensTrueHeight[17] := HmE + YmE;
  Interpolate(11, 17, DensTrueHeight);
  DensTrueHeight[11] := 0.5 * (DensTrueHeight[10] + DensTrueHeight[12]);

  //F1/F2
  DensTrueHeight[50] := F2.Hm;
  if (F1.Fo = 0) or ((F2.Hm - F2.Ym) <= (F1.Hm - F1.Ym + 0.00001))
    then
      begin //F2  LAYER, NO F1 LAYER
      DensTrueHeight[18] := F2.Hm - F2.Ym;
      Interpolate(18, 50, DensTrueHeight);
      end
    else
      begin //F1 LAYER AND F2 LAYER
      DensTrueHeight[18] := Max(DensTrueHeight[17] + 1, F1.Hm - F1.Ym);
      DensTrueHeight[28] := F1.Hm;
      Interpolate(18, 28, DensTrueHeight);
      Interpolate(28, 50, DensTrueHeight);
      end;
end;


procedure TIonoProfile.PopulateElectronDensityArray;
var
  Fsq, Height: Single;
  FnD, FnE, FnVal, FnF1, FnF2: Single;
  h: integer;
begin
  //SLOPE OF E IS SAME AS SLOPE OF Valley AT BotE
  Fsq := Fnx * Exp(-Alp * (BotE - HmD));

  //FORCE F1 ABOVE E LAYER
  //isn't this already done in CheckF1Params?
  if F1.Fo > 0 then BotF1 := Max(HmE, F1.Hm - F1.Ym) else BotF1 := 0;


  for h:=1 to 50 do
    begin
    Height := DensTrueHeight[h];

    FnD := 0; FnE := 0; FnVal := 0; FnF1 := 0; FnF2 := 0;

    //LINEAR VALLEY
    if (Height > BotV) and (Height < TopV)
      then FnVal := FcV_top + SlopeV * (Height - TopV);

    //EXPONENTIAL D-E
    if Height < BotE
      then FnD := FcE * Fsq * Exp(Alp * (Height - HmD))

    //PARABOLIC E
    else if Height <= TopE                   
      then FnE := FcE * (1 - Sqr((Height - HmE) / YmE));

    if (F1.Fo > 0) and (Height >= BotF1) and (Height <= TopF1) then
      if LinearF1
        //LINEAR F1
        then FnF1 := SlopeF1 * (Height - (F1.Hm - F1.Ym))
        //PARABOLIC F1
        else FnF1 := FcF1 * (1 - Sqr((Height - F1.Hm) / F1.Ym));

    //PARABOLIC F2
    if Height >= BotF2
      then FnF2 := FcF2 * (1 - Sqr((Height - F2.Hm) / F2.Ym));

    //USE THE MAXIMUM
    ElDensity[h] := MaxValue([FnD, FnE, FnVal, FnF1, FnF2]);
    end;
end;






//------------------------------------------------------------------------------
//                  true height <-> electron density
//------------------------------------------------------------------------------
function TIonoProfile.DensityToHeight(ADens: Single): Single;
var
  r: Single;
  h: integer;
begin
  //FIND THE TRUE HEIGHT BY INTERPOLATION

  if ADens <= ElDensity[1] then
    begin
    Result := DensTrueHeight[1];
    Exit;
    end;

  for h:=2 to High(ElDensity) do
    if ADens <= ElDensity[h] then
      begin
      r := (ADens - ElDensity[h-1]) / (ElDensity[h] - ElDensity[h-1]);
      Result := DensTrueHeight[h-1] * (1-r) + DensTrueHeight[h] * r;
      Exit;
      end;

  Result := DensTrueHeight[50];
end;


function TIonoProfile.HeightToDensity(AHeight: Single): Single;
var
  r: Single;
  h: integer;
begin
  Result := ElDensity[1];
  if AHeight <= DensTrueHeight[1] then Exit

  else if AHeight >= DensTrueHeight[High(DensTrueHeight)] then
    Result := ElDensity[High(ElDensity)]

 else
    for h:=2 to High(DensTrueHeight) do
      if AHeight <= DensTrueHeight[h] then
        begin
        r := (AHeight - DensTrueHeight[h-1]) / (DensTrueHeight[h] - DensTrueHeight[h-1]);
        Result := ElDensity[h-1] * (1-r) + ElDensity[h] * r;
        Break;
        end;
end;






//------------------------------------------------------------------------------
//                true and virtual height for frequency
//------------------------------------------------------------------------------
function TIonoProfile.GetTrueHeight(AMhz: Single): Single;
begin
  FMhz := AMhz;
  FTrueH := DensityToHeight(Sqr(AMhz));
  Result := FTrueH;
end;


function TIonoProfile.GetVirtualHeightGauss(AMhz: Single): Single;
var
  Dens, Ht, Ymup, Zmup: Single;
  i: integer;
begin
  if AMhz <> FMhz then GetTrueHeight(AMhz);
  Ht := FTrueH - DensTrueHeight[1];

  Dens := Sqr(AMhz);
  Result := 0;

  //GAUSSIAN INTEGRATION
  for i:=0 to High(XT) do
    begin
    Ymup := DensTrueHeight[1] + Ht * (1 - TWDIV * (1 - XT[i]));
    Ymup := Min(0.9999, HeightToDensity(Ymup) / Dens);
    Ymup := 1 / Sqrt(1 - Ymup);

    Zmup := DensTrueHeight[1] + Ht * (1 - TWDIV * (1 + XT[i]));
    Zmup := Min(0.9999, HeightToDensity(Zmup) / Dens);
    Zmup := 1 / Sqrt(1 - Zmup);

    Result := Result + WT[i] * (Ymup + Zmup);
    end;

  Result := DensTrueHeight[1] + Ht * TWDIV * Result;
end;




//------------------------------------------------------------------------------
//                      ionogram, height=F(freq)
//------------------------------------------------------------------------------
procedure TIonoProfile.ComputeIonogram;
var
  i: integer;
begin
  if IgramTrueHeight <> nil then Exit;
  if DensTrueHeight = nil then ComputeElDensityProfile;

  SetLength(IgramTrueHeight, 31);
  SetLength(IgramVirtHeight, 31);
  SetLength(IgramVertFreq, 31);

  //D-E  REGION TAIL
  IgramVertFreq[1] := 0.01;
  IgramVertFreq[4] := E.Fo * Sqrt(Fnx);
  Interpolate(1, 4, IgramVertFreq);

  //E REGION NOSE
  IgramVertFreq[9] := 0.957 * E.Fo;
  IgramVertFreq[10] := 0.99 * E.Fo;
  Interpolate(4, 9, IgramVertFreq);

  //E - F CUSP
  IgramVertFreq[11] := 1.05 * E.Fo;

  //F REGION NOSE
  IgramVertFreq[30] := 0.99 * F2.Fo;
  IgramVertFreq[29] := 0.98 * F2.Fo;
  IgramVertFreq[28] := 0.96 * F2.Fo;
  IgramVertFreq[27] := 0.92 * F2.Fo;

  if F1.Fo > 0
    then
      begin
      //F1 LAYER  AND F2 LAYER
      IgramVertFreq[20] := 0.99 * F1.Fo;
      Interpolate(11, 20, IgramVertFreq);
      //F1 - F2 CUSP
      IgramVertFreq[21] := 1.01 * F1.Fo;
      Interpolate(21, 27, IgramVertFreq);
      end

    else
      //F2 LAYER, NO F1 LAYER
      Interpolate(11, 27, IgramVertFreq);

  //compute height for each frequency
  for i:=1 to High(IgramVertFreq) do
    begin
    IgramTrueHeight[i] := GetTrueHeight(IgramVertFreq[i]);
    IgramVirtHeight[i] := GetVirtualHeightGauss(IgramVertFreq[i]);
    end;
end;


procedure TIonoProfile.ComputeObliqueFreqs(AAngleCount: integer);
var
  a, h: integer;
  R_CosA: Single;
begin
  if ObliqueFreq <> nil then Exit;

  SetLength(ObliqueFreq, AAngleCount+1, Length(IgramTrueHeight));

  for a:=1 to High(ObliqueFreq) do
    begin
    R_CosA := EarthR * Cos(Angles[a]);
    for h:=1 to High(IgramTrueHeight) do
      ObliqueFreq[a,h] := Trunc(1000 * IgramVertFreq[h] / Sqrt(1 - Sqr(R_CosA / (EarthR + IgramTrueHeight[h]))));
    end;
end;


procedure TIonoProfile.ComputeDeviativeLoss(Mufs: TMufInfoArray);
var
  Hm, Hz, Cf, A: Single;
  h: integer;

  function ComputeExp(Ym: Single; Mx: Single = 0.05): Single;
  begin
    Cf := -2 * (IgramTrueHeight[h] - Hz) / Ym;
    Cf := Max(-10, Cf);
    Cf := A * Exp(Cf);
    if Mx > 0 then Cf := Max(Mx, Cf);
    Result := Cf * (IgramVirtHeight[h] - IgramTrueHeight[h] - Hm);
    Result := Max(0, Result);
  end;

begin
  if DevLoss <> nil then Exit;

  SetLength(DevLoss, 31);


  //E LAYER
  A := 0.2;
  Hz := HmE - YmE;
  Hm := Mufs[lrE].Ref.VirtHeight - Mufs[lrE].Ref.TrueHeight;
  for h:=1 to 10 do
    if IgramTrueHeight[h] > Mufs[lrE].Ref.TrueHeight then
      DevLoss[h] := ComputeExp(YmE, 0);


  if F1.Fo > 0
    then
      begin
      //F1  LAYER
      //CONTINUITY AT E TO F1 CUSP
      A := Cf;
      Hz := IgramTrueHeight[11];
      Hm := IgramVirtHeight[13] - IgramTrueHeight[13];
      for h:=11 to 12 do DevLoss[h] := ComputeExp(F1.Ym);

      DevLoss[13] := 0;

      A := 0.1;
      Hm := Mufs[lrF1].Ref.VirtHeight - Mufs[lrF1].Ref.TrueHeight;
      for h:=14 to 20 do
        if IgramTrueHeight[h] > Mufs[lrF1].Ref.TrueHeight then
        DevLoss[h] := ComputeExp(F1.Ym);

      //F2 LAYER WITH F1 LEDGE
      //FORCES CONTINUITY AT F1 TO F2 LAYER
      A := Cf;
      Hz := IgramTrueHeight[21];
      Hm := IgramVirtHeight[23] - IgramTrueHeight[23];
      for h:=21 to 22 do
        DevLoss[h] := ComputeExp(F2.Ym);

      DevLoss[23] := 0;

      A := 0.1;
      Hm := Mufs[lrF2].Ref.VirtHeight - Mufs[lrF2].Ref.TrueHeight;
      for h:=24 to 30 do
        if IgramTrueHeight[h] > Mufs[lrF2].Ref.TrueHeight then
          DevLoss[h] := ComputeExp(F2.Ym);
      end

    else
      begin
      //F2 LAYER WITH NO F1 LEDGE
      //CONTINUITY AT E TO F2 CUSP
      A := Cf;
      Hz := IgramTrueHeight[11];
      Hm := IgramVirtHeight[13] - IgramTrueHeight[13];
      for h:=11 to 12 do DevLoss[h] := ComputeExp(F2.Ym);

      DevLoss[13] := 0;

      A := 0.1;
      Hm := Mufs[lrF2].Ref.VirtHeight - Mufs[lrF2].Ref.TrueHeight;
      for h:=14 to 30 do
        if IgramTrueHeight[h] > Mufs[lrF2].Ref.TrueHeight then
          DevLoss[h] := ComputeExp(F2.Ym, 0.5);
      end;
end;


function TIonoProfile.ComputePenetrationAngles(AMHz: Single): TLayerParamArray;
var
  Frat: Single;
  Xm28, Xm29, Xm30, Xm: Single;

  function ComputeElev(Height: Single): Single;
  begin
    Result := (EarthR + Height) * Sqrt(1 - FRat) / EarthR;
    if Result > 0.999999 then Result := 0 else Result := ArcCos(Result);
  end;

begin
  //USE CUSP FOR E LAYER
  Frat := Sqr(IgramVertFreq[10] / AMhz);
  if Frat < 0.9999
    then
      Result[lrE] := ComputeElev(IgramTrueHeight[10])
    else
      begin
      Result[lrE] := JUST_BELOW_MAX_ELEV;  //89.9 deg.
      Result[lrF1] := HALF_PI;             //90 deg.
      Result[lrF2] := HALF_PI;
      Exit;
      end;


  if F1.Fo > 0
    then
      begin
      //JUST USE CUSP FOR F1 LAYER
      Frat := Sqr(IgramVertFreq[20] / AMhz);
      if Frat < 0.9999
        then Result[lrF1] := ComputeElev(IgramTrueHeight[20])
        else begin Result[lrF1] := 89.9 * RinD; Result[lrF2] := 90 * RinD; Exit; end;
      end

    else
      //no F1 layer
      Result[lrF1] := Result[lrE];


  //REFLECTION UNTIL MAX(RZ+HT)*MU , NOT UNTIL MIDDLE OF LAYER
  //BUT F LAYER IS SENSITIVE TO SPERICAL SYMMETRY DUE TO THICKNESS
  if AMhz <= (IgramVertFreq[30] + 0.0001) then
    begin Result[lrF2] := MAX_NON_POLE_LAT; Exit; end;

  Xm28 := (EarthR + IgramTrueHeight[28]) * Sqrt(1 - Sqr(IgramVertFreq[28] / AMhz));
  Xm29 := (EarthR + IgramTrueHeight[29]) * Sqrt(1 - Sqr(IgramVertFreq[29] / AMhz));
  Xm30 := (EarthR + IgramTrueHeight[30]) * Sqrt(1 - Sqr(IgramVertFreq[30] / AMhz));
  if Xm30 >= Xm29
    then begin if Xm28 > Xm30 then Xm := Xm28 else Xm := Xm30; end
    else begin if Xm29 >= Xm28 then Xm := Xm29 else Xm := Xm28; end;

  Xm := Xm / EarthR;
  if Xm > 0.999999
    then Result[lrF2] := 0
    else Result[lrF2] := ArcCos(Xm);
end;


procedure TIonoProfile.PopulateModeInfo(var AMode: TModeInfo; AIdx: integer; AFrac: Single = 0);
begin
  if AFrac = 0
    then
      begin
      AMode.Ref.TrueHeight := IgramTrueHeight[AIdx];
      AMode.Ref.VirtHeight := IgramVirtHeight[AIdx];
      AMode.Ref.VertFreq := IgramVertFreq[AIdx];
      AMode.Ref.DevLoss := DevLoss[AIdx];
      end
    else
      begin
      AMode.Ref.TrueHeight := IgramTrueHeight[AIdx] * (1-AFrac) + IgramTrueHeight[AIdx+1] * AFrac;
      AMode.Ref.VirtHeight := IgramVirtHeight[AIdx] * (1-AFrac) + IgramVirtHeight[AIdx+1] * AFrac;
      AMode.Ref.VertFreq := IgramVertFreq[AIdx] * (1-AFrac) + IgramVertFreq[AIdx+1] * AFrac;
      AMode.Ref.DevLoss := DevLoss[AIdx] * (1-AFrac) + DevLoss[AIdx+1] * AFrac;
      end;
end;



end.

