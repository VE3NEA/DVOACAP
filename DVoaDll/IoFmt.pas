//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is IoFmt.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit IoFmt;

interface

uses
  SysUtils, Classes, VoaTypes, superobject, Math, TypInfo;


type
  TVoaArguments = record
    RxLocations: array of TGeoPoint;
    RxLabels: array of string;
    Hours: array of TDateTime;
    Freqs: TSingleArray;
    IncludeMuf: boolean;
  end;


  TVoaOutFormat = (fmtXml, fmtJson, fmtCsv, fmtVoa);


  TVoaRequest = record
    Params: TVoaParams;
    Args: TVoaArguments;
    OutParams: set of TPredictedParam;
    OutFormat: TVoaOutFormat;
  end;


  TVoaReplyElement = record
    Predictions: TPredictions;
    Muf: Single;
    Dist: Single;
  end;
  TVoaReply = array of array of TVoaReplyElement;


function XmlToVoaRequest(AXml: AnsiString): TVoaRequest;
function JsonToVoaRequest(AJson: AnsiString): TVoaRequest;

function VoaReplyToXml(const AReply: TVoaReply; const ARequest: TVoaRequest): AnsiString;
function VoaReplyToJson(const AReply: TVoaReply; const ARequest: TVoaRequest): AnsiString;
function VoaReplyToCsv(const AReply: TVoaReply; const ARequest: TVoaRequest): AnsiString;
function VoaReplyToVoaTxt(const AReply: TVoaReply; const ARequest: TVoaRequest): AnsiString;




implementation

//------------------------------------------------------------------------------
//                          helper func
//------------------------------------------------------------------------------
function AzDistToLatLon(TxLoc: TGeoPoint; Azim, Dist: Single): TGeoPoint;
const
  SMALL_VALUE = 1E-5;
var
  Sn, Cs: Single;
begin
  Sn := Sin(TxLoc.Lat);
  Cs := Cos(TxLoc.Lat);

  Result.Lat := ArcSin(Sin(Dist) * Cs * Cos(Azim) + Cos(Dist) * Sn);
  //north pole
  if Abs(TxLoc.Lat - Pi/2) < SMALL_VALUE then Result.Lon := Pi - Azim
  //south pole
  else if Abs(TxLoc.Lat + Pi/2) < SMALL_VALUE then Result.Lon := Azim
  //in between
  else Result.Lon := ArcTan2(Sin(Azim) * Sin(Dist) * Cs, Cos(Dist) - Sn * Sin(Result.Lat));
  Result.Lon := Result.Lon + TxLoc.Lon;

  //keep in range
  if Result.Lon < -Pi then Result.Lon := Result.Lon + 2*Pi
  else if Result.Lon > Pi then Result.Lon := Result.Lon - 2*Pi;
  if Result.Lat > Pi/2 then Result.Lat := Pi/2
  else if Result.Lat < -Pi/2 then Result.Lat := -Pi/2;
end;






//------------------------------------------------------------------------------
//                          params from XML
//------------------------------------------------------------------------------
function XmlToVoaRequest(AXml: AnsiString): TVoaRequest;
begin
  //init result structure
  FillChar(Result, SizeOf(TVoaRequest), 0);
  Result.Params := DefaultVoaParams;

  //TODO

end;






//------------------------------------------------------------------------------
//                         params from JSON
//------------------------------------------------------------------------------
type
  TRangeInfo = record Start, Step: Single; Count: integer; end;


function JsonToVoaRequest(AJson: AnsiString): TVoaRequest;
var
  Ws: WideString;
  So, Pm: ISuperObject;
  i, j, k: integer;
  Arr1, Arr2: TSingleArray;

  function ExpandRange(So: ISuperObject; AFactor: Single): TSingleArray;
  var
    R: TRangeInfo; i: integer;
  begin
    R.Start := So.D['Start'] * AFactor;
    R.Step := So.D['Step'] * AFactor;
    R.Count := So.I['Count'];

    Result := nil; SetLength(Result, R.Count);
    for i:=0 to High(Result) do begin Result[i] := R.Start; R.Start := R.Start + R.Step; end;
  end;

