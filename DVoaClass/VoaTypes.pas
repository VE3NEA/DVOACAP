//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is VoaTypes.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit VoaTypes;

interface

uses
  SysUtils, Math, TypInfo;

  
const
  TWO_PI = 2 * Pi;
  HALF_PI = Pi / 2;
  RinD = Pi / 180;      //radians in degree
  DinR = 1 / RinD;      //degrees in radian
  EarthR = 6370;        //radius of the Earth in km
  VofL = 299.79246;     //velocity of light
  DBinNP = 4.34294;     //dB's in Neper, 10/Ln(10)
  NPinDB = 1 / DBinNP;  //Nepers in dB

  MIN_RXTX_DIST = 0.03 * RinD;    //min distance between tx and rx, radians
  MIN_RXTX_DIST2 = 0.000001;
  MAX_NON_POLE_LAT = 89.9 * RinD; //if higher lat, it is a pole
  MIN_NON_POLE_COSLAT = 1e-7;

  MAX_ELEV_ANGLE = 89.99 * RinD;
  JUST_BELOW_MAX_ELEV = 89.9 * RinD;

  //common GC distances, in radians
  Rad_1000Km = 1000 / EarthR;
  Rad_2000Km = 2000 / EarthR;
  Rad_2000Km_01 = 2000.01 / EarthR;
  Rad_2500Km = 2500 / EarthR;
  Rad_4000Km = 4000 / EarthR;
  Rad_7000Km = 7000 / EarthR;
  Rad_10000Km = 10000 / EarthR;


  //Percentage Points of the Normal Distribution
  TME: array[0..9] of Single = (
  //50%   45%     40%     35%     30%     25%     20%     15%     10%      5%
    0, 0.1257, 0.2533, 0.3853, 0.5244, 0.6745, 0.8416, 1.0364, 1.2815, 1.6449);


  //= TME[10%] in the table above
  NORM_DECILE = 1.28; //x ~ N(0,1)  =>  P(x > 1.28) = 10%


  //ANG(40)
  Angles: array[1..40] of Single = (
     0 * RinD, 0.5 * RinD,  1 * RinD,  2 * RinD,  3 * RinD,  4 * RinD,
     5 * RinD,   6 * RinD,  8 * RinD, 10 * RinD, 12 * RinD, 14 * RinD,
    16 * RinD,  18 * RinD, 20 * RinD, 22 * RinD, 24 * RinD, 26 * RinD,
    28 * RinD,  30 * RinD, 32 * RinD, 34 * RinD, 36 * RinD, 38 * RinD,
    40 * RinD,  42 * RinD, 44 * RinD, 46 * RinD, 48 * RinD, 50 * RinD,
    52 * RinD,  54 * RinD, 56 * RinD, 60 * RinD, 65 * RinD, 70 * RinD,
    75 * RinD,  80 * RinD, 85 * RinD, MAX_ELEV_ANGLE);


  //Gaussian integration weights
  TWDIV = 1/2;

  XT: array[0..19] of Single = (
    0.0387724175, 0.1160840707, 0.1926975807, 0.2681521850,
    0.3419940908, 0.4137792043, 0.4830758017, 0.5494671251,
    0.6125538897, 0.6719566846, 0.7273182552, 0.7783056514,
    0.8246122308, 0.8659595032, 0.9020988070, 0.9328128083,
    0.9579168192, 0.9772599500, 0.9907262387, 0.9982377097);

  WT: array[0..19] of Single = (
    0.0775059480, 0.0770398182, 0.0761103619, 0.0747231691,
    0.0728865824, 0.0706116474, 0.0679120458, 0.0648040135,
    0.0613062425, 0.0574397691, 0.0532278470, 0.0486958076,
    0.0438709082, 0.0387821680, 0.0334601953, 0.0279370070,
    0.0222458492, 0.0164210584, 0.0104982845, 0.0045212771);


  //defined in SIGDIS.FOR
  HTLOSS = 88.0;
  XNUZ = 63.07;
  HNU  = 4.39;


