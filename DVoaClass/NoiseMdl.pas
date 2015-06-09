//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is NoiseMdl.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit NoiseMdl;

interface

uses
  SysUtils, VoaTypes, FrMaps, Math;


type
  TNoiseModel = class
  private
    //params for manmade 1-MHz noise map interpolation
    FLat: Single;
    FEastLon: Single;
    T1, T2: integer;
    dT: Single;
    NsMHz1, NsMHz2: Single;

    function InterpolateDistribution(D1, D2: TDistribution; r: Single): TDistribution;
    function ComputeNoiseAtFreq(Idx: integer; AFreq,
      ANoise1MHz: Single): TDistribution;
  public
    //access to the map data
    FMap: TFourierMaps;

    //input param
    ManMadeNoiseAt3MHz: single;

    //output
    AtmosphericNoise,
    GalacticNoise,
    ManMadeNoise,
    CombinedNoise: TDistribution;

    constructor Create;
    //prepare 1MHz noise coeffs for use in ComputeDistribution
    procedure ComputeNoiseAt1Mhz(const ALocation: TGeoPoint; ALocalTime: TDateTime);
    //noise pdf for specific frequency
    procedure ComputeDistribution(AFreq, foF2: Single);

    //output: median combined noise
    property Combined: Single read CombinedNoise.Value.Mdn;
  end;



implementation

{ TNoiseModel }

constructor TNoiseModel.Create;
begin
  ManMadeNoiseAt3MHz := 145;
end;


//prepare data for future computations:
//save Lat, EastLon
//compute T1, T2, dT, NsMhz1, NsMhz2
procedure TNoiseModel.ComputeNoiseAt1Mhz(const ALocation: TGeoPoint;
  ALocalTime: TDateTime);
begin
  //local time, in hours, at the receiver
  ALocalTime := 24 * ALocalTime;

  //east longitude of the receiver, 0..2*Pi
  if ALocation.Lon >= 0
    then FEastLon := ALocation.Lon
    else FEastLon := TWO_PI + ALocation.Lon;
  FLat := ALocation.Lat;

  //noise map selection, fmNoise1..fmNoise6
  if ALocalTime < 22
    then T1 := Trunc(ALocalTime / 4)
    else T1 := Ord(fmNoise6);

  dT := (ALocalTime - (4 * T1 + 2)) * 0.25;
  if dT < 0 then T2 := Pred(T1)
  else if dT > 0 then T2 := Succ(T1)
  else T2 := T1;

  if T2 < Ord(fmNoise1) then T2 := Ord(fmNoise6)
  else if T2 > Ord(fmNoise6) then T2 := Ord(fmNoise1);

  //1-MHz noise from map
  NsMhz1 := FMap.ComputeFixedMap(TNoiseIndex(T1), FLat, FEastLon);
  NsMhz2 := FMap.ComputeFixedMap(TNoiseIndex(T2), FLat, FEastLon);
end;


function TNoiseModel.ComputeNoiseAtFreq(Idx: integer; AFreq, ANoise1MHz: Single): TDistribution;
var
 PZ, PX, x: Single;
begin
  if FLat < 0 then Inc(Idx, 6);

  PZ := FMap.ComputeFam(Idx, 0, -0.75);
  PX := FMap.ComputeFam(Idx, 1, -0.75);
  Result.Value.Mdn := ANoise1MHz * (2 - PZ) - PX;

  x :=(8 * Power(2, Log10(AFreq)) - 11) / 4;
  PZ := FMap.ComputeFam(Idx, 0, x);
  PX := FMap.ComputeFam(Idx, 1, x);
  Result.Value.Mdn := Result.Value.Mdn * PZ + PX;

  x := Log10(Min(20, AFreq));
  Result.Value.Hi :=  FMap.ComputeDud(0, Idx, x);
  Result.Value.Lo :=  FMap.ComputeDud(1, Idx, x);
  Result.Error.Hi :=  FMap.ComputeDud(2, Idx, x);
  Result.Error.Lo :=  FMap.ComputeDud(3, Idx, x);
  Result.Error.Mdn := FMap.ComputeDud(4, Idx, Min(1, x));
end;