begin
  //init result structure
  FillChar(Result, SizeOf(TVoaRequest), 0);
  Result.Params := DefaultVoaParams;

  //parse input string
  Ws := WideString(AJson);
  So := TSuperObject.ParseString(PWideChar(Ws), false);

  //extract params
  Pm := So['Params'];
  Result.Params.Ssn := Pm.D['Ssn'];
  Result.Params.Month := Pm.I['Month'];
  Result.Params.TxLoc.Lat := Pm['TxLoc'].D['Lat'] * RinD;
  Result.Params.TxLoc.Lon := Pm['TxLoc'].D['Lon'] * RinD;
  Result.Params.TxPower := Pm.D['TxPower'];
  Result.Params.TxLabel := Pm.S['Label'];
  Result.Params.MinAngle := Pm.D['MinAngle'] * RinD;
  Result.Params.ManMadeNoiseAt3MHz := Pm.D['ManMadeNoiseAt3MHz'];
  Result.Params.LongPath := Pm.B['LongPath'];
  Result.Params.RequiredSnr := Pm.D['RequiredSnr'];
  Result.Params.RequiredReliability := Pm.D['RequiredReliability'];
  Result.Params.MultipathPowerTolerance := Pm.D['MultipathPowerTolerance'];
  Result.Params.MaxTolerableDelay := Pm.D['MaxTolerableDelay'];

  //extract output parameter selection
  Result.OutParams := [];
  for Pm in So['Outputs'] do
    Include(Result.OutParams, TPredictedParam(GetEnumValue(TypeInfo(TPredictedParam), 'pm' + Pm.AsString)));
  if Result.OutParams = [] then Result.OutParams := AllPredictedParams;

  //extract output format
  Result.OutFormat := TVoaOutFormat(GetEnumValue(TypeInfo(TVoaOutFormat), 'fmt' + So.S['OutputFormat']));

  //extract RX locations
  k := 0;
  Pm := So['Arguments']['RxLocations'];
  if Pm['Lat'] <> nil then
    begin //lat/lon grid
    Arr1 := ExpandRange(Pm['Lat'], RinD);
    Arr2 := ExpandRange(Pm['Lon'], RinD);
    SetLength(Result.Args.RxLocations, Length(Arr1) * Length(Arr2));
    Result.Args.RxLabels := nil;
    for i:=0 to High(Arr1) do
      for j:=0 to High(Arr2) do
        begin
        Result.Args.RxLocations[k].Lat := Arr1[i];
        Result.Args.RxLocations[k].Lon := Arr2[j];
        Inc(k);
        end;
    end
  else if Pm['Azim'] <> nil then
    begin //azim/dist grid
    Arr1 := ExpandRange(Pm['Azim'], RinD);
    Arr2 := ExpandRange(Pm['Dist'], RinD);
    SetLength(Result.Args.RxLocations, Length(Arr1) * Length(Arr2));
    Result.Args.RxLabels := nil;
    for i:=0 to High(Arr1) do
      for j:=0 to High(Arr2) do
        begin
        Result.Args.RxLocations[k] := AzDistToLatLon(Result.Params.TxLoc, Arr1[i], Arr2[j]);
        Inc(k);
        end;
    end
  else
    begin //list of locations
    SetLength(Result.Args.RxLocations, Pm.AsArray.Length);
    SetLength(Result.Args.RxLabels, Pm.AsArray.Length);
    for i:=0 to High(Result.Args.RxLocations) do
      begin
      Result.Args.RxLocations[i].Lat := Pm.AsArray[i].D['Lat'] * RinD;
      Result.Args.RxLocations[i].Lon := Pm.AsArray[i].D['Lon'] * RinD;
      Result.Args.RxLabels[i] := Pm.AsArray[i].S['Label'];
      end;
    end;

  //extract hours
  Pm := So['Arguments']['Hours'];
  if Pm['Start'] <> nil
    then
      begin
      Arr1 := ExpandRange(Pm, 1/24);
      SetLength(Result.Args.Hours, Length(Arr1));
      for i:=0 to High(Result.Args.Hours) do Result.Args.Hours[i] := Arr1[i];
      end
    else
      begin
      SetLength(Result.Args.Hours, Pm.AsArray.Length);
      for i:=0 to High(Result.Args.Hours) do
        Result.Args.Hours[i] := Pm.AsArray.D[i] / 24;
      end;

  //extract frequencies
  Pm := So['Arguments']['Freqs'];
  if Pm['Start'] <> nil
    then
      Result.Args.Freqs := ExpandRange(Pm, 1)
    else
      begin
      SetLength(Result.Args.Freqs, Pm.AsArray.Length);
      for i:=0 to High(Result.Args.Freqs) do
        Result.Args.Freqs[i] := Pm.AsArray.D[i];
      end;

  Pm := So['Arguments']['IncludeMuf'];
  Result.Args.IncludeMuf := (Pm <> nil) and Pm.AsBoolean;
  if Result.Args.IncludeMuf then
    SetLength(Result.Args.Freqs, Length(Result.Args.Freqs)+1);
