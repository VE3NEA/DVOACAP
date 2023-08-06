//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is VoaCapEng.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit VoaCapEng;

interface

uses
  SysUtils, VoaTypes, PathGeom, MagFld, Sun, FrMaps, Math, LayrParm,
  Classes, IonoProf, MufCalc, Reflx, AntGain, NoiseMdl;


type
  TVoacapEngine = class
  private
    FMag: TGeoMagneticField;
    FMap: TFourierMaps;
    FNoise: TNoiseModel;
    FRefl: TReflectrix;

    //these are computed in SIGDIS and used in performance calcs
    FAbsorptionIndex: Single;
    Adj_DE_Loss: Single;
    Adj_CCIR252_A, Adj_CCIR252_B: Single;
    Adj_Signal_10, Adj_Signal_90: Single;
    Adj_Auroral: Single;

    procedure ComputeControlPoints;
    procedure ComputeGeoParams(var Pnt: TControlPoint);
    procedure CreateIonoProfiles;
    procedure ClearIonoProfiles;
    procedure AdjustSignalDistributionTables(AProf: TIonoProfile);
    procedure ComputeSignal(var AMode: TModeInfo);
    function GetAngleCount: integer;
    procedure StoreFoundModes(AModes: TModeInfoArray);
    function ComputeGroundReflectionLoss(Idx: integer; AElev, AFreq: Single): Single;
    function EvaluateShortModel(FreqIdx: integer): TPrediction;
    function CombineShortAndLong(const AShort, ALong: TPrediction): TPrediction;
    function EvaluateLongModel(FreqIdx: integer): TPrediction;
    function DoEvaluateLongModel(TxRefl, RxRefl: TReflectrix): TPrediction;
    function AnalyzeReliability: TPrediction;
    procedure CalcSumOfModes(AModes: TModeInfoArray; var AResult: TPrediction);
    procedure CalcReliability(var ASig: TSignalInfo; AClamp: boolean = false);
    function FindBestMode: PModeInfo;
    function ValuesToLine(APointer: Pointer; ADec: integer; AScale: Single = 1): string;
    function CalcMultiPathProb: Single;
    function CalcServiceProb: Single;
    function ListModes(ARefl: TReflectrix): TModeInfoArray;
    function SelectOptimumAngle(AModes: TModeInfoArray; AAnts: TAntennaFarm): PModeInfo;
    procedure ComputeLosses(var AMode: TModeInfo; AProf: TIonoProfile;
      AFreq: Single);
    function CalcMModeDistance(AIonoDist, AFreq: Single): Single;
    function GetAbsPerKm(AFreq, AElevation, AVirtHeight, ADistance, AAbsIndex: Single): Single;
    function CalcDeciles(AFreq: Single; ALayer: TIonoLayer): TTripleValue;
    function CalcRequiredPower(const ASig: TSignalInfo): Single;
  protected
    //temp data
    Freq: Single;
    CurrProf: TIonoProfile;
    SunLoc: TGeoPoint;
    CtrlPts: array of TControlPoint;
    Profiles: TIonoProfiles;
    Modes: TModeInfoArray;
    AvgLoss: TDistribution;
    BestMode: PModeInfo;
  public
    FPath: TPathGeometry;
    FMufCalc: TCircuitMuf;

    //input parameters
    TxAnts, RxAnts: TAntennaFarm;
    Pm: TVoaParams;

    //input arguments
    RxLoc: TGeoPoint;
    UtcTime: TDateTime;
    Freqs: TSingleArray;

    //results
    Results: TPredictions;

    constructor Create;
    destructor Destroy; override;
    procedure Predict;
    function GetModeName(const APrediction: TPrediction): string;
    function ResultToText: string;
  end;



implementation


{ TVoacapEngine }

constructor TVoacapEngine.Create;
begin
  //defaults
  Pm := DefaultVoaParams;
  TxAnts := TAntennaFarm.Create;
  RxAnts := TAntennaFarm.Create;
  FPath := TPathGeometry.Create;
  FMag := TGeoMagneticField.Create;
  FMap := TFourierMaps.Create;

  FNoise := TNoiseModel.Create;
  FNoise.FMap := FMap;

  FMufCalc := TCircuitMuf.Create;
  FMufCalc.FPath := FPath;
  FMufCalc.FMap := FMap;
  FMufCalc.MinAngle := Pm.MinAngle;
end;


destructor TVoacapEngine.Destroy;
begin
  FMap.Free;
  FMag.Free;
  FPath.Free;
  FMufCalc.Free;
  TxAnts.Free;
  RxAnts.Free;
  FNoise.Free;
  ClearIonoProfiles;
  inherited;
end;


procedure TVoacapEngine.Predict;
var
  i, f: integer;
begin
  TxAnts.CurrentAntenna.TxPower_dBW := ToDb(Pm.TxPower);
  FMufCalc.MinAngle := Pm.MinAngle;

  SetLength(Results, Length(Freqs));

  //compute maps for the given month, ssn and utc
  FMap.SetMonthSsnUtc(Pm.Month, Pm.Ssn, UtcTime);

  //path geometry
  FPath.LongPath := Pm.LongPath;
  FPath.SetTxRx(Pm.TxLoc, RxLoc);
  //accept adjustments made in FPath
  RxLoc := FPath.Rx;
  Pm.TxLoc := FPath.Tx;
  //rotate antennae
  TxAnts.CurrentAntenna.Azimuth := FPath.AzimTR;
  RxAnts.CurrentAntenna.Azimuth := FPath.AzimRT;

  //control points
  ComputeControlPoints;

  //geophysical parameters
  for i:=0 to High(CtrlPts) do ComputeGeoParams(CtrlPts[i]);

  //ionospheric parameters
  for i:=0 to High(CtrlPts) do ComputeIonoParams(CtrlPts[i], FMap);

  //prepare noise tables
  FNoise.ManMadeNoiseAt3MHz := Pm.ManMadeNoiseAt3MHz;
  FNoise.ComputeNoiseAt1Mhz(RxLoc, ComputeLocalTime(UtcTime, RxLoc.Lon));

  //oblique profiles of the ionosphere
  CreateIonoProfiles;

  //circuit muf
  FMufCalc.ComputeCircuitMuf(Profiles);
  //if zero in the last element, replace with MUF
  if Freqs[High(Freqs)] = 0 then Freqs[High(Freqs)] := FMufCalc.Muf;

  //selected profile for short model
  CurrProf := SelectProfile(Profiles);

  //compute profile fo short model
  CurrProf.ComputeIonogram;
  CurrProf.ComputeObliqueFreqs(GetAngleCount);
  CurrProf.ComputeDeviativeLoss(FMufCalc.MufInfo);

  //{!} should this be split into CurrProf-independent
  //part and the small piece that depends on CurrProf?
  AdjustSignalDistributionTables(CurrProf);

  //compute profiles for long model
  if FPath.Dist >= Rad_7000Km then
    begin
    Profiles[0].ComputeIonogram;
    Profiles[0].ComputeObliqueFreqs(GetAngleCount);
    Profiles[0].ComputeDeviativeLoss(FMufCalc.MufInfo);

    Profiles[High(Profiles)].ComputeIonogram;
    Profiles[High(Profiles)].ComputeObliqueFreqs(GetAngleCount);
    Profiles[High(Profiles)].ComputeDeviativeLoss(FMufCalc.MufInfo);
    end;

  //compute prediction for each frequency in Freqs[]
  for f:=0 to High(Freqs) do
    begin
    Freq := Freqs[f];
    TxAnts.SelectAntenna(Freq);
    RxAnts.SelectAntenna(Freq);

    FNoise.ComputeDistribution(Freq, Profiles[High(Profiles)].F2.Fo);

    FRefl := TReflectrix.Create(Pm.MinAngle, Freq, CurrProf);
    try
      Results[f] := EvaluateShortModel(f);
      if FPath.Dist >= Rad_7000Km then
        Results[f] := CombineShortAndLong(Results[f], EvaluateLongModel(f));
    finally FRefl.Free; end;
    end;
end;