type
  TMonth = 1..12;


  TSingleArray = array of Single;
  TSingleArray2D = array of TSingleArray;


  TGeoPoint = record Lat, Lon: Single; end;

  PLayerInfo = ^TLayerInfo;
  TLayerInfo = record
    Fo, Hm, Ym: Single;
    end;


  TIonoLayerEx = (lrE, lrF1, lrF2, lrEs);
  TIonoLayer = lrE..lrF2;

  TMethod = (mdShort, mdLong, mdSmooth);


  TLayerParamArray = array[TIonoLayer] of Single;


  PControlPoint = ^TControlPoint;
  TControlPoint = record
    //location
    Loc: TGeoPoint;
    EastLon: Single;
    DistanceRad: Single;
    LocalTime: TDateTime;
    ZenAngle: Single;
    ZenMax: Single;

    //geophys
    MagLat: Single;
    GyroFreq: Single;
    MagDip: Single;
    GndSig: Single;
    GndEps: Single;

    //iono
    E, F1, F2, Es: TLayerInfo;
    EsFo_Lo, EsFo_Hi: Single;
    Absorp: Single;
    F2M3: Single;
    HpF2: Single;
    Rat: Single;
    end;


  TTripleValue = record
    Mdn, Lo, Hi: Single;
    end;


  TDistribution = record
    Value, Error: TTripleValue;
    end;
    

  TReflection = record
    Elevation: Single;  //rad
    TrueHeight: Single; //km
    VirtHeight: Single; //km
    VertFreq: Single;   //MHz
    DevLoss: Single;    // AFFLX, AFAC
    end;


  PMufInfo = ^TMufInfo;
  TMufInfo = record
    Ref: TReflection;
    HopCount: integer;
    Fot, Hpf, Muf: Single;
    SigLo, SigHi: Single;
    end;

  TMufInfoArray = array[TIonoLayer] of TMufInfo;


  TSignalInfo = record
    Delay_ms: Single;
    TxGain_dB: Single;
    RxGain_dB: Single;
    MufDay: Single;
    TotalLoss_dB: Single;
    Power10: Single;
    Power90: Single;
    Field_dBuV: Single; //dB over microvolt per meter
    Power_dBW: Single;
    Snr_dB: Single;
    Snr10: Single;
    Snr90: Single;         
    Reliability: Single;
    end;



  PModeInfo = ^TModeInfo;
  TModeInfo = record
    Ref: TReflection;
    Sig: TSignalInfo;

    HopDist: Single;
    HopCnt: integer;
    Layer: TIonoLayer;

    FreeSpaceLoss: Single;
    AbsorptionLoss: Single;
    Obscuration: Single;
    DeviationTerm: Single;
    GroundLoss: Single;
    end;

  TModeInfoArray = array of TModeInfo;


  TPredictedParam = (pmMODE, pmTANGLE, pmRANGLE, pmDELAY, pmV_HITE, pmMUFDAY,
    pmLOSS, pmDBU, pmS_DBW, pmN_DBW, pmSNR, pmRPWRG, pmREL, pmMPROB, pmSPRB,
    pmSIG_LW, pmSIG_UP, pmSNR_LW, pmSNR_UP, pmTGAIN, pmRGAIN, pmSNRXX);

  TPredictedParams = set of TPredictedParam;

const
  AllPredictedParams = [pmMODE..pmSNRXX];

type
  TVoaParams = record
    Ssn: Single;
    Month: TMonth;
    TxLoc: TGeoPoint;
    TxPower: Single;
    TxLabel: string;
    MinAngle: Single;
    ManMadeNoiseAt3MHz: Single;
    LongPath: boolean;
    RequiredSnr: Single;
    RequiredReliability: Single;
    MultipathPowerTolerance: Single;
    MaxTolerableDelay: Single;
  end;


  TPrediction = record
    //mode
    Method: TMethod;
    ModeT, ModeR: TIonoLayer;
    HopCnt: integer;

    //path params
    TxElevation, RxElevation: Single;   //radians
    VirtHeight: Single;                 //meters

    //signal
    Sig: TSignalInfo;

    //performance
    Noise_dBW: Single;       //Noise, dBW
    RequiredPower: Single;  //Pwr required for specified reliability
    MultiPathProb: Single;  //0..1  PROBMP[]
    ServiceProb: Single;    //0..1
    SnrXX: Single;          //SNR percentile at xx%

    function GetParamStr(APm: TPredictedParam): string; inline;
    end;

  TPredictions = array of TPrediction;