end;






//------------------------------------------------------------------------------
//                          results to XML
//------------------------------------------------------------------------------
function VoaReplyToXml(const AReply: TVoaReply; const ARequest: TVoaRequest): AnsiString;
begin
  Result := '';

  //TODO

end;






//------------------------------------------------------------------------------
//                          results to JSON
//------------------------------------------------------------------------------
function VoaReplyToJson(const AReply: TVoaReply; const ARequest: TVoaRequest): AnsiString;
var
  Lines: TStringList;
  p, h, f: integer;
  S: string;
  Pm: TPredictedParam;
  ParamNames: array[TPredictedParam] of string;
  RxLabel: string;
begin
  for Pm:=Low(TPredictedParam) to High(TPredictedParam) do
    ParamNames[Pm] := Copy(GetEnumName(TypeInfo(TPredictedParam), Ord(Pm)), 3, MAXINT);

  {$IFDEF FPC}DefaultFormatSettings.{$ENDIF}DecimalSeparator := '.';
  Lines := TStringList.Create;
  try
    Lines.Add('{"predictions": [');
    for p:=0 to High(AReply) do
      for h:=0 to High(AReply[p]) do
        begin
        for f:=0 to High(AReply[p,h].Predictions) do
          begin
          if (ARequest.Args.RxLabels <> nil) and (ARequest.Args.RxLabels[p] <> '')
            then RxLabel := '"Label": "' + ARequest.Args.RxLabels[p] + '", '
            else RxLabel := '';
          S := Format('  {"Lat": %.2f, "Lon": %.2f, %s"Hour": %.2f, ',
            [ARequest.Args.RxLocations[p].Lat * DinR, ARequest.Args.RxLocations[p].Lon * DinR,
             RxLabel, ARequest.Args.Hours[h] * 24]);

          if ARequest.Args.IncludeMuf and (f = High(ARequest.Args.Freqs))
            then S := S + Format('"Freq": %.2f, "IsMuf": "Y", ', [AReply[p,h].Muf])
            else S := S + Format('"Freq": %.2f, "IsMuf": "N", ', [ARequest.Args.Freqs[f]]);

          for Pm:=Low(TPredictedParam) to High(TPredictedParam) do
            if Pm in ARequest.OutParams then
              if Pm = pmMODE
                then
                  S := S + Format('"MODE": "%s", ', [GetModeName(AReply[p,h].Predictions[f], AReply[p,h].Dist)])
                else
                  S := S + Format('"%s": %s, ', [ParamNames[Pm], AReply[p,h].Predictions[f].GetParamStr(Pm)]);
          Lines.Add(Copy(S, 1, Length(S)-2) + '},');
          end;
        end;

    S := Lines[Lines.Count-1];
    Lines[Lines.Count-1] := Copy(S, 1, Length(S)-1);
    Lines.Add(']}');
    Result := AnsiString(Lines.Text);
  finally
    Lines.Free;
  end;

  //verify that the result is a valid JSON:
  Assert(SO(string(Result)) <> nil);