procedure TVoacapEngine.ComputeControlPoints;
begin
  CtrlPts := nil;

  if FPath.Dist <= Rad_2000Km_01 then
    begin
    SetLength(CtrlPts, 1);
    CtrlPts[0].Loc := FPath.GetPointAtDist(0.5 * FPath.Dist);
    end

  else if FPath.Dist <= Rad_4000Km then
    begin
    SetLength(CtrlPts, 3);
    CtrlPts[0].Loc := FPath.GetPointAtDist(Rad_1000Km);
    CtrlPts[1].Loc := FPath.GetPointAtDist(0.5 * FPath.Dist);
    CtrlPts[2].Loc := FPath.GetPointAtDist(FPath.Dist - Rad_1000Km);
    end

  else
    begin
    SetLength(CtrlPts, 5);
    CtrlPts[0].Loc := FPath.GetPointAtDist(Rad_1000Km);
    CtrlPts[1].Loc := FPath.GetPointAtDist(Rad_2000Km);
    CtrlPts[2].Loc := FPath.GetPointAtDist(0.5 * FPath.Dist);
    CtrlPts[3].Loc := FPath.GetPointAtDist(FPath.Dist - Rad_2000Km);
    CtrlPts[4].Loc := FPath.GetPointAtDist(FPath.Dist - Rad_1000Km);
    end;
end;


procedure TVoacapEngine.ComputeGeoParams(var Pnt: TControlPoint);
begin
  //EastLon (0..2Pi)
  if Pnt.Loc.Lon >= 0
    then Pnt.EastLon := Pnt.Loc.Lon
    else Pnt.EastLon := TWO_PI + Pnt.Loc.Lon;

  //magnetic latitude, dip, and gyrofreq
  FMag.Compute(Pnt);

  //ground constants
  if FMap.ComputeFixedMap(fmLandmass, Pnt.Loc.Lat, Pnt.EastLon) >= 0
    then begin Pnt.GndSig := 0.001; Pnt.GndEps := 4; end   //land
    else begin Pnt.GndSig := 5; Pnt.GndEps := 80; end;     //sea

  //zenith angle of the Sun
  Pnt.ZenAngle := ComputeZenithAngle(Pnt.Loc, UtcTime, Pm.Month);

  //local time
  Pnt.LocalTime := ComputeLocalTime(UtcTime, Pnt.Loc.Lon);
end;


procedure TVoacapEngine.ClearIonoProfiles;
var
  i: integer;
begin
  for i:=0 to High(Profiles) do Profiles[i].Free;
  Profiles := nil;
end;


procedure TVoacapEngine.CreateIonoProfiles;
var
  i: integer;
begin
  //create profile objects
  ClearIonoProfiles;
  SetLength(Profiles, 1 + (Length(CtrlPts) shr 1));
  for i:=0 to High(Profiles) do Profiles[i] := TIonoProfile.Create;


  //PLACES THE PARAMETERS INTO PROPER SLOTS
  case Length(Profiles) of
    1:
      begin
      Profiles[0].E := CtrlPts[0].E;
      Profiles[0].F1 := CtrlPts[0].F1;
      Profiles[0].F2 := CtrlPts[0].F2;

      Profiles[0].Lat := CtrlPts[0].Loc.Lat;
      Profiles[0].MagLat := CtrlPts[0].MagLat;
      Profiles[0].LocalTimeE := CtrlPts[0].LocalTime;
      Profiles[0].LocalTimeF2 := CtrlPts[0].LocalTime;
      Profiles[0].GyroFreq := CtrlPts[0].GyroFreq;
      end;
    2:
      begin
      Profiles[0].E := CtrlPts[0].E;
      Profiles[0].F1 := CtrlPts[0].F1;
      Profiles[0].F2 := CtrlPts[1].F2;

      Profiles[1].E := CtrlPts[2].E;
      Profiles[1].F1 := CtrlPts[2].F1;
      Profiles[1].F2 := CtrlPts[1].F2;

      Profiles[0].Lat := CtrlPts[1].Loc.Lat;
      Profiles[0].MagLat := CtrlPts[0].MagLat;
      Profiles[0].LocalTimeE := CtrlPts[0].LocalTime;
      Profiles[0].LocalTimeF2 := CtrlPts[1].LocalTime;
      Profiles[0].GyroFreq := CtrlPts[0].GyroFreq;

      Profiles[1].Lat := CtrlPts[1].Loc.Lat;
      Profiles[1].MagLat := CtrlPts[2].MagLat;
      Profiles[1].LocalTimeE := CtrlPts[2].LocalTime;
      Profiles[1].LocalTimeF2 := CtrlPts[1].LocalTime;
      Profiles[1].GyroFreq := CtrlPts[2].GyroFreq;
      end;
    3:
      begin
      Profiles[0].E := CtrlPts[0].E;
      Profiles[0].F1 := CtrlPts[0].F1;
      Profiles[0].F2 := CtrlPts[1].F2;

      Profiles[1].E := CtrlPts[2].E;
      Profiles[1].F1 := CtrlPts[2].F1;
      Profiles[1].F2 := CtrlPts[2].F2;

      Profiles[2].E := CtrlPts[4].E;
      Profiles[2].F1 := CtrlPts[4].F1;
      Profiles[2].F2 := CtrlPts[3].F2;

      Profiles[0].Lat := CtrlPts[1].Loc.Lat;
      Profiles[0].MagLat := CtrlPts[0].MagLat;
      Profiles[0].LocalTimeE := CtrlPts[0].LocalTime;
      Profiles[0].LocalTimeF2 := CtrlPts[1].LocalTime;
      Profiles[0].GyroFreq := CtrlPts[0].GyroFreq;

      Profiles[1].Lat := CtrlPts[2].Loc.Lat;
      Profiles[1].MagLat := CtrlPts[2].MagLat;
      Profiles[1].LocalTimeE := CtrlPts[2].LocalTime;
      Profiles[1].LocalTimeF2 := CtrlPts[2].LocalTime;
      Profiles[1].GyroFreq := CtrlPts[2].GyroFreq;

      Profiles[2].Lat := CtrlPts[3].Loc.Lat;
      Profiles[2].MagLat := CtrlPts[4].MagLat;
      Profiles[2].LocalTimeE := CtrlPts[4].LocalTime;
      Profiles[2].LocalTimeF2 := CtrlPts[3].LocalTime;
      Profiles[2].GyroFreq := CtrlPts[4].GyroFreq;
      end;
    end;


  //CHECKS THE CONSISTeNCY OF THE IONOSPHERIC PARAMETERS
  for i:=0 to High(Profiles) do
    with Profiles[i] do
      begin
      if F1.Fo > 0 then
        if F1.Fo <= (E.Fo + 0.2) then F1.Fo := 0
        else if F2.Fo <= (F1.Fo + 0.2) then F1.Fo := 0
        else F1.Hm := Min(F1.Hm, F2.Hm);

      F2.Ym := Min(F2.Ym, F2.Hm - E.Hm - 2);
      end;
end;


procedure TVoacapEngine.StoreFoundModes(AModes: TModeInfoArray);
var
  i: integer;
begin
  SetLength(Modes, Length(Modes) + Length(AModes));
  for i:=0 to High(AModes) do Modes[High(Modes)-i] := AModes[High(AModes)-i];
end;


function TVoacapEngine.GetAngleCount: integer;
const
  NANGX: array [0..7] of integer = (40, 34, 29, 24, 19, 14, 12, 9);
var
  i: integer;
begin
  Result := Trunc(FPath.Dist / Rad_2000Km);
  Result := Min(7, Result);
  Result := NANGX[Result];

  if (Pm.MinAngle > 0) and (Angles[Result] < (Pm.MinAngle + 10*RinD)) then
    for i:=Low(Angles) to High(Angles) do
      if Angles[i] >= (Pm.MinAngle + 8.5*RinD)
        then begin Result := i; Break; end;
end;


//SIGDIS/SYSSY
procedure TVoacapEngine.AdjustSignalDistributionTables(AProf: TIonoProfile);
var
  p: integer;
  Avg_FoE: Single;
  Avg_MagLat: Single;
  FTAB, F2LSM, PF2, ESLSM, PES: Single;
