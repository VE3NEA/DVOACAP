//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is Sun.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
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

