//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is FrMaps.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit FrMaps;

interface

uses
  SysUtils, Classes, VoaTypes, SinCos, Math, Types;


type
  //types of maps that TFourierMaps can compute

  TFixedMapKind = (fmNoise1, fmNoise2, fmNoise3, fmNoise4, fmNoise5, fmNoise6,
    fmLandMass, fmYmF2);

  TNoiseIndex = fmNoise1..fmNoise5;

  TVarMapKind = (vmEsU, vmEsM, vmEsL, vmF2, vmFm3, vmEr);



  TFixedCoeff = packed record
    case boolean of
      false: ( //as stored in resource
        FAKP:   array[0..5, 0..15, 0..28] of Single;
        FAKMAP: array[      0..15, 0..28] of Single;
        HMYM:   array[      0..15, 0..28] of Single;
        FAKABP: array[0..5, 0..1] of Single;
        ABMAP:  array[0..2, 0..1] of Single;
        );
      true: ( //as used in code
        P:   array[TFixedMapKind, 0..15, 0..28] of Single;
        ABP: array[TFixedMapKind, 0..1] of Single;
        ABP_Dummy: array[0..1] of Single;
        );
      end;


  TFourierMaps = class
  private
    IKIM: array[TVarMapKind,0..9] of integer;
    SYS: array[0..5,0..15,0..8] of Single;
    F2D: array[0..5,0..5,0..15] of Single;
    PERR: array[0..5,0..3,0..8] of Single;

    ANEW: array[0..2] of Single;
    BNEW: array[0..2] of Single;
    ACHI: array[0..1] of Single;
    BCHI: array[0..1] of Single;

    {fm}XPMAP: array[0..1,0..15,0..28] of Single;

    {vm}XFM3CF: array[0..1,0..48,0..8] of Single;
    {vm}XESMCF: array[0..1,0..60,0..6] of Single;
    {vm}XESLCF: array[0..1,0..54,0..4] of Single;
    {vm}XESUCF: array[0..1,0..54,0..4] of Single;
    {vm}XERCOF: array[0..1,0..21,0..8] of Single;
    {vm}XF2COF: array[0..1,0..75,0..12] of Single;

    FMonth: TMonth;
    FSsn: Single;
    FUtc: TDateTime;

    CoefF: TFixedCoeff;
    COFION: array[TVarMapKind] of TSingleArray2D;
    CoefV: array[TVarMapKind] of TSingleArray;

    procedure LoadCoeffResource(AMonth: TMonth);
    procedure InterpolateInSsn(ASsn: Single);
    procedure InterpolateInUtc(AUtc: TDateTime);
  protected
    DUD: array[0..4,0..11,0..4] of Single;
    FAM: array[0..11,0..1,0..6] of Single;

  public
    constructor Create;
    destructor Destroy; override;
    procedure SetMonthSsnUtc(AMonth: TMonth; ASsn: Single; AUtc: TDateTime);

    function ComputeFixedMap(Kind: TFixedMapKind; Lat, EastLon: Single): Single;
    function ComputeVarMap(Kind: TVarMapKind; Lat, EastLon, Gob: Single): Single;
    function ComputeZenMax(MagDip: Single): Single;
    function ComputeFoF1(ZenAngle: Single): Single;
    function ComputeF2Deviation(Muf, Lat: Single; LocalTime: TDateTime; Above: boolean): Single;
    function ComputeExcessiveSystemLoss(MagLat: Single; LocalTime: Single; Over2500km: boolean): TDistribution;
    //noise parameters
    function ComputeFam(Idx1, Idx2: integer; U: Single): Single;
    function ComputeDud(Idx1, Idx2: integer; U: Single): Single;

    property Month: TMonth read FMonth;
    property Ssn: Single read FSsn;
    property UtcTime: TDateTime read FUtc;
  end;



implementation

{$R '..\DVoaData\VoaCoeff.RES'}

{ TFourierMaps }

//------------------------------------------------------------------------------
//                               system
//------------------------------------------------------------------------------
constructor TFourierMaps.Create;
begin
 SetMonthSsnUtc(1, 1, 1);
end;


destructor TFourierMaps.Destroy;
begin
  inherited;

