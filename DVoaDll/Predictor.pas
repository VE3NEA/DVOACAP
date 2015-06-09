//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is Predictor.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit Predictor;

interface

uses
  SysUtils, VoaTypes, IoFmt, VoaCapEng;


type
  //this is a simple wrapper around the TVoaCapEngine class that receives
  //input parameters ang argument in the TVoaRequest structure
  //and returns results in TVoaReply.
  //A more sophisticated wrapper would create multiple instances of TVoaCapEngine
  //and use them on different threads to take advantage of multi-core CPU
  TPropagationPredictor = class
  public
    Eng: TVoacapEngine;
    constructor Create;
    destructor Destroy; override;
    function Predict(ARequest: TVoaRequest): TVoaReply;
  end;


var
  PrPr: TPropagationPredictor;




implementation

{ TPropagationPredictor }

constructor TPropagationPredictor.Create;
begin
  Eng := TVoacapEngine.Create;
end;


destructor TPropagationPredictor.Destroy;
begin
  Eng.Free;
  inherited;
end;


//iterate over rx locations and hours, compute prediction for each combination
function TPropagationPredictor.Predict(ARequest: TVoaRequest): TVoaReply;
var
  i, j: integer;
begin
  Eng.Pm := ARequest.Params;
  Eng.Freqs := ARequest.Args.Freqs;

  Result := nil;
  SetLength(Result, Length(ARequest.Args.RxLocations), Length(ARequest.Args.Hours));
  for i:=0 to High(Result) do
    begin
    Eng.RxLoc := ARequest.Args.RxLocations[i];
    for j:=0 to High(Result[i]) do
      begin
      if ARequest.Args.IncludeMuf then Eng.Freqs[High(Eng.Freqs)] := 0; //clear old MUF
      Eng.UtcTime := ARequest.Args.Hours[j];
      Eng.Predict;
      Result[i,j].Predictions := Copy(Eng.Results);
      Result[i,j].Muf := Eng.FMufCalc.Muf;
      Result[i,j].Dist := Eng.FPath.Dist;
      end;
    end;
end;



initialization
  PrPr := TPropagationPredictor.Create;

finalization
  PrPr.Free;



end.