function TNoiseModel.InterpolateDistribution(D1, D2: TDistribution; r: Single): TDistribution;
begin
  Result.Value.Mdn := D1.Value.Mdn * (1-r) + D2.Value.Mdn * r;
  Result.Value.Lo := D1.Value.Lo * (1-r) + D2.Value.Lo * r;
  Result.Value.Hi := D1.Value.Hi * (1-r) + D2.Value.Hi * r;

  Result.Error.Mdn := D1.Error.Mdn * (1-r) + D2.Error.Mdn * r;
  Result.Error.Lo := D1.Error.Lo * (1-r) + D2.Error.Lo * r;
  Result.Error.Hi := D1.Error.Hi * (1-r) + D2.Error.Hi * r;
end;


type TNoiseFactorDtstribution = record AU, VU, AL, VL: Single; end;


function CalcAV(D: TDistribution): TNoiseFactorDtstribution;
const
  DFAC = 7.87384;
  BFAC = 30.99872;
begin
  with Result do
    begin
    AU := Exp(Sqr(D.Value.Hi / DFAC) + D.Value.Mdn * NPinDB);
    VU := Sqr(AU) * (Exp(Sqr(D.Value.Hi) / BFAC) - 1);
    AL := Exp(Sqr(D.Value.Lo / DFAC) + D.Value.Mdn * NPinDB);
    VL := Sqr(AL) * (Exp(Sqr(D.Value.Lo) / BFAC) - 1);
    end;
end;


procedure TNoiseModel.ComputeDistribution(AFreq, foF2: Single);
const
  ZeroAV: TNoiseFactorDtstribution = (AU: 0; VU: 0; AL: 0; VL: 0);
  CFAC = 5.56765; //= DBinNP * NORM_DECILE

  Default_Galactic: TDistribution =
    (Value: (Mdn: 0; Lo: 2; Hi: 2); Error: (Mdn: 0.5; Lo: 0.2; Hi: 0.2));

  Default_Manmade: TDistribution =
    (Value: (Mdn: 0; Lo: 6; Hi: 9.7); Error: (Mdn: 5.4; Lo: 1.5; Hi: 1.5));
var
  D1, D2: TDistribution;
  AV_Atm, AV_Gal, AV_Man, AV_Sum: TNoiseFactorDtstribution;
  QP_Atm, QP_Gal, QP_Man: Single;
  SigLo, SigHi, Sig: Single;
  PV: Single;
