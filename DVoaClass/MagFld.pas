//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is MagFld.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit MagFld;

interface

uses
  SysUtils, Math, VoaTypes, SinCos;


const
  //geomagnetic North Pole
  MagPole: TGeoPoint = (Lat: 79.5 * RinD; Lon: -69.0 * RinD);


type
  TGeoMagneticField = class
  private
    MSin, MCos: Single;
    P, DP: array[0..6,0..6] of Single;
    X, Y, Z: Single;

    procedure ComputeXYZ(const Pnt: TControlPoint);
  public
    constructor Create;
    procedure Compute(var Pnt: TControlPoint);
  end;



implementation

{ TGeoMagneticField }


constructor TGeoMagneticField.Create;
begin
  MSin := Sin(MagPole.Lat);
  MCos := Cos(MagPole.Lat);
end;


procedure TGeoMagneticField.Compute(var Pnt: TControlPoint);
var
  QCos, Gob: Single;
  Mag2, Mag3: Single;
begin
  //field vertor
  ComputeXYZ(Pnt);
  Mag2 := Sqrt(Sqr(X) + Sqr(Y));
  Mag3 := Sqrt(Sqr(X) + Sqr(Y) + Sqr(Z));

  //magnetic latitude
  QCos := MSin * Sin(Pnt.Loc.Lat) + MCos * Cos(Pnt.Loc.Lat) * Cos(Pnt.Loc.Lon - MagPole.Lon);
  if Abs(QCos)> 1 then QCos := Sign(QCos);
  Pnt.MagLat := HALF_PI - ArcCos(QCos);

  //gyrofrequency
  Pnt.GyroFreq := 2.8 * Mag3;
  //1.358

  //modified magnetic dip
  Gob := Max(0.000001, Cos(Pnt.Loc.Lat));
  Pnt.MagDip := ArcTan(ArcTan(-Z / Mag2) / Sqrt(Gob));
end;






//------------------------------------------------------------------------------
//                        MAGNETIC FIELD VECTOR
//------------------------------------------------------------------------------
const
  CT: array[0..6,0..6] of Single = (
    (0,          0,          0,          0,          0,          0,          0),
    (0,          0,          0,          0,          0,          0,          0),
    (0.33333333, 0,          0,          0,          0,          0,          0),
    (0.26666667, 0.2,        0,          0,          0,          0,          0),
    (0.25714286, 0.22857142, 0.14285714, 0,          0,          0,          0),
    (0.25396825, 0.23809523, 0.19047619, 0.11111111, 0,          0,          0),
    (0.25252525, 0.24242424, 0.21212121, 0.16161616, 0.09090909, 0,          0));

  G: array[0..6,0..6] of Single = (
    ( 0,          0,         0,         0,         0,          0,        0),
    ( 0.304112,   0.021474,  0,         0,         0,          0,        0),
    ( 0.024035,  -0.051253, -0.013381,  0,         0,          0,        0),
    (-0.031518,   0.062130, -0.024898, -0.006496,  0,          0,        0),
    (-0.041794,  -0.045298, -0.021795,  0.007008, -0.002044,   0,        0),
    ( 0.016256,  -0.034407, -0.019447, -0.000608,  0.002775,   0.000697, 0),
    (-0.019523,  -0.004853,  0.003212,  0.021413,  0.001051,   0.000227, 0.001115));

  H: array[0..6,0..6] of Single = (
    (0,  0.0,        0,          0,          0,          0,         0),
    (0, -0.057989,   0,          0,          0,          0,         0),
    (0,  0.033124,  -0.001579,   0,          0,          0,         0),
    (0,  0.014870,  -0.004075,   0.00021,    0,          0,         0),
    (0, -0.011825,   0.010006,   0.00043,    0.001385,   0,         0),
    (0, -0.000796,  -0.002,      0.004597,   0.002421,  -0.001218,  0),
    (0, -0.005758,  -0.008735,  -0.003406,  -0.000118,  -0.001116, -0.000325));


procedure TGeoMagneticField.ComputeXYZ(const Pnt: TControlPoint);
const
  EarthR = 6371200; //meters
  Height = 300000;  //meters
  AR = EarthR / (EarthR + Height);
var
  Lat, Lon: Single;
  W: TSinCosArray;
  S, C, SumZ, SumY, SumX, Temp, PwrAR: Single;
  n, m: integer;
begin
  //avoid poles where Cos(Lat) = 0;
  if Pnt.Loc.Lat > MAX_NON_POLE_LAT then
    begin
    Lat := MAX_NON_POLE_LAT;
    Lon := 0;
    end
  else if Pnt.Loc.Lat < -MAX_NON_POLE_LAT then
    begin
    Lat := -MAX_NON_POLE_LAT;
    Lon := 0;
    end
  else
    begin
    Lat := Pnt.Loc.Lat;
    Lon := Pnt.EastLon;
    end;

  //sin & cos
  C := Sin(Lat);
  S := Cos(Lat);
  W := MakeSinCosArray(Lon, 7);

  //init
  PwrAR := Sqr(AR);
  P[0,0] := 1;
  DP[0,0] := 0;
  Z := 0; Y := 0; X := 0;

  for n:=1 to 6 do
    begin
    SumZ := 0; SumY := 0; SumX := 0;

    for m:=0 to n do
      begin
      if m = n then
        begin
        P[n,n] := S * P[n-1,n-1];
        DP[n,n] := S * DP[n-1,n-1] + C * P[n-1,n-1];
        end
      else if n = 1 then
        begin
        P[1,0] := C;
        DP[1,0] := -S;
        end
      else
        begin
        P[N,M] := C * P[N-1,M] - CT[n,m] * P[N-2,M];
        DP [N, M] := C * DP[N-1, M] - S * P[N-1, M] - CT[n,m] * DP[N-2, M];
        end;

      Temp := G[n,m] * W[m].Cs + H[n,m] * W[m].Sn;
      SumZ := SumZ + P [N, M] * Temp;
      SumY := SumY + DP [N, M] * Temp;
      SumX := SumX + m * P[N, M] * (-G[n,m] * W[m].Sn + H[n,m] * W[m].Cs);
      end;

    PwrAR := PwrAR * AR;
    Z := Z - PwrAR * (n+1) * SumZ;
    Y := Y - PwrAR * SumY;
    X := X + PwrAR * SumX;
    end;

  X := X / S;
end;



end.