end;






//------------------------------------------------------------------------------
//                            prepare coeff
//------------------------------------------------------------------------------
procedure TFourierMaps.SetMonthSsnUtc(AMonth: TMonth; ASsn: Single; AUtc: TDateTime);
begin
  if FMonth <> AMonth then
    begin
    LoadCoeffResource(AMonth);
    InterpolateInSsn(ASsn);
    InterpolateInUtc(AUtc);
    end

  else if ASsn <> FSsn then
    begin
    InterpolateInSsn(ASsn);
    InterpolateInUtc(AUtc);
    end

  else if AUtc <> FUtc then
    InterpolateInUtc(AUtc);
end;


procedure TFourierMaps.LoadCoeffResource(AMonth: TMonth);
var
  ResName: string;
begin
  FMonth := AMonth;

  ResName := Format('COEFF%.2d', [FMonth]);
  with TResourceStream.Create(HInstance, ResName, RT_RCDATA) do
    try
      ReadBuffer(IKIM, SizeOf(IKIM));
      ReadBuffer(DUD, SizeOf(DUD));
      ReadBuffer(FAM, SizeOf(FAM));
      ReadBuffer(SYS, SizeOf(SYS));
      ReadBuffer(CoefF.FAKP, SizeOf(CoefF.FAKP));
      ReadBuffer(CoefF.FAKABP, SizeOf(CoefF.FAKABP));
      ReadBuffer(XFM3CF, SizeOf(XFM3CF));
      ReadBuffer(ANEW, SizeOf(ANEW));
      ReadBuffer(BNEW, SizeOf(BNEW));
      ReadBuffer(ACHI, SizeOf(ACHI));
      ReadBuffer(BCHI, SizeOf(BCHI));
      ReadBuffer(CoefF.FAKMAP, SizeOf(CoefF.FAKMAP));
      ReadBuffer(CoefF.ABMAP, SizeOf(CoefF.ABMAP));
      ReadBuffer(F2D, SizeOf(F2D));
      ReadBuffer(PERR, SizeOf(PERR));
      ReadBuffer(XESMCF, SizeOf(XESMCF));
      ReadBuffer(XPMAP, SizeOf(XPMAP));
      ReadBuffer(XESLCF, SizeOf(XESLCF));
      ReadBuffer(XESUCF, SizeOf(XESUCF));
      ReadBuffer(XERCOF, SizeOf(XERCOF));
      Assert(Position = Size);
    finally Free; end;


  ResName := Format('FOF2CCIR%.2d', [FMonth]);
  with TResourceStream.Create(HInstance, ResName, RT_RCDATA) do
    try
      ReadBuffer(XF2COF, SizeOf(XF2COF));
      Assert(Position = Size);
    finally Free; end;
end;


procedure TFourierMaps.InterpolateInSsn(ASsn: Single);
var
  r100, r125, r150: Single;
  i, j: integer;