end;






//------------------------------------------------------------------------------
//                          results to CSV
//------------------------------------------------------------------------------
function VoaReplyToCsv(const AReply: TVoaReply; const ARequest: TVoaRequest): AnsiString;
var
  Lines, Fields: TStringList;
  p, h, f: integer;
  Pm: TPredictedParam;
  LocationStr, HourStr: string;
begin
  {$IFDEF FPC}DefaultFormatSettings.{$ENDIF}DecimalSeparator := '.';
  Lines := TStringList.Create;
  Fields := TStringList.Create;
  try
    //header
    for Pm:=Low(TPredictedParam) to High(TPredictedParam) do
      if Pm in ARequest.OutParams then
        Fields.Add(Copy(GetEnumName(TypeInfo(TPredictedParam), Ord(Pm)), 3, MAXINT));
    Lines.Add('Lat,Lon,Hour,Freq,IsMuf,' + Fields.CommaText);

    for p:=0 to High(AReply) do
      begin
      LocationStr := Format('%.2f,%.2f,', [ARequest.Args.RxLocations[p].Lat * DinR, ARequest.Args.RxLocations[p].Lon * DinR]);
      for h:=0 to High(AReply[p]) do
        //prediction
        begin
        HourStr := Format('%.2f,', [ARequest.Args.Hours[h] * 24]);
        for f:=0 to High(AReply[p,h].Predictions) do
          begin
          if ARequest.Args.IncludeMuf and (f = High(ARequest.Args.Freqs))
            then Fields.CommaText := Format('%.2f,Y', [AReply[p,h].Muf])
            else Fields.CommaText := Format('%.2f,N', [ARequest.Args.Freqs[f]]);

          for Pm:=Low(TPredictedParam) to High(TPredictedParam) do
            if Pm in ARequest.OutParams then
              if Pm = pmMODE
                then Fields.Add(GetModeName(AReply[p,h].Predictions[f], AReply[p,h].Dist))
                else Fields.Add(AReply[p,h].Predictions[f].GetParamStr(Pm));

          Lines.Add(LocationStr + HourStr + Fields.CommaText);
          end;
        end;
      end;

    Result := AnsiString(Lines.Text);
  finally
    Lines.Free;
    Fields.Free;
  end;
end;






//------------------------------------------------------------------------------
//             results to the original VOACAP output format
//------------------------------------------------------------------------------
function ValuesToLine(AFreqs: TSingleArray; const AResults: TPredictions;
  APointer: Pointer; ADec: integer; AScale: Single = 1): string;
var
  Offset: Cardinal;
  f: integer;
  Fmt: string;

  function GetValue(Idx: integer): Single;
    begin Result := AScale * PSingle(PByte(@AResults[idx]) + Offset)^; end;

begin
  Offset := PByte(APointer) - PByte(@AResults[0]);
  Fmt := Format('%%5.%df', [ADec]);
  Result := '      ' + Format(Fmt, [GetValue(High(AResults))]);
  for f:=0 to High(AFreqs)-1 do Result := Result + Format(Fmt, [GetValue(f)]);
  for f:=High(AFreqs) to 10 do Result := Result + '   - ';
end;

function VoaReplyToVoaTxt(const AReply: TVoaReply; const ARequest: TVoaRequest): AnsiString;
var
  Lines: TStringList;
  S: string;
  p, h, f: integer;
  Results: TPredictions;