begin
  //average over all profiles
  FAbsorptionIndex := 0;
  Avg_FoE := 0;
  Avg_MagLat := 0;
  FillChar(AvgLoss, SizeOf(AvgLoss), 0);
  for p:=0 to High(Profiles) do
   with Profiles[p] do
     begin
     Avg_FoE := Avg_FoE + E.Fo;
     Avg_MagLat := Avg_MagLat + Abs(MagLat);
     AbsorptionIndex := Max(0.1, - 0.04 + Exp(-2.937 + 0.8445 * E.Fo));
     FAbsorptionIndex := FAbsorptionIndex + AbsorptionIndex;
     ExcessiveSystemLoss := FMap.ComputeExcessiveSystemLoss(MagLat, LocalTimeE, FPath.Dist > Rad_2500Km);
     AvgLoss.Value.Mdn := AvgLoss.Value.Mdn + ExcessiveSystemLoss.Value.Mdn;
     AvgLoss.Value.Lo := AvgLoss.Value.Lo + ExcessiveSystemLoss.Value.Lo;
     AvgLoss.Value.Hi := AvgLoss.Value.Hi + ExcessiveSystemLoss.Value.Hi;
     AvgLoss.Error.Mdn := AvgLoss.Error.Mdn + ExcessiveSystemLoss.Error.Mdn;
     AvgLoss.Error.Lo := AvgLoss.Error.Hi + ExcessiveSystemLoss.Error.Lo;
     AvgLoss.Error.Hi := AvgLoss.Error.Hi + ExcessiveSystemLoss.Error.Hi;
     end;
  Avg_FoE := Avg_FoE / Length(Profiles);
  Avg_MagLat := Avg_MagLat / Length(Profiles);
  FAbsorptionIndex := FAbsorptionIndex / Length(Profiles);
  AvgLoss.Value.Mdn := AvgLoss.Value.Mdn / Length(Profiles);
  AvgLoss.Value.Lo := AvgLoss.Value.Lo / Length(Profiles);
  AvgLoss.Value.Hi := AvgLoss.Value.Hi/ Length(Profiles);
  AvgLoss.Error.Mdn := AvgLoss.Error.Mdn / Length(Profiles);
  AvgLoss.Error.Lo := AvgLoss.Error.Lo / Length(Profiles);
  AvgLoss.Error.Hi := AvgLoss.Error.Hi / Length(Profiles);


  //D - E REGION LOSS ADJUSTMENT FACTOR
  {!}//this is the only statement in the procedure that depends on AProf
  //the rest should be moved out of the loop
  Adj_DE_Loss := InterpolateTable(90{km}, AProf.IgramTrueHeight, AProf.IgramVertFreq) / AProf.E.Fo;

  //ADJUSTMENT TO CCIR 252 (HAYDON,LUCAS) LOSS EQUATION FOR E MODES
  if Avg_FoE > 2 then
    begin
    Adj_CCIR252_A := 1.359;
    Adj_CCIR252_B := 8.617;
    end
  else if Avg_FoE > 0.5 then
    begin
    Adj_CCIR252_A := 1.359 *(Avg_FoE - 0.5)/1.5;
    Adj_CCIR252_B := 8.617 *(Avg_FoE - 0.5)/1.5;
    end
  else
    begin
    Adj_CCIR252_A := 0;
    Adj_CCIR252_B := 0;
    end;

  //USE FOT, F2 LAYER
  with FMufCalc.MufInfo[lrF2] do
    if Avg_MagLat <= (40 * RinD)
      then FTAB := Fot
    else if Avg_MagLat <= (50 * RinD)
      then FTAB := Fot - (Avg_MagLat - 40*RinD) * (Fot - 10) / (10 * RinD)
    else
      FTAB := 10; //10 MHZ (NEAR POLES)

  {Es}//ES CONTRIBUTION TO TABLE( OBSCURTION LOSS).
  ESLSM := 0;

  //F2 OVER-THE-MUF CONTRIBUTION
  with FMufCalc.MufInfo[lrF2] do
    PF2 := Max(0.1, CalcMufProb(FTAB, Muf, Muf, SigLo, SigHi));
  F2LSM := -ToDb(PF2);

  //RESIDUAL (AURORAL) LOSS ADJUSTMENT TO MEDIAN SIGNAL LEVEL
  Adj_Auroral := Max(0, AvgLoss.Value.Mdn - ESLSM - F2LSM);

  //UPPER DECILE SIGNAL LEVEL ADJUSTMENT TO MEDIAN
  {Es}PES := 0;
  with FMufCalc.MufInfo[lrF2] do
    PF2 := Max(0.1, CalcMufProb(FTAB, Hpf, Hpf, SigLo, SigHi));
  Adj_Signal_90 := Max(0.5, NORM_DECILE * AvgLoss.Value.Lo - ToDb(1-PES) - ESLSM - ToDb(PF2) - F2LSM);

  //LOWER DECILE
  {Es}PES := 0;
  with FMufCalc.MufInfo[lrF2] do
    PF2 := Max(0.1, CalcMufProb(FTAB, Fot, Fot, SigLo, SigHi));
  Adj_Signal_10 := Max(1, NORM_DECILE * AvgLoss.Value.Hi + ToDb(1-PES) + ESLSM + ToDb(PF2) + F2LSM);
end;


function TVoacapEngine.ComputeGroundReflectionLoss(Idx: integer;
  AElev, AFreq: Single): Single;
var
  ERT, T, U, Rho, a, R, Q, S, X, V, ASXV: Single;
  CH, CV: Single;
begin
 if AElev < 1e-8 then begin Result := 6; Exit; end;

  //THE EQUATIONS FOR THE FRESNEL REFLECTION COEFFICIENTS ARE IN
  //VOLUME I OF THE OT REPORT ON THIS ANALYSIS PROGRAM

  X := 18000 * CtrlPts[Idx].GndSig / AFreq;
  T := Cos(AElev);
  Q := Sin(AElev);
  R := Sqr(Q);
  S := Sqr(R);
  ERT := CtrlPts[Idx].GndEps - Sqr(T);
  Rho := Sqrt(Sqr(ERT) + Sqr(X));
  a := -ArcTan(X / ERT);
  U := Sqr(CtrlPts[Idx].GndEps) + Sqr(X);
  V := SQRT(U);
  ASXV := ArcSin(X / V);

  CV := Sqrt(Sqr(Rho) + Sqr(U) * S - 2 * Rho * U * R * Cos(a + 2 * ASXV)) /
    (Rho + U * R + 2 * Sqrt(Rho) * V * Q * Cos(0.5 * a + ASXV));

  CH := Sqrt(Sqr(Rho) + S - 2 * Rho * R * Cos(a)) /
    (Rho + R + 2 * Sqrt(Rho) * Q * Cos(0.5 * a));

 Result := Abs(4.3429 * Ln(0.5 * (Sqr(CH) + Sqr(CV))));
end;


//REGMOD
procedure TVoacapEngine.ComputeSignal(var AMode: TModeInfo);
var
  AC, BC: Single;
  PathLen: Single;
  HopCnt, HopCnt2: integer;
  NSqr: Single; //collision frequency
  HEff: Single; //effective height
  Obscur10, Obscur90: Single; //obscuration deciles
  ADX: Single;
  ModeMufElev, ModeMuf: Single;

  XMUF, XLS, XlsLo, XlsHi, CPR: Single;
  Sec: Single; //secance of incidence angle
  M: PMufInfo;
  p: integer;
