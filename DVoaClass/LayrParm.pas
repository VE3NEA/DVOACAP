//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is LayrParm.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit LayrParm;

interface

uses
  SysUtils, Math, VoaTypes, FrMaps;


procedure ComputeIonoParams(var Pnt: TControlPoint; Map: TFourierMaps);




implementation

//compute retardation, adjust F1 layer if necessary
function ComputeF2Retardation(var Pnt: TControlPoint): Single;
const
  DELZ = 2 * RinD;
  XF1 = 1.1;
var
  Fc, Fec, Rft: Single;
  Zn, Hn, Yn, Sz, Hm, Ym, dH, Y1Max: Single;
begin
  //E LAYER RETARDATION
  Fc := 0.834 * Pnt.F2.Fo;
  Fec := Max(1.1, Fc / Pnt.E.Fo);
  Result := Fec * Ln((Fec + 1) / (Fec - 1));
  Result := (Result - 2) * Pnt.E.Ym;

  //FORCE MERGER OF F1 LAYER INTO F2 LAYER.
  //CHECK IF F1 IS AT TWILIGHT
  if Pnt.F1.Fo > 0 then
    begin
    Fec := Max(XF1, Fc / Pnt.F1.Fo);
    Fec := Fec * Ln((Fec + 1) / (Fec - 1));
    Zn := Pnt.ZenMax - DELZ;

    if Pnt.ZenAngle <= Zn
      //if ZenAngle is below ZenMax-DELZ (daytime)
      then
        Rft := 0.5 * Pnt.F1.Ym * (Fec - 2)

      //if ZenAngle within ZenMax-DELZ..ZenMax (twilight)
      else
        begin
        //NEAR DAY-NIGHT,CORRECT HI(2,II) AND RETARDATION.
        //FORCE F1 UP INTO F2 AND RETARDATION TO ZERO FROM ZN TO ZMAX
        Sz := (Pnt.ZenAngle - Zn) / DELZ;
        Hn := 165 + 0.6428/RinD * Zn;
        Yn := Hn * Pnt.F1.Ym / Pnt.F1.Hm;
        Rft := 0.5 * Yn * (Fec - 2) * (1 - Sz);

        //F2 WITHOUT F1
        Hm := Pnt.Hpf2 - Result;
        Ym := Hm / Pnt.Rat;
        dH := (Hm - Ym) - (Hn - Yn);

        if dH > 0 then
          begin
          //BOTTOM OF F1 GOES TO BOTTOM OF F2
          dH := dH * (1 - Sz);
          Pnt.F1.Hm := (Hm - Ym) - dH + Pnt.F1.Ym;

          if Pnt.F1.Fo > Fc then
            begin
            //F1 IS ALSO CLOSE TO F2 IN FREQUENCY, FORCE F1 YM TO F2 YM
            Y1Max := Yn + (Ym - Yn) * (Pnt.F1.Fo / Pnt.F2.Fo - 0.834) / 0.166;
            Pnt.F1.Ym := Yn + (Y1Max - Yn) * Sz;
            Pnt.F1.Hm := (Hm - Ym) - dH + Pnt.F1.Ym;
            end;
          end;
        end;

    Result := Result + Rft;
    end;
end;


procedure ComputeIonoParams(var Pnt: TControlPoint; Map: TFourierMaps);
const
  PSC4 = 0.7;
  BETAE = 5.5;
  BETAF1 = 4.0;
  DELZ = 2 * RinD;
  XF1 = 1.1;
var
  Gm, Z: Single;
  V: Single;
begin
  //E layer
  V := Map.ComputeVarMap(vmEr, Pnt.Loc.Lat, Pnt.EastLon, Cos(Pnt.Loc.Lat));
  if V < 0.36 then V := 0.36 * Sqrt(1 + 0.0098 * Map.Ssn);
  Pnt.E.Fo := V;
  Pnt.E.Hm := 110;
  Pnt.E.Ym := 110 / BETAE;
  //never used, overwritten in SIGDIS
  Pnt.Absorp := -0.04 * Exp(-2.937 + 0.8445 * Pnt.E.Fo);


  //F1 layer
  Pnt.ZenMax := Map.ComputeZenMax(Pnt.MagDip);
  if Pnt.ZenAngle <= Pnt.ZenMax
    then
      begin
      Pnt.F1.Fo := Map.ComputeFoF1(Pnt.ZenAngle);
      Pnt.F1.Hm := 165 + 0.6428/RinD * Pnt.ZenAngle;
      Pnt.F1.Ym := Pnt.F1.Hm / BETAF1;
      end
    else
      Pnt.F1.Fo := 0;


  //F2 layer
  Gm := Abs(Pnt.MagLat) - 0.25 * Pi;
  Z := Pnt.ZenAngle * Sign(Pnt.LocalTime - 0.5) + Pi;
  Pnt.Rat := Max(2, Map.ComputeFixedMap(fmYmF2, Gm, Z));
  Pnt.F2M3 := Map.ComputeVarMap(vmFm3, Pnt.MagDip, Pnt.EastLon, Cos(Pnt.Loc.Lat));
  Pnt.HpF2 := 1490 / Pnt.F2M3 - 176;

  Pnt.F2.Fo := Map.ComputeVarMap(vmF2, Pnt.MagDip, Pnt.EastLon, Cos(Pnt.Loc.Lat));
  Pnt.F2.Fo := Pnt.F2.Fo + 0.5 * Pnt.GyroFreq;
  Pnt.F1.Fo := Min(Pnt.F1.Fo, Pnt.F2.Fo - 0.2); //F1 MUST BE LESS THAN F2

  Pnt.F2.Hm := Pnt.Hpf2 - ComputeF2Retardation(Pnt);
  Pnt.F2.Ym := Pnt.F2.Hm / Pnt.Rat;


  //Es layer
  Pnt.Es.Fo   := Map.ComputeVarMap(vmEsM, Pnt.MagDip, Pnt.EastLon, Cos(Pnt.Loc.Lat)) * PSC4;
  Pnt.EsFo_Lo := Map.ComputeVarMap(vmEsL, Pnt.MagDip, Pnt.EastLon, Cos(Pnt.Loc.Lat)) * PSC4;
  Pnt.EsFo_Hi := Map.ComputeVarMap(vmEsU, Pnt.MagDip, Pnt.EastLon, Cos(Pnt.Loc.Lat)) * PSC4;
  Pnt.Es.Hm := 110; 
end;



end.

