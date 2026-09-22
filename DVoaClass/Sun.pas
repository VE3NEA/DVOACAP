//------------------------------------------------------------------------------
//DVOACAP - an HF propagation prediction engine based on the VOACAP algorithms.
//
//Copyright (C) 2013-2025 Alex Shovkoplyas, VE3NEA.
//
//This file is distributed under the MIT License. See the LICENSE file in the
//project root for the full license text.
//------------------------------------------------------------------------------
unit Sun;

interface

uses
  SysUtils, Math, VoaTypes;


function ComputeZenithAngle(P: TGeoPoint; AUtc: TDateTime; AMonth: TMonth): Single;
function ComputeLocalTime(AUtc: TDateTime; ALon: Single): TDateTime;




implementation

const
  SunLat: array[TMonth, boolean] of Single = (
    (-23.05 * RinD, -17.31 * RinD),
    (-17.30 * RinD,  -7.89 * RinD),
    ( -7.88 * RinD,   4.21 * RinD),
    (  4.26 * RinD,   14.8 * RinD),
    ( 14.84 * RinD,  21.93 * RinD),
    ( 21.93 * RinD,  23.45 * RinD),
    ( 23.15 * RinD,  18.23 * RinD),
    ( 18.20 * RinD,   8.68 * RinD),
    (  8.55 * RinD,  -2.86 * RinD),
    ( -2.90 * RinD, -14.16 * RinD),
    (-14.20 * RinD, -21.68 * RinD),
    (-21.66 * RinD, -23.45 * RinD));


function ComputeZenithAngle(P: TGeoPoint; AUtc: TDateTime; AMonth: TMonth): Single;
var
  Sun: TGeoPoint;
begin
  //sub-solar point
  Sun.Lon := Pi - AUtc * TWO_PI;

  if Abs(P.Lat - SunLat[AMonth, false]) > Abs(P.Lat - SunLat[AMonth, true])
    then Sun.Lat := SunLat[AMonth, false]
    else Sun.Lat := SunLat[AMonth, true];

  Result := Sin(P.Lat) * Sin(Sun.Lat) + Cos(P.Lat) * Cos(Sun.Lat) * Cos(P.Lon - Sun.Lon);
  Result := ArcCos(Result);
end;


function ComputeLocalTime(AUtc: TDateTime; ALon: Single): TDateTime;
begin
  Result := Frac(AUtc + 1 + ALon / TWO_PI);

  //voacap uses hours from 1h to 24h; 0h is never used
  if Result < 1e-4 then Result := 1;
end;



end.