begin
  M := @FMufCalc.MufInfo[AMode.Layer];

  //this is for SP model. For LP, Prof[].AbsorptionIndex is used instead
  AC := 677.2 * FAbsorptionIndex;

  BC := Power(Freq + CurrProf.GyroFreq, 1.98);
  HopCnt := Trunc(FPath.Dist / AMode.HopDist + 0.01);
  HopCnt2 := Min(2, HopCnt);
  PathLen := HopCnt * HopLength3D(AMode.Ref.Elevation, AMode.HopDist, AMode.Ref.VirtHeight);


  //TIME DELAY
  AMode.Sig.Delay_ms := PathLen / VofL;

  //FREE SPACE LOSS LOSS RELATIVE TO AN ISOTROPIC RADIATOR
  AMode.FreeSpaceLoss := 32.45 + 2 * ToDb(PathLen * Freq);

  {!}//same code as in ComputeLosses(), call that method instead?


  //ABSORPTION LOSS BUT REMOVE E LAYER BENDING EFFECT
  if AMode.Ref.VertFreq <= CurrProf.E.Fo
    then
      //D-E MODE
      begin
      if AMode.Ref.TrueHeight >= HTLOSS
        then NSqr := 10.2
        else NSqr := XNUZ * Exp(-2 * (1 + 3 * (AMode.Ref.TrueHeight - 70) / 18) / HNU);
      HEff := Min(100, AMode.Ref.TrueHeight);
      ADX := Adj_CCIR252_A + Adj_CCIR252_B * Ln(Max(AMode.Ref.VertFreq / CurrProf.E.Fo , Adj_DE_Loss));
      end
    else
      //F LAYER MODES
      begin
      NSqr := 10.2;
      HEff := 100;
      ADX := 0;
      end;
  AMode.AbsorptionLoss := AC / (BC + NSqr) / CosOfIncidence(AMode.Ref.Elevation, HEff);

  //ground loss
  AMode.GroundLoss := 0;
  for p:=0 to High(CtrlPts) do
    AMode.GroundLoss := AMode.GroundLoss + ComputeGroundReflectionLoss(p, AMode.Ref.Elevation, Freq);
  AMode.GroundLoss :=  AMode.GroundLoss / Length(CtrlPts);

  //DEVIATION TERM FOR HIGH ANGLE RAYS, PLUS E LAYER BENDING EFFECT
  AMode.DeviationTerm := AMode.Ref.DevLoss /(BC + NSqr) *
    (Power(AMode.Ref.VertFreq + CurrProf.GyroFreq, 1.98) + NSqr) /
    CosOfIncidence(AMode.Ref.Elevation, AMode.Ref.VirtHeight) +
    ADX;

  //{Es}
  AMode.Obscuration := 0;
  Obscur10 := 0;
  Obscur90 := 0;

  //ANTENNA GAINS
  AMode.Sig.TxGain_dB := TxAnts.CurrentAntenna.GetGainDb(AMode.Ref.Elevation);
  AMode.Sig.RxGain_dB := RxAnts.CurrentAntenna.GetGainDb(AMode.Ref.Elevation);

  //TRANSMISSION LOSS
  AMode.Sig.TotalLoss_dB := AMode.FreeSpaceLoss +
    HopCnt * (AMode.AbsorptionLoss + AMode.DeviationTerm) +
    AMode.GroundLoss * (HopCnt - 1) +
    HopCnt2 * AMode.Obscuration +
    Adj_Auroral - AMode.Sig.RxGain_dB - AMode.Sig.TxGain_dB;


  //MUF FOR THIS HOP DISTANCE
  ModeMufElev := CalcElevationAngle(AMode.HopDist, M^.Ref.VirtHeight);
  ModeMuf := M^.Ref.VertFreq / CosOfIncidence(ModeMufElev, M^.Ref.TrueHeight);

  //THIS IS MUFDAY
  AMode.Sig.MufDay := CalcMufProb(Freq, ModeMuf, M^.Muf, M^.SigLo, M^.SigHi);

  //ADD MORE LOSS WHEN MUFDAY GETS VERY LOW
  if AMode.Sig.MufDay < 1e-4 then
    AMode.Sig.TotalLoss_dB := AMode.Sig.TotalLoss_dB - Max(-24, 8 * Log10(AMode.Sig.MufDay) + 32);

  //some more losses
  Sec := 1 / CosOfIncidence(AMode.Ref.Elevation, AMode.Ref.TrueHeight);
  XMUF := M^.Ref.VertFreq * Sec;
  XLS := CalcMufProb(Freq, XMUF, M^.Muf, M^.SigLo, M^.SigHi);
  XLS := -ToDb(Max(1e-6, XLS)) * Sec;
  AMode.Sig.TotalLoss_dB := AMode.Sig.TotalLoss_dB + HopCnt * XLS;

  CPR := M^.Ref.VertFreq / M^.Muf;
  XlsLo := CalcMufProb(Freq, M^.Fot * Sec * CPR, M^.Fot, M^.SigLo, M^.SigHi);
  XlsLo := -ToDb(Max(1e-6, XlsLo)) * Sec;

  XlsHi := CalcMufProb(Freq, M^.Hpf * Sec * CPR, M^.Hpf, M^.SigLo, M^.SigHi);
  XlsHi := -ToDb(Max(1e-6, XlsHi)) * Sec;

  //DECILES OF SIGNAL LEVEL
  AMode.Sig.Power10 := Min(25, Adj_Signal_10 + HopCnt2 *(Obscur10 - AMode.Obscuration) + HopCnt * (XlsLo - XLS));
  AMode.Sig.Power90 := Min(25, Adj_Signal_90 + HopCnt2 *(AMode.Obscuration - Obscur90) + HopCnt * (XLS  - XlsHi));

  //FLDST(IM) IS FIELD STRENGTH
  AMode.Sig.Field_dBuV := 107.2 + TxAnts.CurrentAntenna.TxPower_dBW + 2 * ToDb(Freq) - AMode.Sig.TotalLoss_dB - AMode.Sig.RxGain_dB;
  //SIGPOW(IM) IS SIGNAL
  AMode.Sig.Power_dBW := TxAnts.CurrentAntenna.TxPower_dBW - AMode.Sig.TotalLoss_dB;
  //SN(IM) IS SIGNAL TO NOISE
  AMode.Sig.Snr_dB := AMode.Sig.Power_dBW - FNoise.Combined;
end;


function TVoacapEngine.EvaluateShortModel(FreqIdx: integer): TPrediction;
var
  MinHops, MaxHops, HopsB, HopsE, HopCnt: integer;
  m: integer;
begin
  Modes := nil;

  //min hop count
  MinHops := Min(FMufCalc.MufInfo[lrE].HopCount, FMufCalc.MufInfo[lrF2].HopCount);
  if CurrProf.F1.Fo > 0 then MinHops := Min(MinHops, FMufCalc.MufInfo[lrF1].HopCount);

  //decide which hop counts will be used
  if FRefl.MaxDistance <= 0
    then
      begin
      //ONLY ONE OVER THE MUF MODE
      HopsB := MinHops;
      HopsE := MinHops;
      end
    else
      begin
      //UP TO THREE HOPS
      HopsB := Trunc(FPath.Dist / FRefl.MaxDistance) + 1;
      HopsB := Max(MinHops, HopsB);
      MaxHops := Trunc(FPath.Dist / FRefl.SkipDistance);
      MaxHops := Max(HopsB, MaxHops);
      HopsE := Min(MaxHops, HopsB + 2);
      if HopsB > MinHops then HopsB := Max(MinHops, HopsE - 2);
      end;

  //find all rays for all hop counts
  for HopCnt:=HopsB to HopsE do
    begin
    FRefl.FindModes(FPath.Dist / HopCnt, HopCnt);
    FRefl.AddOverTheMufAndVertModes(FPath.Dist / HopCnt, HopCnt, FMufCalc);
    StoreFoundModes(FRefl.Modes);
    end;

  //signal strength, snr, etc.
  for m:=0 to High(Modes) do ComputeSignal(Modes[m]);

  //select best ray, compute its params and total power
  Result := AnalyzeReliability;
  //probability of required snr
  Result.ServiceProb := CalcServiceProb;
  //multipath
  Result.MultiPathProb := CalcMultiPathProb;

  //short model, path is symmetric
  Result.Method := mdShort;
  Result.ModeR := Result.ModeT;
  Result.RxElevation := Result.TxElevation;
end;


function TVoacapEngine.EvaluateLongModel(FreqIdx: integer): TPrediction;
var
  TxRefl, RxRefl: TReflectrix;