begin
  {$IFDEF FPC}DefaultFormatSettings.{$ENDIF}DecimalSeparator := '.';
  Lines := TStringList.Create;
  try
    for p:=0 to High(AReply) do
      begin
      //TX and RX locations
      S := Format(#13#10'  %5.2f N  %6.2f E - %5.2f N  %6.2f E'#13#10, [
        Abs(ARequest.Params.TxLoc.Lat * DinR),
        Abs(ARequest.Params.TxLoc.Lon * DinR),
        Abs(ARequest.Args.RxLocations[p].Lat * DinR),
        Abs(ARequest.Args.RxLocations[p].Lon * DinR)]);
      if ARequest.Params.TxLoc.Lat < 0 then S[11] := 'S';
      if ARequest.Params.TxLoc.Lon < 0 then S[21] := 'W';
      if ARequest.Args.RxLocations[p].Lat < 0 then S[31] := 'S';
      if ARequest.Args.RxLocations[p].Lon < 0 then S[41] := 'W';
      Lines.Add(S);

      for h:=0 to High(AReply[p]) do
        begin
        Results := AReply[p,h].Predictions;

        //utc
        S := Format('%6.1f%5.1f', [ARequest.Args.Hours[h] * 24, AReply[p,h].Muf]);
        //frequencies
        for f:=0 to High(ARequest.Args.Freqs)-1 do S := S + Format('%5.1f', [ARequest.Args.Freqs[f]]);
        for f:=High(ARequest.Args.Freqs) to 10 do S := S + '  0.0';
        Lines.Add(S + ' FREQ');

        //modes
        if pmMODE in ARequest.OutParams then
          begin
          S := Format('%11s', [GetModeName(Results[High(Results)], AReply[p,h].Dist)]);
          for f:=0 to High(ARequest.Args.Freqs)-1 do S := S + Format('%5s', [GetModeName(Results[f], AReply[p,h].Dist)]);
          for f:=High(ARequest.Args.Freqs) to 10 do S := S + '   - ';
          Lines.Add(S + ' MODE');
          end;

        //FP values
        if pmTANGLE in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].TxElevation, 1,  DinR) + ' TANGLE');
        if (pmRANGLE in ARequest.OutParams) and (AReply[p,h].Dist >= Rad_7000Km) then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].RxElevation, 1,  DinR) + ' RANGLE');
        if pmDELAY in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.Delay_ms,     1) + ' DELAY');
        if pmV_HITE in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].VirtHeight,       0) + ' V HITE');
        if pmMUFDAY in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.MufDay,       2) + ' MUFday');
        if pmLOSS in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.TotalLoss_dB, 0) + ' LOSS');
        if pmDBU in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.Field_dBuV,   0) + ' DBU');
        if pmS_DBW in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.Power_dBW,    0) + ' S DBW');
        if pmN_DBW in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Noise_dBW,        0) + ' N DBW');
        if pmSNR in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.Snr_dB,       0) + ' SNR');
        if pmRPWRG in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].RequiredPower,    0) + ' RPWRG');
        if pmREL in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.Reliability,  2) + ' REL');
        if pmMPROB in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].MultiPathProb,    2) + ' MPROB');
        if pmSPRB in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].ServiceProb,      2) + ' S PRB');
        if pmSIG_LW in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.Power10,      1) + ' SIG LW');
        if pmSIG_UP in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.Power90,      1) + ' SIG UP');
        if pmSNR_LW in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.Snr10,        1) + ' SNR LW');
        if pmSNR_UP in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.Snr90,        1) + ' SNR UP');
        if pmTGAIN in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.TxGain_dB,    1) + ' TGAIN');
        if pmRGAIN in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].Sig.RxGain_dB,    1) + ' RGAIN');
        if pmSNRXX in ARequest.OutParams then
          Lines.Add(ValuesToLine(ARequest.Args.Freqs, Results, @Results[0].SnrXX,            0) + ' SNRxx');
        Lines.Add('');
        end;
      end;

    Result := AnsiString(Lines.Text);
  finally
    Lines.Free;
  end;
end;



end.