const
  DefaultVoaParams: TVoaParams = (
    Ssn: 100;
    Month: 1;
    TxLoc: (Lat:0;Lon:0);
    TxPower: 1500;
    TxLabel: '';
    MinAngle: 3 * RinD;
    ManMadeNoiseAt3MHz: 145;
    LongPath: false;
    RequiredSnr: 73;
    RequiredReliability: 0.9;
    MultipathPowerTolerance: 3;
    MaxTolerableDelay: 0.1;
    );



function Sign(X: Single): Single;
function ToDb(X: Single): Single;
function FromDb(X: Single): Single;
function CumulativeNormal(x: Double): Double;
function GetLayerName(ALayer: TIonoLayer): string;
function GetModeName(Prediction: TPrediction; ADist: Single): string;




implementation

function Sign(X: Single): Single;
begin
  {if X = 0 then Result := 0
  else} if X >= 0 then Result := 1
  else Result := -1;
end;


function ToDb(X: Single): Single;
begin
  Result := 10 * Log10(x);
end;


function FromDb(X: Single): Single;
begin
  if X > 375 then Result := 3e37 else Result := Power(10, 0.1 * X);
end;


function CumulativeNormal(x: Double): Double;
const
  C: array[1..4] of Single = (0.196854, 0.115194, 0.000344, 0.019527);
var
  y: Single;
begin
   y := Min(5, Abs(x));
   Result := 1 + y * (C[1] + y * (C[2] + y * (C[3] + y * C[4])));
   Result := Result * Result * Result * Result;
   Result := 0.5 * (1 / Result);
   if x > 0 then Result := 1 - Result;
end;


function GetLayerName(ALayer: TIonoLayer): string;
begin
  Result := Copy(GetEnumName(TypeInfo(TIonoLayer), Ord(ALayer)), 3, MAXINT);
end;


function GetModeName(Prediction: TPrediction; ADist: Single): string;
begin
  if ADist < Rad_7000Km
    then Result := IntToStr(Prediction.HopCnt) + GetLayerName(Prediction.ModeT)
    else Result := GetLayerName(Prediction.ModeT) + GetLayerName(Prediction.ModeR);
end;

{ TPrediction }

function TPrediction.GetParamStr(APm: TPredictedParam): string;
begin
  case APm of
    pmTANGLE: Result := Format('%.1f', [TxElevation * DinR]);
    pmRANGLE: Result := Format('%.1f', [RxElevation * DinR]);
    pmDELAY:  Result := Format('%.1f', [Sig.Delay_ms]);
    pmV_HITE: Result := Format('%.0f', [VirtHeight]);
    pmMUFDAY: Result := Format('%.2f', [Sig.MufDay]);
    pmLOSS:   Result := Format('%.0f', [Sig.TotalLoss_dB]);
    pmDBU:    Result := Format('%.0f', [Sig.Field_dBuV]);
    pmS_DBW:  Result := Format('%.0f', [Sig.Power_dBW]);
    pmN_DBW:  Result := Format('%.0f', [Noise_dBW]);
    pmSNR:    Result := Format('%.0f', [Sig.Snr_dB]);
    pmRPWRG:  Result := Format('%.0f', [RequiredPower]);
    pmREL:    Result := Format('%.2f', [Sig.Reliability]);
    pmMPROB:  Result := Format('%.2f', [MultiPathProb]);
    pmSPRB:   Result := Format('%.2f', [ServiceProb]);
    pmSIG_LW: Result := Format('%.1f', [Sig.Power10]);
    pmSIG_UP: Result := Format('%.1f', [Sig.Power90]);
    pmSNR_LW: Result := Format('%.1f', [Sig.Snr10]);
    pmSNR_UP: Result := Format('%.1f', [Sig.Snr90]);
    pmTGAIN:  Result := Format('%.1f', [Sig.TxGain_dB]);
    pmRGAIN:  Result := Format('%.1f', [Sig.RxGain_dB]);
    pmSNRXX:  Result := Format('%.0f', [SnrXX]);
  end;
end;



end.