begin
  //reuse existing reflectrces if possible
  if Profiles[0] = CurrProf then TxRefl := FRefl else TxRefl := nil;
  if Profiles[High(Profiles)] = CurrProf then RxRefl := FRefl else RxRefl := nil;

  //create reflectrices if cannot reuse
  if TxRefl = nil then TxRefl := TReflectrix.Create(Pm.MinAngle, Freq, Profiles[0]);
  try
    if RxRefl = nil then RxRefl := TReflectrix.Create(Pm.MinAngle, Freq, Profiles[High(Profiles)]);
    try
      Result := DoEvaluateLongModel(TxRefl, RxRefl);
    //destroy reflectrices if created
    finally
      if RxRefl <> FRefl then RxRefl.Free;
    end;
  finally
    if TxRefl <> FRefl then TxRefl.Free;
  end;
end;


function TVoacapEngine.CombineShortAndLong(const AShort, ALong: TPrediction): TPrediction;
var
  ShortPwr10, LongPwr10: Single;
  r, Pwr: Single;
begin
  //lower deciles of predicted power
  ShortPwr10 := AShort.Sig.Power_dBW - Abs(AShort.Sig.Power10);
  LongPwr10 := ALong.Sig.Power_dBW - Abs(ALong.Sig.Power10);

  if FPath.Dist < Rad_7000Km then Result := AShort
  else if ShortPwr10 > LongPwr10 then Result := AShort
  else if FPath.Dist >= Rad_10000Km then Result := ALong
  else
    begin
    //LONG PATH/SHORT PATH SMOOTHING FROM VOA MEMO  15 JAN 1991
    Result := ALong;
    Result.Method := mdSmooth;

    r := (FPath.Dist - Rad_7000Km) / (Rad_10000Km - Rad_7000Km);
    Pwr := ShortPwr10 + ToDb(r * (FromDb(LongPwr10 - ShortPwr10) - 1) + 1);

    Result.Sig.Power_dBW := Pwr + ALong.Sig.Power10; //{?}why along
    Result.Sig.TotalLoss_dB := TxAnts.CurrentAntenna.TxPower_dBW - Result.Sig.Power_dBW;
    Result.Sig.Snr_dB := Result.Sig.Power_dBW - FNoise.Combined;
    Result.Sig.Field_dBuV := 107.2 + TxAnts.CurrentAntenna.TxPower_dBW + 2 * ToDb(Freq) - Result.Sig.TotalLoss_dB - Result.Sig.RxGain_dB;

    //uses Sig.Snr_dB, Power10, Power90
    CalcReliability(Result.Sig, true);

    //uses Sig.Snr_dB, Sig.Snr10, Sig.Snr90
    Result.RequiredPower := CalcRequiredPower(Result.Sig);
    Result.SnrXX := Pm.RequiredSnr - Result.RequiredPower;

    //uses Modes[m].Ref.VirtHeight, Sig.Power10, Sig.Power90, Sig.Snr_dB
    SetLength(Modes, 1);
    Modes[0].Ref.VirtHeight := Result.VirtHeight;
    Modes[0].Sig := Result.Sig;
    Result.ServiceProb := CalcServiceProb;
    end;
end;


//compute ASig.Snr10, ASig.Snr90, ASig.Reliability
procedure TVoacapEngine.CalcReliability(var ASig: TSignalInfo; AClamp: boolean = false);
var
  Z: Single;
begin
  //LOWER DISTRIBUTION VARIABLE FOR THE SNR; VALUES OF SNR
  //AT THIS END OF THE SNR DISTRIBUTION REFLECT HIGH NOISE & LOW SIGNAL.
  ASig.Snr10 := Sqrt(Sqr(FNoise.CombinedNoise.Value.Hi) + Sqr(ASig.Power10));
  ASig.Snr90 := Sqrt(Sqr(FNoise.CombinedNoise.Value.Lo) + Sqr(ASig.Power90));

  if AClamp then
    begin
    ASig.Snr10 := Max(0.2, ASig.Snr10);
    ASig.Snr90 := Min(30, ASig.Snr90);
    end;

  Z := Pm.RequiredSnr - ASig.Snr_dB;
  if Z <= 0
    then Z := Z / (ASig.Snr10 / NORM_DECILE)
    else Z := Z / (ASig.Snr90 / NORM_DECILE);

  ASig.Reliability := 1 - CumulativeNormal(Z);
end;


function TVoacapEngine.FindBestMode: PModeInfo;
var
  m: integer;
begin
  Result := @Modes[0];

  for m:=1 to High(Modes) do
    //MAKE SELECTION BASED ON RELIABILITY FIRST BUT IF CLOSE SELECT ON
    //LOWER NUMBER OF HOPS (IF THE NUMBER OF HOPS ARE EQUAL SELECT BY
    //MEDIAN SNR)
    if Modes[m].Sig.Reliability > (Result^.Sig.Reliability + 0.05) then Result := @Modes[m]
    else if Modes[m].Sig.Reliability < (Result^.Sig.Reliability - 0.05) then Continue
    else if Modes[m].HopCnt < Result^.HopCnt then Result := @Modes[m]
    else if Modes[m].HopCnt > Result^.HopCnt then Continue
    else if Modes[m].Sig.Snr_dB > Result^.Sig.Snr_dB then Result := @Modes[m];
end;


function TVoacapEngine.AnalyzeReliability: TPrediction;
var
  m: integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  if Modes = nil then Exit;

  //RELIABILITY CALCULATION FOR EACH MODE
  for m:=0 to High(Modes) do
    if Modes[m].Ref.VirtHeight <= 70
      then Modes[m].Sig.Reliability := 0.001 //{!} Power10/90 is left undefined
      else CalcReliability(Modes[m].Sig);

  //MOST RELIABLE  MODE
  BestMode := FindBestMode;

  Result.TxElevation := BestMode^.Ref.Elevation;
  Result.VirtHeight := BestMode^.Ref.VirtHeight;
  Result.HopCnt := BestMode^.HopCnt;
  Result.Sig := BestMode^.Sig;
  Result.Noise_dBW := FNoise.CombinedNoise.Value.Mdn;

  Result.ModeT := BestMode^.Layer;

  //ADD THE SIGNALS RANDOM PHASE i.e. ADD THE POWERS IN WATTS
  if Length(Modes) > 1 then
    begin
    CalcSumOfModes(Modes, Result);
    Result.Sig.Snr_dB := BestMode^.Sig.Snr_dB + Result.Sig.Power_dBW - BestMode^.Sig.Power_dBW;
    CalcReliability(Result.Sig, true);
    end;

  //REQUIRED POWER GAIN  FOR SPECIFIED RELIABILITY
  Result.RequiredPower := CalcRequiredPower(Result.Sig);
  Result.SnrXX := Pm.RequiredSnr - Result.RequiredPower;
end;


function TVoacapEngine.CalcRequiredPower(const ASig: TSignalInfo): Single;
var
  Idx: integer;
begin
  Idx := Min(High(TME), Abs(Round(Pm.RequiredReliability * 100) - 50) div 5);
  if Pm.RequiredReliability < 0.5
    then Result := Pm.RequiredSnr - ASig.Snr_dB - TME[Idx]/TME[8] * ASig.Snr90
    else Result := Pm.RequiredSnr - ASig.Snr_dB + TME[Idx]/TME[8] * ASig.Snr10;
end;

//add up Power_dBW, Power10, Power90, Field_dBuV of all modes
procedure TVoacapEngine.CalcSumOfModes(AModes: TModeInfoArray; var AResult: TPrediction);
var
  m: integer;
  MaxPwr, MaxPwrLo, MaxPwrHi, MaxFld: Single;
  SumPwr, SumPwrLo, SumPwrHi, SumFld: Single;
  X: Single;