begin
  FSsn := ASsn;
  r100 := (Ssn -  0) / (100 -  0);
  r125 := (Ssn - 25) / (125 - 25);
  r150 := (Ssn - 10) / (150 - 10);

  //foF2
  SetLength(COFION[vmF2], Length(XF2COF[0]), Length(XF2COF[0,0]));
  for i:=0 to High(XF2COF[0]) do
    for j:=0 to High(XF2COF[0,0]) do
      COFION[vmF2][i,j] := XF2COF[0,i,j] * (1-r100) + XF2COF[1,i,j] * r100;

  //foEs
  SetLength(COFION[vmEsM], Length(XESMCF[0]), Length(XESMCF[0,0]));
  for i:=0 to High(XESMCF[0]) do
    for j:=0 to High(XESMCF[0,0]) do
      COFION[vmEsM][i,j] := XESMCF[0,i,j] * (1-r150) + XESMCF[1,i,j] * r150;

  //YmF2
  for i:=0 to High(CoefF.HMYM) do
    for j:=0 to High(CoefF.HMYM[0]) do
      CoefF.HMYM[i,j] := XPMAP[0,i,j] * (1-r125) + XPMAP[1,i,j] * r125;

  //foEs lower decile
  //Note: XESLCF is Hi and XESUCF is Lo, this is a bug in the input data
  SetLength(COFION[vmEsL], Length(XESUCF[0]), Length(XESUCF[0,0]));
  for i:=0 to High(XESUCF[0]) do
    for j:=0 to High(XESUCF[0,0]) do
      COFION[vmEsL][i,j] := XESUCF[0,i,j] * (1-r150) + XESUCF[1,i,j] * r150;

  //foEs upper decile
  SetLength(COFION[vmEsU], Length(XESLCF[0]), Length(XESLCF[0,0]));
  for i:=0 to High(XESLCF[0]) do
    for j:=0 to High(XESLCF[0,0]) do
      COFION[vmEsU][i,j] := XESLCF[0,i,j] * (1-r150) + XESLCF[1,i,j] * r150;

  //M3000
  SetLength(COFION[vmFm3], Length(XFM3CF[0]), Length(XFM3CF[0,0]));
  for i:=0 to High(XFM3CF[0]) do
    for j:=0 to High(XFM3CF[0,0]) do
      COFION[vmFm3][i,j] := XFM3CF[0,i,j] * (1-r100) + XFM3CF[1,i,j] * r100;

  //foE
  SetLength(COFION[vmEr], Length(XERCOF[0]), Length(XERCOF[0,0]));
  for i:=0 to High(XERCOF[0]) do
    for j:=0 to High(XERCOF[0,0]) do
      COFION[vmEr][i,j] := XERCOF[0,i,j] * (1-r150) + XERCOF[1,i,j] * r150;
end;


procedure TFourierMaps.InterpolateInUtc(AUtc: TDateTime);
var
  W: TSinCosArray;
  m: TVarMapKind;
  i, j: integer;
begin
  FUtc := AUtc;
  W := MakeSinCosArray((FUtc - 0.5) * TWO_PI, 7);

  for m:=Low(TVarMapKind) to High(TVarMapKind) do
    begin
    SetLength(CoefV[m], Length(COFION[m]));
    for i:=0 to High(CoefV[m]) do
      begin
      CoefV[m,i] := COFION[m,i,0];
      for j:=1 to IKIM[m,9] do
        CoefV[m,i] := CoefV[m,i] +
          W[j].Sn * COFION[m,i,2*j-1] + W[j].Cs * COFION[m,i,2*j];
      end;
    end;
end;






//------------------------------------------------------------------------------
//                          public interface
//------------------------------------------------------------------------------
function TFourierMaps.ComputeFixedMap(Kind: TFixedMapKind; Lat, EastLon: Single): Single;
var
  Lm, Ln, n, m: integer;
  Wn, Wm: TSinCosArray;
  R: Single;
begin
  Result := CoefF.ABP[Kind, 0] + CoefF.ABP[Kind,1] * (Lat + HALF_PI);

  if Kind = fmYmF2
    then begin Lm := 15; Ln := 10; end
    else begin Lm := 29; Ln := 15; end;

  Wn := MakeSinCosArray(0.5 * EastLon, Ln + 1);
  Wm := MakeSinCosArray(Lat + HALF_PI, Lm + 1);

  for m:=0 to Lm-1 do
    begin
    R := 0;
    for n:=0 to Ln-1 do
      R := R + Wn[n+1].Sn * CoefF.P[Kind][n, m];
    Result := Result + Wm[m+1].Sn * (R + CoefF.P[Kind][15, m]);
    end;
end;


//Lat is either latitude or magnetic dip, depending on Kind
//Gob is Cos(latitude)
function TFourierMaps.ComputeVarMap(Kind: TVarMapKind; Lat, EastLon, Gob: Single): Single;
var
  G: TSingleArray;
  LastI, PwrC, i: integer;
  Sx, Cx, PowerCx: Single;
