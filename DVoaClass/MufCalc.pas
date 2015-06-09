//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is MufCalc.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit MufCalc;

interface

uses
  SysUtils, VoaTypes, PathGeom, FrMaps, IonoProf, Math;


type
  TCircuitMuf = class
  private
    Profile: TIonoProfile;

    //temp vars computed in FirstEstimate and used elsewhere
    HopDist, SinISqr: Single;

    function ComputeMufE: TMufInfo;
    function ComputeMufF1: TMufInfo;
    function ComputeMufF2: TMufInfo;
    procedure ComputeFirstEstimate(var AResult: TMufInfo);
    procedure RefineEstimate(var AResult: TMufInfo; LayerFo: Single);
  public
    //helper objects
    FPath: TPathGeometry;
    FMap: TFourierMaps;
    MinAngle: Single;

    //output
    MufInfo: TMufInfoArray;
    Fot, Muf, Hpf: Single;
    Angle: Single;
    Layer: TIonoLayer;

    procedure ComputeCircuitMuf(Profiles: TIonoProfiles);
  end;


function SelectProfile(Profiles: TIonoProfiles): TIonoProfile;
function CalcMufProb(AFreq, AModeMuf, AMedian, SigmaLo, SigmaHi: Single): Single;




implementation


const
  FQDEL = 0.1;


function SelectProfile(Profiles: TIonoProfiles): TIonoProfile;
begin
  Result := nil;

  case Length(Profiles) of
    1:
      Result := Profiles[0];
    2:
      if Profiles[0].E.Fo <= Profiles[1].E.Fo
        then Result := Profiles[0] else Result := Profiles[1];
    3:
      if Abs(Profiles[0].F2.Fo - Profiles[2].F2.Fo) > 0.01
        then
          if Profiles[0].F2.Fo <= Profiles[2].F2.Fo
            then Result := Profiles[0] else Result := Profiles[2]
        else
          if Profiles[0].E.Fo <= Profiles[2].E.Fo
            then Result := Profiles[0] else Result := Profiles[2];
    end;
end;



//Prob that MUF exceeds AFreq

//AFreq    IS THE OPERATING FREQUENCY
//AModeMuf IS THE MUF AT A SET ANGLE FOR A PARTICULAR LAYER, FOR ONE HOP
//         (IT MAY NOT BE THE CIRCUIT MUF)
//AMedian  IS WHERE MEDIAN OF DISTRIBUTION IS PLACED (=FOT, MUF OR HPF)
//SigmaLo  IS THE LOWER DECILE
//SigmaHi  IS THE UPPER DECILE
function CalcMufProb(AFreq, AModeMuf, AMedian, SigmaLo, SigmaHi: Single): Single;
var
  Sig, z: Single;
begin
  z := AFreq - AModeMuf;

  if AMedian <= 0
    then
      if z <= 0 then Result := 1 else Result := 0
    else
      begin
      if z <= 0 then Sig := SigmaLo else Sig := SigmaHi;
      z := z / Max(0.001, AModeMuf * Sig / AMedian);
      Result := 1 - CumulativeNormal(z);
      end;
end;


procedure TCircuitMuf.ComputeCircuitMuf(Profiles: TIonoProfiles);
begin
  //SELECT CONTROLING SAMPLE AREA
  Profile := SelectProfile(Profiles);

  //CALCULATE ELECTRON DENSITY PROFILE
  Profile.ComputeElDensityProfile;

  //E LAYER MUF
  MufInfo[lrE] := ComputeMufE;

  //F2 LAYER MUF
  MufInfo[lrF2] := ComputeMufF2;

  //F1 LAYER MUF
  if Profile.F1.Fo = 0 then MufInfo[lrF1] := MufInfo[lrE] else MufInfo[lrF1] := ComputeMufF1;

  //CIRCUIT MUF
  //NOTE THAT ES IS NOT INCLUDED HERE
  Fot := MaxValue([MufInfo[lrE].Fot, MufInfo[lrF1].Fot, MufInfo[lrF2].Fot]);
  Muf := MaxValue([MufInfo[lrE].Muf, MufInfo[lrF1].Muf, MufInfo[lrF2].Muf]);
  Hpf := MaxValue([MufInfo[lrE].Hpf, MufInfo[lrF1].Hpf, MufInfo[lrF2].Hpf]);

  if MufInfo[lrE].Muf >= Muf then
    begin Angle := MufInfo[lrE].Ref.Elevation; Layer := lrE; end
  else if MufInfo[lrF1].Muf >= Muf then
    begin Angle := MufInfo[lrF1].Ref.Elevation; Layer := lrF1; end
  else
    begin Angle := MufInfo[lrF2].Ref.Elevation; Layer := lrF2; end;
end;