begin
  //find max
  MaxPwr := -1000;
  MaxPwrLo := -1000;
  MaxPwrHi := -1000;
  MaxFld :=  -1000;

  for m:=0 to High(Modes) do
    begin
    MaxPwr := Max(MaxPwr, Modes[m].Sig.Power_dBW);
    MaxPwrLo := Max(MaxPwrLo, Modes[m].Sig.Power_dBW - Modes[m].Sig.Power10);
    MaxPwrHi := Max(MaxPwrHi, Modes[m].Sig.Power_dBW + Modes[m].Sig.Power90);
    MaxFld := Max(MaxFld, Modes[m].Sig.Field_dBuV);
    end;


  //add together
  SumPwrLo := 0;
  SumPwr := 0;
  SumPwrHi := 0;
  SumFld := 0;

  for m:=0 to High(Modes) do
    with Modes[m].Sig do
      begin
      X := Power_dBW - Power10 - MaxPwrLo;
      if X > -100 then SumPwrLo := SumPwrLo + FromDb(X);

      X := Power_dBW - MaxPwr;
      if X > -100 then SumPwr := SumPwr + FromDb(X);

      X := Power_dBW + Power90 - MaxPwrHi;
      if X > -100 then SumPwrHi := SumPwrHI + FromDb(X);

      X := Field_dBuV - MaxFld;
      if X > -100 then SumFld := SumFld + FromDb(X);
      end;


  if SumPwr > 0
    then AResult.Sig.Power_dBW := MaxPwr + ToDb(SumPwr)
    else AResult.Sig.Power_dBW := -500;

  if SumPwrLo > 0
    then AResult.Sig.Power10 := Abs(AResult.Sig.Power_dBW - ToDb(SumPwrLo) - MaxPwrLo)
    else AResult.Sig.Power10 := 0;
  AResult.Sig.Power10 := Max(0.2, Min(30, AResult.Sig.Power10));

  if SumPwrHi > 0
    then AResult.Sig.Power90 := Abs(MaxPwrHi + ToDb(SumPwrHi) - AResult.Sig.Power_dBW)
    else AResult.Sig.Power90 := 0;
  AResult.Sig.Power90 := Max(0.2, Min(30, AResult.Sig.Power90));

  if SumFld > 0
    then AResult.Sig.Field_dBuV := MaxFld + ToDb(SumFld)
    else AResult.Sig.Field_dBuV := -500;
end;


function TVoacapEngine.GetModeName(const APrediction: TPrediction): string;
begin
  if FPath.Dist < Rad_7000Km
    then Result := IntToStr(APrediction.HopCnt) + GetLayerName(APrediction.ModeT)
    else Result := GetLayerName(APrediction.ModeT) + GetLayerName(APrediction.ModeR);
end;


//hack: print all FP fields in a record in a unified way
function TVoacapEngine.ValuesToLine(APointer: Pointer; ADec: integer; AScale: Single = 1): string;
var
  Offset: Integer;
  f: integer;
  Fmt: string;

  function GetValue(Idx: integer): Single;
    begin Result := AScale * PSingle(PByte(@Results[idx]) + Offset)^; end;

begin
  Offset := PByte(APointer) - PByte(@Results[0]);
  Fmt := Format('%%5.%df', [ADec]);
  Result := '      ' + Format(Fmt, [GetValue(High(Results))]);
  for f:=0 to High(Freqs)-1 do Result := Result + Format(Fmt, [GetValue(f)]);
  for f:=High(Freqs) to 10 do Result := Result + '   - ';
end;


//generate text output in the same format as in voacapw.exe
function TVoacapEngine.ResultToText: string;
var
  Lines: TStringList;
  S: string;
  f: integer;
begin
  Lines := TStringList.Create;
  try
    //utc 
    S := Format('%6.1f%5.1f', [UtcTime * 24, FMufCalc.Muf]);
    //frequencies
    for f:=0 to High(Freqs)-1 do S := S + Format('%5.1f', [Freqs[f]]);
    for f:=High(Freqs) to 10 do S := S + '  0.0';
    Lines.Add(S + ' FREQ');

    //modes
    S := Format('%11s', [GetModeName(Results[High(Results)])]);
    for f:=0 to High(Freqs)-1 do S := S + Format('%5s', [GetModeName(Results[f])]);
    for f:=High(Freqs) to 10 do S := S + '   - ';
    Lines.Add(S + ' MODE');

    //FP values
    Lines.Add(ValuesToLine(@Results[0].TxElevation, 1,  DinR) + ' TANGLE');
    if FPath.Dist >= Rad_7000Km then 
      Lines.Add(ValuesToLine(@Results[0].RxElevation, 1,  DinR) + ' RANGLE');
    Lines.Add(ValuesToLine(@Results[0].Sig.Delay_ms,     1) + ' DELAY');
    Lines.Add(ValuesToLine(@Results[0].VirtHeight,       0) + ' V HITE');
    Lines.Add(ValuesToLine(@Results[0].Sig.MufDay,       2) + ' MUFday');
    Lines.Add(ValuesToLine(@Results[0].Sig.TotalLoss_dB, 0) + ' LOSS');
    Lines.Add(ValuesToLine(@Results[0].Sig.Field_dBuV,   0) + ' DBU');
    Lines.Add(ValuesToLine(@Results[0].Sig.Power_dBW,    0) + ' S DBW');
    Lines.Add(ValuesToLine(@Results[0].Noise_dBW,        0) + ' N DBW');
    Lines.Add(ValuesToLine(@Results[0].Sig.Snr_dB,       0) + ' SNR');
    Lines.Add(ValuesToLine(@Results[0].RequiredPower,    0) + ' RPWRG');
    Lines.Add(ValuesToLine(@Results[0].Sig.Reliability,  2) + ' REL');
    Lines.Add(ValuesToLine(@Results[0].MultiPathProb,    2) + ' MPROB');
    Lines.Add(ValuesToLine(@Results[0].ServiceProb,      2) + ' S PRB');
    Lines.Add(ValuesToLine(@Results[0].Sig.Power10,      1) + ' SIG LW');
    Lines.Add(ValuesToLine(@Results[0].Sig.Power90,      1) + ' SIG UP');
    Lines.Add(ValuesToLine(@Results[0].Sig.Snr10,        1) + ' SNR LW');
    Lines.Add(ValuesToLine(@Results[0].Sig.Snr90,        1) + ' SNR UP');
    Lines.Add(ValuesToLine(@Results[0].Sig.TxGain_dB,    1) + ' TGAIN');
    Lines.Add(ValuesToLine(@Results[0].Sig.RxGain_dB,    1) + ' RGAIN');
    Lines.Add(ValuesToLine(@Results[0].SnrXX,            0) + ' SNRxx');

    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;


function TVoacapEngine.CalcServiceProb: Single;
const
  DR = 2; //PREDICTION ERROR IN RSN, REQUIRED SNR
var
  Idx: integer;
  m: integer;
  Prob: Single;
  NoisePwr, SignalPwr, NoiseErr, SignalErr, Sgn: Single;
  Tmx, Pwr50, Pwr10, Z: Single;
begin
  Result := 0.001;

  Idx := Min(High(TME), Abs(Round(Pm.RequiredReliability * 100) - 50) div 5);
  Tmx := TME[Idx];

  if Pm.RequiredReliability >= 0.5
    then
      begin
      NoisePwr := Tmx * FNoise.CombinedNoise.Value.Hi / NORM_DECILE;
      SignalErr := Tmx * AvgLoss.Error.Hi;
      NoiseErr :=  Tmx * FNoise.CombinedNoise.Error.Hi / NORM_DECILE;
      Sgn := -1;
      end
    else
      begin
      NoisePwr := Tmx * FNoise.CombinedNoise.Value.Lo / NORM_DECILE;
      SignalErr := Tmx * AvgLoss.Error.Lo;
      NoiseErr :=  Tmx * FNoise.CombinedNoise.Error.Lo / NORM_DECILE;
      Sgn := 1;
      end;

  for m:=0 to High(Modes) do
    if Modes[m].Ref.VirtHeight > 70 then
      begin
      if Pm.RequiredReliability >= 0.5
        then SignalPwr := TME[Idx] * Modes[m].Sig.Power10 / NORM_DECILE
        else SignalPwr := TME[Idx] * Modes[m].Sig.Power90 / NORM_DECILE;

      Pwr50 := Sqrt(Sqr(SignalPwr) + Sqr(NoisePwr));
      Pwr10 := Pwr50 + Sqrt(Sqr(FNoise.CombinedNoise.Error.Mdn) +
        Sqr(AvgLoss.Error.Mdn) + Sqr(NoiseErr) + Sqr(SignalErr) + Sqr(DR));
      Pwr50 := Modes[m].Sig.Snr_dB + Sgn * Pwr50;
      Z := (Pm.RequiredSnr - Pwr50) / Pwr10;
      Prob := 1 - CumulativeNormal(Z);

      Result := Max(Result, Prob);
      end;