begin
  //FREQUENCY DEPENDENT ATMOSPHERIC NOISE
  D1 := ComputeNoiseAtFreq(T1, AFreq, NsMHz1);
  D2 := ComputeNoiseAtFreq(T2, AFreq, NsMHz2);
  AtmosphericNoise := InterpolateDistribution(D1, D2, Abs(dT));
  AV_Atm := CalcAV(AtmosphericNoise);

  //GALACTIC NOISE
  GalacticNoise := Default_Galactic;
  if AFreq > foF2
    then
      begin
      GalacticNoise.Value.Mdn := 52 - 23 * Log10(AFreq);
      AV_Gal := CalcAV(GalacticNoise);
      end
    else
      //GALACTIC NOISE DOES NOT PENETRATE -- IGNORE
      begin
      GalacticNoise.Value.Mdn := 0;
      AV_Gal := ZeroAV;
      end;

  //MAN MADE NOISE
  ManMadeNoise := Default_Manmade;
  ManMadeNoise.Value.Mdn := 204 - ManMadeNoiseAt3MHz + 13.22 - 27.7 * Log10(AFreq);
  AV_Man := CalcAV(ManMadeNoise);

  //combined AV
  AV_Sum.AU := AV_Atm.AU + AV_Gal.AU + AV_Man.AU;
  AV_Sum.VU := AV_Atm.VU + AV_Gal.VU + AV_Man.VU;
  AV_Sum.AL := AV_Atm.AL + AV_Gal.AL + AV_Man.AL;
  AV_Sum.VL := AV_Atm.VL + AV_Gal.VL + AV_Man.VL;

  //SWITCH TO DB .GT. WATT
  AtmosphericNoise.Value.Mdn := AtmosphericNoise.Value.Mdn - 204;
  GalacticNoise.Value.Mdn := GalacticNoise.Value.Mdn - 204;
  ManMadeNoise.Value.Mdn := ManMadeNoise.Value.Mdn - 204;

  //DETERMINATION OF NOISE LEVEL IS ITS-78
  CombinedNoise.Value.Mdn := ToDb(FromDb(AtmosphericNoise.Value.Mdn) +
    FromDb(GalacticNoise.Value.Mdn) + FromDb(ManMadeNoise.Value.Mdn));

  //SPAULDING'S ORIGINAL REPLACES SIMPLE POWER SUM
  SigHi := Ln(1 + AV_Sum.VU / Sqr(AV_Sum.AU));
  SigLo := Ln(1 + AV_Sum.VL / Sqr(AV_Sum.AL));

  //CARUANA'S MODIFICATION
  //See  http://www.greg-hand.com/noise/itu_submission.doc
  if (AtmosphericNoise.Value.Hi > 12) or (AtmosphericNoise.Value.Lo > 12) then
    begin
    Sig := 2 * (Ln(AV_Sum.AU) - (CombinedNoise.Value.Mdn + 204) * NPinDB);
    if Sig > 0 then SigHi := Min(Sig, SigHi);

    Sig := 2 * (Ln(AV_Sum.AL) - (CombinedNoise.Value.Mdn + 204) * NPinDB);
    if Sig > 0 then SigLo := Min(Sig, SigLo);
    end;
  CombinedNoise.Value.Mdn := DBinNP * (Ln(AV_Sum.AU) - SigHi/2) - 204;

  //UPPER DECILE
  CombinedNoise.Value.Hi := CFAC * Sqrt(SigHi);

  //LOWER DECILE
  CombinedNoise.Value.Lo := CFAC * Sqrt(SigLo);

  //PREDICTION ERRORS
  QP_Atm := FromDb(AtmosphericNoise.Value.Mdn - CombinedNoise.Value.Mdn);
  if AFreq > foF2 then QP_Gal := FromDb(GalacticNoise.Value.Mdn - CombinedNoise.Value.Mdn) else QP_Gal := 0;
  QP_Man := FromDb(ManMadeNoise.Value.Mdn - CombinedNoise.Value.Mdn);

  CombinedNoise.Error.Mdn := Sqrt(Sqr(QP_Atm * AtmosphericNoise.Error.Mdn) +
    Sqr(QP_Gal * GalacticNoise.Error.Mdn) + Sqr(QP_Man * ManMadeNoise.Error.Mdn));

  with AtmosphericNoise do
    begin
    PV := QP_Atm * FromDb(Value.Hi - CombinedNoise.Value.Hi);
    CombinedNoise.Error.Hi := Sqr(PV * Error.Hi) + Sqr((PV - QP_Atm) * Error.Mdn);
    PV := QP_Atm * FromDb(Value.Lo - CombinedNoise.Value.Lo);
    CombinedNoise.Error.Lo := Sqr(PV * Error.Lo) + Sqr((PV - QP_Atm) * Error.Mdn);
    end;

  with GalacticNoise do
    begin
    PV := QP_Gal * FromDb(Value.Hi - CombinedNoise.Value.Hi);
    CombinedNoise.Error.Hi := CombinedNoise.Error.Hi + Sqr(PV * Error.Hi) + Sqr((PV - QP_Gal) * Error.Mdn);
    PV := QP_Gal * FromDb(Value.Lo - CombinedNoise.Value.Lo);
    CombinedNoise.Error.Lo := CombinedNoise.Error.Lo + Sqr(PV * Error.Lo) + Sqr((PV - QP_Gal) * Error.Mdn);
    end;

  with ManMadeNoise do
    begin
    PV := QP_Man * FromDb(Value.Hi - CombinedNoise.Value.Hi);
    CombinedNoise.Error.Hi := Sqrt(CombinedNoise.Error.Hi + Sqr(PV * Error.Hi) + Sqr((PV - QP_Man) * Error.Mdn));
    PV := QP_Man * FromDb(Value.Lo - CombinedNoise.Value.Lo);
    CombinedNoise.Error.Lo := Sqrt(CombinedNoise.Error.Lo + Sqr(PV * Error.Lo) + Sqr((PV - QP_Man) * Error.Mdn));
    end;
end;


end.
