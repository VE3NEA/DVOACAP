//------------------------------------------------------------------------------
//DVOACAP - an HF propagation prediction engine based on the VOACAP algorithms.
//
//Copyright (C) 2013-2025 Alex Shovkoplyas, VE3NEA.
//
//This file is distributed under the MIT License. See the LICENSE file in the
//project root for the full license text.
//------------------------------------------------------------------------------
unit AntGain;

interface

uses
  SysUtils;


type
  TAntennaModel = class
  private
    FFrequency: Single;
    FAzimuth: Single;
    FLowFrequency: Single;
    FHighFrequency: Single;
  protected
    procedure SetAzimuth(const Value: Single); virtual;
    procedure SetFrequency(const Value: Single); virtual;
  public
    //extra gain added to result
    ExtraGain_dB: Single;
    TxPower_dBW: Single;

    function GetGainDb(AElev: Single): Single; virtual;

    //freq range of ant, read only
    property LowFrequency: Single read FLowFrequency;
    property HighFrequency: Single read FHighFrequency;

    //current values, user sets before calling GetGainDb
    property Frequency: Single read FFrequency write SetFrequency;
    property Azimuth: Single read FAzimuth write SetAzimuth;
  end;


  TIsotropicAntenna = class(TAntennaModel)
  public
    constructor Create;
  end;


  TAntennaFarm = class
  private
    FIsotropicAntenna: TIsotropicAntenna;
    FCurrentAntenna: TAntennaModel;
  public
    FAnts: array of TAntennaModel;

    constructor Create;
    destructor Destroy; override;

    //selects antenna for this frequency, set antenna's frequency
    procedure SelectAntenna(AFreq: Single);
    //antenna selected by frequency
    property CurrentAntenna: TAntennaModel read FCurrentAntenna;
  end;




implementation

{ TAntennaModel }

procedure TAntennaModel.SetAzimuth(const Value: Single);
begin
  FAzimuth := Value;
end;


procedure TAntennaModel.SetFrequency(const Value: Single);
begin
  Assert(Value >= LowFrequency);
  Assert(Value <= HighFrequency);
  FFrequency := Value;
end;


function TAntennaModel.GetGainDb(AElev: Single): Single;
begin
  Result := ExtraGain_dB;
end;




{ TOmniDirAntenna }

constructor TIsotropicAntenna.Create;
begin
  FLowFrequency := 0;
  FHighFrequency := MAXINT;
  TxPower_dBW := 1;
end;




{ TAntennaFarm }

constructor TAntennaFarm.Create;
begin
  FIsotropicAntenna := TIsotropicAntenna.Create;
  FCurrentAntenna := FIsotropicAntenna;
end;


destructor TAntennaFarm.Destroy;
begin
  FIsotropicAntenna.Free;
  inherited;
end;


procedure TAntennaFarm.SelectAntenna(AFreq: Single);
var
  i: integer;
begin
  for i:=0 to High(FAnts) do
    if (AFreq >= FAnts[i].FLowFrequency) and (AFreq <= FAnts[i].FHighFrequency)
      then begin FCurrentAntenna := FAnts[i]; Exit; end;

  //no ant found for this freq, use omnidirectional
  FCurrentAntenna := FIsotropicAntenna;
end;



end.
