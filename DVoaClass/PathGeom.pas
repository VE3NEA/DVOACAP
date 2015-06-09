//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is PathGeom.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit PathGeom;

interface

uses
  SysUtils, VoaTypes, Math;


type
  TPathGeometry = class
  protected
    FTx: TGeoPoint;
    FRx: TGeoPoint;
    FDist: Single;
    FAzimTR: Single;
    FAzimRT: Single;
    dLon: Single;
  public
    LongPath: boolean;

    procedure SetTxRx(ATx, ARx: TGeoPoint);
    function GetPointAtDist(ADist: Single): TGeoPoint;
    function HopCount(Elev, Height: Single): integer;

    property Rx: TGeoPoint read FRx;
    property Tx: TGeoPoint read FTx;
    property AzimTR: Single read FAzimTR;
    property AzimRT: Single read FAzimRT;
    property Dist: Single read FDist;
  end;


function CalcElevationAngle(HopDist, Height: Single): Single;
function HopDistance(Elev, Height: Single): Single{rad};
function SinOfIncidence(Elev, Height: Single): Single;
function CosOfIncidence(Elev, Height: Single): Single;
function HopLength3D(Elev, HopDist, VirtHeight: Single): Single;




implementation

{ TPathGeometry }

//------------------------------------------------------------------------------
//                               2D path
//------------------------------------------------------------------------------
procedure TPathGeometry.SetTxRx(ATx, ARx: TGeoPoint);
var
  QCos: Single;
begin
  FTx := ATx;
  FRx := ARx;

  //move Rx away from Tx a little bit
  if Max(Abs(Rx.Lat - Tx.Lat), Abs(Rx.Lon - Tx.Lon)) <= MIN_RXTX_DIST
    then FRx.Lat := Rx.Lat - Sign(Rx.Lat) * MIN_RXTX_DIST;

  //at poles, force long=0
  if Abs(Rx.Lat) > MAX_NON_POLE_LAT then FRx.Lon := 0;
  if Abs(Tx.Lat) > MAX_NON_POLE_LAT then FTx.Lon := 0;

  //longitude diff
  dLon := Tx.Lon - Rx.Lon;
  if Abs(dLon) > Pi then dLon := dLon - Sign(dLon) * TWO_PI;
  if LongPath then dLon := dLon - Sign(dLon) * TWO_PI;

  //GC distance
  QCos := Sin(Tx.Lat) * Sin(Rx.Lat) + Cos(Tx.Lat) * Cos(Rx.Lat) * Cos(dLon);
  if Abs(QCos)> 1 then QCos := Sign (QCos);
  FDist := Max(MIN_RXTX_DIST2, ArcCos(QCos));
  if LongPath then FDist := TWO_PI - Dist;

  //azimuth T->R
  if Cos(Tx.Lat) <= MIN_NON_POLE_COSLAT
    then
      if Tx.Lat <= 0 then FAzimTR := 0 else FAzimTR := Pi
    else
      begin
      QCos := (Sin(Rx.Lat) - Sin(Tx.Lat) * Cos(Dist)) / (Cos(Tx.Lat) * Sin(Dist));
      if Abs(QCos)> 1 then QCos := Sign (QCos);
      FAzimTR := ArcCos(QCos);
      end;
  if dLon > 0 then FAzimTR := TWO_PI - FAzimTR;

  //azimuth R->T
  if Cos(Rx.Lat) <= MIN_NON_POLE_COSLAT
    then
      if Rx.Lat <= 0 then FAzimRT := 0 else FAzimRT := Pi
    else
      begin
      QCos := (Sin(Tx.Lat) - Sin(Rx.Lat) * Cos(Dist)) / (Cos(Rx.Lat) * Sin(Dist));
      if Abs(QCos)> 1 then QCos := Sign (QCos);
      FAzimRT := ArcCos(QCos);
      end;

  if dLon < 0 then FAzimRT := TWO_PI - FAzimRT;
end;


function TPathGeometry.GetPointAtDist(ADist: Single): TGeoPoint;
var
  QCos: Single;
begin
  if Cos(Tx.Lat) < MIN_NON_POLE_COSLAT then //if TX near pole
    begin
    Result.Lat := Tx.Lat - Sign(Tx.Lat) * Abs(ADist);
    if Abs(Result.Lat) > HALF_PI then Result.Lat := Sign(Result.Lat) * HALF_PI;
    Result.Lon := Rx.Lon;
    Exit;
    end;

  //RX Lat
  QCos := Cos(ADist) * Sin(Tx.Lat) + Sin(ADist) * Cos(Tx.Lat) * Cos(AzimTR);
  if Abs(QCos)> 1 then QCos := Sign (QCos);
  Result.Lat := HALF_PI - ArcCos(QCos);

  //RX Lon
  if Cos(Result.Lat) <= MIN_NON_POLE_COSLAT then //if RX near pole
    begin Result.Lon := Tx.Lon; Exit; end;
  QCos := (Cos(ADist) - Sin(Result.Lat) * Sin(Tx.Lat)) / (Cos(Result.Lat) * Cos(Tx.Lat));
  if Abs(QCos)> 1 then QCos := Sign (QCos);
  Result.Lon := ArcCos(QCos);
  if ADist > Pi then Result.Lon := TWO_PI - Result.Lon;
  Result.Lon := Tx.Lon - Sign(dLon) * Abs(Result.Lon);
  if Abs(Result.Lon) > Pi then Result.Lon := Result.Lon - Sign(Result.Lon) * TWO_PI;
end;






//------------------------------------------------------------------------------
//                               3D path
//------------------------------------------------------------------------------
function HopDistance(Elev, Height: Single): Single{rad};
begin
  Result := Cos(Elev) * EarthR / (EarthR + Height);
  Result := 2 * (ArcCos(Result) - Elev);
end;


function HopLength3D(Elev, HopDist, VirtHeight: Single): Single;
begin
  Result := 2 * (VirtHeight + EarthR * (1 - Cos(0.5 * HopDist))) / Sin(0.5 * HopDist + Elev);
end;


function TPathGeometry.HopCount(Elev, Height: Single): integer;
begin
  Result := 1 + Trunc(Dist / HopDistance(Elev, Height));
end;


function CalcElevationAngle(HopDist, Height: Single): Single;
var
  Half: Single;
begin
  Half := 0.5 * HopDist;
  Result := (Cos(Half) - EarthR/(EarthR + Height) ) / Sin(Half);
  Result := ArcTan(Result);
end;


function SinOfIncidence(Elev, Height: Single): Single;
begin
  Result := EarthR * Cos(Elev) / (EarthR + Height);
end;


function CosOfIncidence(Elev, Height: Single): Single;
begin
  Result := SinOfIncidence(Elev, Height);
  Result := Sqrt(Max(1e-6, 1 - Sqr(Result)));
end;



end.