end;


function TVoacapEngine.CalcMultiPathProb: Single;
var
  m: integer;
  PowerLimit: Single;
begin
  Result := 0.001;
  if FPath.Dist > Rad_7000Km then Exit;

  PowerLimit := BestMode^.Sig.Power_dBW - Pm.MultipathPowerTolerance;

  for m:=0 to High(Modes) do
    if (Abs(Modes[m].Sig.Delay_ms - BestMode^.Sig.Delay_ms) > Pm.MaxTolerableDelay) and
       (Modes[m].Sig.Power_dBW > PowerLimit) then
      Result := Max(Result, Modes[m].Sig.Reliability);
end;


function TVoacapEngine.CalcDeciles(AFreq: Single; ALayer: TIonoLayer): TTripleValue;
var
  LogProbMuf, LogProbFot, LogProbHpf: Single;
  Cs: Single;
begin
  with FMufCalc.MufInfo[ALayer] do
    begin
    LogProbMuf := -ToDb(CalcMufProb(AFreq, Muf, Muf, SigLo, SigHi));
    LogProbFot := -ToDb(CalcMufProb(AFreq, Fot, Fot, SigLo, SigHi));
    LogProbHpf := -ToDb(CalcMufProb(AFreq, Hpf, Hpf, SigLo, SigHi));
    Cs := Ref.VertFreq / Muf;
    end;

  Result.Lo := (LogProbFot - LogProbMuf) / Cs;
  Result.Hi := (LogProbMuf - LogProbHpf) / Cs;
end;


function TVoacapEngine.DoEvaluateLongModel(TxRefl, RxRefl: TReflectrix): TPrediction;
var
  TxModes, RxModes: TModeInfoArray;
  Md, BestTxMode, BestRxMode: PModeInfo;

  AvgElevation, HopDist, Ramp, PathLen, ConvFact, HopCnt: Single;
  TxEndLoss, RxEndLoss: Single;
  DistI, DistM, DistF, LossM, LossF: Single;
  Dec: TTripleValue;
begin
  Modes := nil; SetLength(Modes, 1);
  Md := @Modes[0];

  //find best angle at each end
  TxModes := ListModes(TxRefl);
  RxModes := ListModes(RxRefl);
  BestTxMode := SelectOptimumAngle(TxModes, TxAnts);
  BestRxMode := SelectOptimumAngle(RxModes, RxAnts);

  //AVERAGE TAKE-OFF ANGLE
  AvgElevation := 0.5 * (BestTxMode^.Ref.Elevation + BestRxMode^.Ref.Elevation);
  //AVERAGE VIRTUAL HEIGHT
  Md^.Ref.VirtHeight := 0.5 * (BestTxMode^.Ref.VirtHeight + BestRxMode^.Ref.VirtHeight);

  //path structure: 0.5*ramp + straight + 0.5*ramp
  HopDist := HopDistance(AvgElevation, Md^.Ref.VirtHeight);
  Ramp := HopLength3D(AvgElevation, HopDist, Md^.Ref.VirtHeight);
  PathLen := Ramp + (EarthR + Md^.Ref.VirtHeight) * Max(0.001, FPath.Dist - HopDist);

  //FREE-SPACE CONVERGENCE FACTOR
  ConvFact := PathLen / EarthR * Cos(AvgElevation) / Max(0.000001, Abs(Sin(FPath.Dist)));
  ConvFact := Min(15, ToDb(ConvFact));
  //FREE-SPACE LOSS
  Md^.FreeSpaceLoss := 36.58 + 2 * ToDb(0.6214 * PathLen * Freq) - ConvFact;

  //IONOSPHERIC DISTANCE
  DistI := FPath.Dist - 0.5 * (BestTxMode^.HopDist + BestRxMode^.HopDist);
  //THE DISTANCE SUPPORTING M MODES, E.G., NIGHT-DAY-NIGHT PATH
  DistM := CalcMModeDistance(DistI, Freq);
  DistF := Max(0, DistI - DistM);
  //loss due to distance
  LossM := DistM * EarthR * GetAbsPerKm(Freq, AvgElevation, Md^.Ref.VirtHeight, DistM, 0.1);
  LossF := DistF * EarthR * GetAbsPerKm(Freq, AvgElevation, Md^.Ref.VirtHeight, DistF, FAbsorptionIndex);

  //LOSS AT TRANSMITTER END
  TxEndLoss := 0.5 * (BestTxMode^.AbsorptionLoss + BestTxMode^.DeviationTerm);
  //LOSS AT RECEIVER END
  RxEndLoss := 0.5 * (BestRxMode^.AbsorptionLoss + BestRxMode^.DeviationTerm);

  //AVERAGE GROUND LOSS
  Md^.GroundLoss := 0.5 * (BestTxMode^.GroundLoss + BestRxMode^.GroundLoss);
  HopCnt := Max(1, DistF / (0.5 * (BestTxMode^.HopDist + BestRxMode^.HopDist)));

  //TRANSMISSION LOSS
  Md^.Sig.TotalLoss_dB := Md^.FreeSpaceLoss + TxEndLoss + LossM
    + LossF + RxEndLoss + (HopCnt - 1) * Md^.GroundLoss + Adj_Auroral
    - Md^.Sig.TxGain_dB - Md^.Sig.RxGain_dB;

  HopCnt := Max(1, FPath.Dist / (BestTxMode^.HopDist + BestRxMode^.HopDist));
  Md^.HopCnt := Trunc(HopCnt); //{?}
  Md^.Sig.TxGain_dB := TxAnts.CurrentAntenna.GetGainDb(BestRxMode^.Ref.Elevation);
  Md^.Sig.RxGain_dB := RxAnts.CurrentAntenna.GetGainDb(BestTxMode^.Ref.Elevation);
  Md^.Sig.Delay_ms := PathLen / VofL;
  Md^.Ref.Elevation := BestTxMode^.Ref.Elevation;
  Md^.AbsorptionLoss := 0.5 * (BestTxMode^.AbsorptionLoss + BestRxMode^.AbsorptionLoss);
  Md^.Obscuration := 0.5 * (BestTxMode^.Obscuration + BestRxMode^.Obscuration);
  Md^.DeviationTerm := 0.5 * (BestTxMode^.DeviationTerm + BestRxMode^.DeviationTerm);
  Md^.Sig.Power_dBW := TxAnts.CurrentAntenna.TxPower_dBW - Md^.Sig.TotalLoss_dB;
  Md^.Sig.Field_dBuV := 107.2 + Md^.Sig.Power_dBW  + 2 * ToDb(Freq) - Md^.Sig.RxGain_dB;
  Md^.Sig.Snr_dB := Md^.Sig.Power_dBW - FNoise.Combined;

  //LOWER DECILE, UPPER DECILE
  Dec := CalcDeciles(Freq, BestTxMode^.Layer);
  if BestRxMode^.Layer <> BestTxMode^.Layer then
    with CalcDeciles(Freq, BestRxMode^.Layer) do
      begin
      Dec.Lo := 0.5 * (Dec.Lo + Lo);
      Dec.Hi := 0.5 * (Dec.Hi + Hi);
      end;
  Md^.Sig.Power10 := Min(25, Adj_Signal_10 + HopCnt * Dec.Lo);
  Md^.Sig.Power90 := Min(25, Adj_Signal_90 + HopCnt * Dec.Hi);

  //F.DAYS
  Md^.Sig.MufDay := Min(BestTxMode^.Sig.MufDay, BestRxMode^.Sig.MufDay);

  Result := AnalyzeReliability;
  Result.ServiceProb := CalcServiceProb;

  Result.Method := mdLong;
  Result.ModeT := BestTxMode^.Layer;
  Result.ModeR := BestRxMode^.Layer;
  Result.RxElevation := BestRxMode^.Ref.Elevation;
end;


