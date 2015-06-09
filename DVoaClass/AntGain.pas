//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is AntGain.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
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