function TCircuitMuf.ComputeMufE: TMufInfo;
begin
  //TANGENT FREQUENCIES
  Result.Ref.VertFreq := Profile.E.Fo / Sqrt(1 + 0.5 * YmE / HmE);

  ComputeFirstEstimate(Result);

  //DISTRIBUTION FOR E LAYER MUF
  Result.SigLo := Max(0.01, 0.1 * Result.Muf);
  Result.SigHi := Result.SigLo;

  //DECILES
  Result.Fot := Result.Muf - NORM_DECILE * Result.SigLo;
  Result.Hpf := Result.Muf + NORM_DECILE * Result.SigHi;
  //THE DEVIATIVE LOSS FACTOR FOR THE E LAYER
  Result.Ref.DevLoss := 0;
end;


function TCircuitMuf.ComputeMufF2: TMufInfo;
const
  BEX = 9.5;
var
  XtF2, Beta: Single;
begin
  //TANGENT FREQUENCIES
  XtF2 := 1 / Sqrt(1 + 0.5 * Profile.F2.Ym / Profile.F2.Hm);
  Result.Ref.VertFreq := Profile.F2.Fo * XtF2;

  //FORCE F2MUF TO APPROACH MUF(0)
  if FPath.Dist < Rad_2000Km then
    begin
    Beta := 1 + (1/XtF2 - 1) * Exp(-BEX * FPath.Dist / Rad_2000Km);
    Result.Ref.VertFreq := Result.Ref.VertFreq * Beta;
    end;

  ComputeFirstEstimate(Result);
  RefineEstimate(Result, Profile.F2.Fo);

  //F2 MUF DISTRIBUTION FROM THE F2 M(3000) TABLES
  Result.SigLo := Max(0.01, FMap.ComputeF2Deviation(Result.Muf, Profile.Lat, Profile.LocalTimeF2, false));
  Result.SigHi := Max(0.01, FMap.ComputeF2Deviation(Result.Muf, Profile.Lat, Profile.LocalTimeF2, true));

  Result.Fot := Result.Muf - NORM_DECILE * Result.SigLo;
  Result.Hpf := Result.Muf + NORM_DECILE * Result.SigHi;
  Result.Ref.DevLoss := 0;
end;


function TCircuitMuf.ComputeMufF1: TMufInfo;
begin
  //TANGENT FREQUENCIES
  Result.Ref.VertFreq := Profile.F1.Fo / Sqrt(1 + 0.5 * Profile.F1.Ym / Profile.F1.Hm);

  ComputeFirstEstimate(Result);
  RefineEstimate(Result, Profile.F1.Fo);

  Result.SigLo := Max(0.01, 0.1 * Result.Muf);
  Result.SigHi := Result.SigLo;

  Result.Fot := Result.Muf - NORM_DECILE * Result.SigLo;
  Result.Hpf := Result.Muf + NORM_DECILE * Result.SigHi;
  Result.Ref.DevLoss := 0;
end;


procedure TCircuitMuf.ComputeFirstEstimate(var AResult: TMufInfo);
begin
  //height
  AResult.Ref.TrueHeight := Profile.GetTrueHeight(AResult.Ref.VertFreq);
  AResult.Ref.VirtHeight := Profile.GetVirtualHeightGauss(AResult.Ref.VertFreq);

  //hops
  AResult.HopCount := FPath.HopCount(MinAngle, AResult.Ref.VirtHeight);
  HopDist := FPath.Dist / AResult.HopCount;

  //elevation angle
  AResult.Ref.Elevation := CalcElevationAngle(HopDist, AResult.Ref.VirtHeight);

  //muf
  SinISqr := Sqr(SinOfIncidence(AResult.Ref.Elevation, AResult.Ref.TrueHeight));
  AResult.Muf := AResult.Ref.VertFreq / Sqrt(1 - SinISqr);
end;


procedure TCircuitMuf.RefineEstimate(var AResult: TMufInfo; LayerFo: Single);
var
  OrigHeight, PrevMuf, Corr0, Corr: Single;
  i: integer;
begin
  OrigHeight := AResult.Ref.VirtHeight;
  Corr0 := CorrToMartynsTheorem(AResult.Ref);

  //iteration for MufF2.Muf, HPX2.  allows 4 tries to obtain epsilon of 0.1
  for i:=1 to 4 do
    begin
    PrevMuf := AResult.Muf;

    //CORRECTION TO MARTYN"S THEOREM
    Corr := Corr0 * Sqr(PrevMuf / LayerFo) * SinISqr;
    //CORRECTED VIRTUAL HEIGHT
    AResult.Ref.VirtHeight := OrigHeight + Corr;

    //new elevation angle and MUF
    AResult.Ref.Elevation := CalcElevationAngle(HopDist, AResult.Ref.VirtHeight);
    SinISqr := Sqr(SinOfIncidence(AResult.Ref.Elevation, AResult.Ref.TrueHeight));
    AResult.Muf := AResult.Ref.VertFreq / Sqrt(1 - SinISqr);

    //CORRECTION IS SUFFICIENT
    if Abs(AResult.Muf - PrevMuf) <= FQDEL then Break;
    end;
end;



end.