begin
  SetLength(G, Length(CoefV[Kind]));
  Sx := Sin(Lat);
  Cx := Gob;

  //compute G[] = Sx^N
  G[1] := Sx;
  LastI := IKIM[Kind,0];
  for i:=2 to LastI do G[i] := G[i-1] * Sx;

  //compute G[] = Sx^N * Cx^M * Sin/Cos(M*Lon);
  PowerCx := Cx;
  for PwrC:=1 to 8 do
    begin
    i := LastI + 1;
    LastI := IKIM[Kind,PwrC];
    if i >= LastI then Break;

    G[i] := PowerCx * Cos(PwrC * EastLon);
    G[i+1] := PowerCx * Sin(PwrC * EastLon);
    Inc(i, 2);

    while i < LastI do
      begin
      G[i] := Sx * G[i-2];
      G[i+1] := Sx * G[i-1];
      Inc(i, 2);
      end;

    PowerCx := PowerCx * Cx;
    end;

  //compute Result = G[] * CoefV[]
  Result := CoefV[Kind][0]; 
  for i:=1 to LastI do Result := Result + G[i] * CoefV[Kind][i];
end;


function TFourierMaps.ComputeZenMax(MagDip: Single): Single;
begin
  Result := RinD * (ACHI[0] + BCHI[0] * Ssn + (ACHI[1] + BCHI[1] * Ssn) * Cos(MagDip));
end;


function TFourierMaps.ComputeFoF1(ZenAngle: Single): Single;
var
  CosZ: Single;
begin
  CosZ := Cos(ZenAngle);

  Result := (ANEW[0] + BNEW[0] * Ssn) +
            (ANEW[1] + BNEW[1] * Ssn) * CosZ +
            (ANEW[2] + BNEW[2] * Ssn) * Sqr(CosZ);
end;


function TFourierMaps.ComputeF2Deviation(Muf, Lat: Single; LocalTime: TDateTime; Above: boolean): Single;
var
  T, S, L: integer;
begin
  //local time
  T := Trunc(LocalTime * 6 + 0.55);
  if T >= 6 then T := 0;

  //Lat
  L := Trunc(8.5 - Abs(Lat) * 0.1/RinD);
  if L < 0 then L := 0
  else if L > 7 then L := 7;

  //above the muf
  if not Above then Inc(L, 8);

  //SSN
  if FSsn <= 50 then S := 0
  else if FSsn <= 100 then S := 1
  else S := 2;

  //south lat
  if Lat <= 0 then Inc(S, 3);


  Result := Abs((1 - F2D[T,S,L]) * Muf) * (1/NORM_DECILE);
  Result := Max(0.001, Result);
end;


function TFourierMaps.ComputeExcessiveSystemLoss(MagLat,
  LocalTime: Single; Over2500km: boolean): TDistribution;
var
  Hour, KJ, LJ, LD, NN, ND: integer;
begin
  if Over2500km then NN := 3 else NN := 0;
  if MagLat < 0 then ND := 3 else ND := 0;

  Hour := Round(LocalTime * 24);

  LJ := Floor(Hour / 3 - 0.33);
  if LJ < 0 then LJ := 7;
  if MagLat < 0 then Inc(LJ, 8);

  LD := Floor(Hour / 6 - 0.33);
  if LD < 0 then LD := 3;

  KJ := Round((Abs(MagLat * DinR) - 40) / 5);
  KJ := Max(0, Min(8, KJ));

  Result.Value.Mdn :=   Sys[NN+1,   LJ, KJ];
  Result.Value.Hi := Sys[NN+2, LJ, KJ] / NORM_DECILE;
  Result.Value.Lo := Sys[NN, LJ, KJ] / NORM_DECILE;

  Result.Error.Mdn :=   Perr[ND  , LD, KJ];
  Result.Error.Hi := Perr[ND+1, LD, KJ];
  Result.Error.Lo := Perr[ND+2, LD, KJ];
end;


function TFourierMaps.ComputeFam(Idx1, Idx2: integer; U: Single): Single;
var
  i: integer;
begin
  Result := FAM[Idx1,Idx2,0];
  for i:=1 to High(FAM[Idx1,Idx2]) do Result := U * Result + FAM[Idx1,Idx2,i];
end;


function TFourierMaps.ComputeDud(Idx1, Idx2: integer; U: Single): Single;
var
  i: integer;
begin
  Result := DUD[Idx1,Idx2,0];
  for i:=1 to High(DUD[Idx1,Idx2]) do Result := U * Result + DUD[Idx1,Idx2,i];
end;



end.