function TVoacapEngine.GetAbsPerKm(AFreq, AElevation, AVirtHeight, ADistance, AAbsIndex: Single): Single;
var
  AC, BC, HopCnt: Single;
begin
  if (ADistance <= 0) or (AVIrtHeight <= 70) then begin Result := 1000; Exit; end;

  //these calculations are repeated in several other places, consider making them a proc
  AC := 677.2 * AAbsIndex;
  BC := Power(AFreq + Profiles[1].GyroFreq, 1.98); //gyro at path center
  Result := AC / (BC + 10.2) / CosOfIncidence(AElevation, 100);

  HopCnt := ADistance / HopDistance(AElevation, AVirtHeight);
  Result := Result * HopCnt / (ADistance * EarthR);
end;

//long path model constants
const
  GMIN = 3;
  DELOPT = 3 * RinD;
  YMIN = 0.1;


function TVoacapEngine.CalcMModeDistance(AIonoDist, AFreq: Single): Single;
var
  PenetrationFreq: array[0..2] of Single;
  i: integer;
  FP1, FP2, FP3: Single;
begin
  Assert(Length(Profiles) = 3);
  Result := 0;

  //E PENETRATION FREQUENCIES
  for i:=0 to 2 do
    PenetrationFreq[i] := Profiles[i].E.Fo / CosOfIncidence(DELOPT, Profiles[i].E.Hm);

  FP1 := Max(PenetrationFreq[0], PenetrationFreq[2]);
  FP2 := PenetrationFreq[1];
  FP3 := Min(PenetrationFreq[0], PenetrationFreq[2]);

  //THE MIDDLE IS --
  if FP1 >= FP2 then Exit;
  if AFreq >= (FP2 + 0.001) then Exit;
  if AFreq <= (FP1 - 0.001) then Exit;

  Result := 0.5 * AIonoDist * (FP2 - AFreq) * (1 / (FP2-FP1) + 1 / (FP2-FP3));
  if Result <= Rad_1000Km then Result := 0;
  //MUST BE ABLE TO GET UP THERE FOR M MODE
  if (AIonoDist <= (Result + Rad_1000Km)) then Result := 0;
end;


procedure TVoacapEngine.ComputeLosses(var AMode: TModeInfo; AProf: TIonoProfile; AFreq: Single);
var
  AC, BC, NSqr, HEff, ADX: Single;
  p: integer;
begin
  if AMode.Ref.VertFreq < AProf.E.Fo
    then //D-E  LAYER MODES
      begin
      if AMode.Ref.TrueHeight >= HTLOSS
        then NSqr := 10.2
        else NSqr := XNUZ * Exp(-2 * (1 + 3 * (AMode.Ref.TrueHeight - 70) / 18) / HNU);
      HEff := Min(100, AMode.Ref.TrueHeight);
      ADX := Adj_CCIR252_A + Adj_CCIR252_B * Ln(Max(AMode.Ref.VertFreq / AProf.E.Fo , Adj_DE_Loss));
      end
    else //F LAYER MODES
      begin
      NSqr := 10.2;
      HEff := 100;
      ADX := 0;
      end;

  //ABSORPTION LOSS
  //this is for LP model. For SP, FAbsorptionIndex is used instead
  AC := 677.2 * AProf.AbsorptionIndex;
  BC := Power(AFreq + AProf.GyroFreq, 1.98);
  AMode.AbsorptionLoss := AC / (BC + NSqr) / CosOfIncidence(AMode.Ref.Elevation, HEff);

  //DEVIATIVE LOSS
  AMode.DeviationTerm := AMode.Ref.DevLoss /(BC + NSqr) *
    (Power(AMode.Ref.VertFreq + AProf.GyroFreq, 1.98) + NSqr) /
    CosOfIncidence(AMode.Ref.Elevation, AMode.Ref.VirtHeight) + ADX;

  //{Es} ES OBSCURTION LOSS
  AMode.Obscuration := 0;

  //AVERAGE GROUND LOSS
  AMode.GroundLoss := 0;
  for p:=0 to High(CtrlPts) do
    AMode.GroundLoss := AMode.GroundLoss + ComputeGroundReflectionLoss(p, AMode.Ref.Elevation, AFreq);
  AMode.GroundLoss :=  AMode.GroundLoss / Length(CtrlPts);
end;


//SETTXR
function TVoacapEngine.ListModes(ARefl: TReflectrix): TModeInfoArray;
var
  Src, Dst: integer;

  procedure ComputeAllLosses(Idx: integer);
    begin
    ComputeLosses(Result[Idx], ARefl.FProf, ARefl.FMHz);

    with FMufCalc.MufInfo[FMufCalc.Layer] do
      Result[Idx].Sig.MufDay := CalcMufProb(ARefl.FMHz, Muf, Muf, SigLo, SigHi);

    //ADD ADJUSTMENT TO ABSORPTION LOSS
    with Result[Idx] do
      AbsorptionLoss := AbsorptionLoss - ToDb(Sig.MufDay) /
        CosOfIncidence(Ref.Elevation, Ref.TrueHeight);
    end;

begin
  SetLength(Result, Length(ARefl.Refl));
  Dst := 0;
  for Src:=0 to High(ARefl.Refl) do
    if (ARefl.Refl[Src].Ref.VirtHeight >= 70) and
       ((Min(Rad_4000Km, FPath.Dist) / ARefl.Refl[Src].HopDist) >= 0.9) and
       (ARefl.Refl[Src].Ref.Elevation >= Pm.MinAngle) then
      begin
      Result[Dst].Ref := ARefl.Refl[Src].Ref;
      Result[Dst].HopCnt := ARefl.Refl[Src].HopCnt;
      Result[Dst].HopDist := ARefl.Refl[Src].HopDist;
      Result[Dst].Layer := ARefl.Refl[Src].Layer;
      ComputeAllLosses(Dst);
      Inc(Dst);
      end;
  SetLength(Result, Dst);

  //PENETRATED LAYER, TRY OVER THE MUF MODE
  if Result = nil then
    begin
    SetLength(Result, 1);
    Result[0].Ref := FMufCalc.MufInfo[FMufCalc.Layer].Ref;
    Result[0].HopCnt := FMufCalc.MufInfo[FMufCalc.Layer].HopCount;
    Result[0].HopDist := FPath.Dist / Result[0].HopCnt;
    Result[0].Layer := FMufCalc.Layer;
    ComputeAllLosses(0);
    end;
end;


//SELTXR
function TVoacapEngine.SelectOptimumAngle(AModes: TModeInfoArray;
  AAnts: TAntennaFarm): PModeInfo;
var
  i: integer;
  Gain, BestGain: Single;
  DEND: Single;
  Hops: Single;
  HopFrac, BestFrac: Single;
  Angle, BestAngle: Single;
begin
  DEND := Min(Rad_4000Km, FPath.Dist);

  Result := @AModes[0];
  Hops := DEND / Result^.HopDist;
  BestFrac := Abs(Hops - Round(Hops));
  BestGain := AAnts.CurrentAntenna.GetGainDb(Result^.Ref.Elevation) -
    Hops * (Result^.AbsorptionLoss + Result^.DeviationTerm);
  BestAngle := Abs(Result^.Ref.Elevation - DELOPT);


  for i:=1 to High(AModes) do
    begin
    Hops := DEND / AModes[i].HopDist;
    HopFrac := Abs(Hops - Round(Hops));
    Gain := AAnts.CurrentAntenna.GetGainDb(AModes[i].Ref.Elevation) -
      Hops * (AModes[i].AbsorptionLoss + AModes[i].DeviationTerm);
    Angle := Abs(AModes[i].Ref.Elevation - DELOPT);

    //skip if not better
    if Gain < (BestGain - GMIN) then Continue;
    if Gain <= (BestGain + GMIN) then
      begin
      if HopFrac > (BestFrac + YMIN) then Continue;
      if HopFrac >= (BestFrac - YMIN) then
        if Angle > BestAngle then Continue;
      end;

    //this mode is better than previous best
    Result := @AModes[i];
    BestFrac := HopFrac;
    BestGain := Gain;
    BestAngle := Angle;
    end;
end;



end.


