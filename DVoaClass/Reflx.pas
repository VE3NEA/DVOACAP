//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is Reflx.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
//------------------------------------------------------------------------------
unit Reflx;

interface

uses
  SysUtils, Math, VoaTypes, IonoProf, PathGeom, MufCalc, TypInfo;


type
  TReflectrix = class
  private
    FKhz: integer;                //JFHZ

    Lr: TIonoLayer;               //IL
    HtIdx, LowH, HighH: integer;  //IH, ILOW, IHIGH
    AngIdx: integer;              //IA
    PenAngles: TLayerParamArray;

    ModeCnt: integer;             //IAF
    Done: boolean;

    procedure SetLayer(ALr: TIonoLayer);
    procedure FindModesForLayer(ALr: TIonoLayer);
    procedure AddRefl;
    procedure AddReflExact;
    procedure AddReflInterp;
    procedure AddReflCusp;

    procedure AddModeExact(AIdx: integer; AHopDist: Single; AHopCnt: integer);
    procedure AddModeInterp(AIdx: integer; AHopDist: Single; AHopCnt: integer);
    procedure AddVerticalMode(AHopDist: Single; AHopCnt: integer);
    procedure AddMode(const AMode: TModeInfo);
  public
    FMhz: Single;                 //FREQ
    FProf: TIonoProfile;
    MinAngle: Single;

    Refl, Modes: TModeInfoArray;
    SkipDistance, MaxDistance: Single;

    constructor Create(AMinAngle, AFreq: Single; AProf: TIonoProfile);
    procedure ComputeReflectrix(AMhz: Single; AProf: TIonoProfile);
    procedure FindModes(AHopDist: Single; AHopCnt: integer);
    procedure AddOverTheMufAndVertModes(AHopDist: Single; AHopCnt: integer; AMuf: TCircuitMuf);
  end;



implementation


const
  MAX_MODES = 6;


{ TReflectrix }

constructor TReflectrix.Create(AMinAngle, AFreq: Single; AProf: TIonoProfile);
begin
  MinAngle := AMinAngle;
  ComputeReflectrix(AFreq, AProf);
end;






//------------------------------------------------------------------------------
//                 all modes for frequency (reflectrix)
//------------------------------------------------------------------------------
procedure TReflectrix.ComputeReflectrix(AMhz: Single; AProf: TIonoProfile);
begin
  //make arguments available to all private methods
  FMhz := AMhz;
  FKhz := Trunc(AMhz * 1000);
  FProf := AProf;

  //compute penetration angles for all layers at frequency AMHz
  PenAngles := FProf.ComputePenetrationAngles(AMhz);

  SkipDistance := MAXINT;
  MaxDistance := 0;
  SetLength(Refl, 45);
  ModeCnt := 0;
  HighH := 0;
  AngIdx := 0;
  Done := false;

  //find propagation modes for each layer
  FindModesForLayer(lrE);
  if (not Done) and (FProf.F1.Fo > 0) then FindModesForLayer(lrF1);
  if not Done then FindModesForLayer(lrF2);

  SetLength(Refl, ModeCnt);
end;


//returns true to continue searh, or false to stop
procedure TReflectrix.FindModesForLayer(ALr: TIonoLayer);
begin
  SetLayer(ALr);

  //CHECK TO SEE IF ANY MODES FROM THIS LAYER
  if PenAngles[Lr] <= 0 then
    begin Done := false; Exit; end; //proceed to next layer

  //CHECK IF PENETRATED ALL LAYERS
  if PenAngles[Lr] > MAX_ELEV_ANGLE then
    begin Done := true; Exit; end; //end of search

  //START OF SEARCH (for each angle in the Angles[] table)
  repeat
    Inc(AngIdx);
    //STOP IF THERE ARE MORE HOPS THAN REASONABLE
    if AngIdx > High(FProf.ObliqueFreq) then
      begin Done := true; Exit; end; //end of search

    //CHECK TO SEE IF LAYER WAS PENETRATED
    if Angles[AngIdx] >= PenAngles[Lr] then
      begin AddReflCusp; Exit; end;

    //SEARCH FOR FREQUENCY
    repeat
      //{!} this could be moved outside of Repeat
      if FProf.ObliqueFreq[AngIdx, LowH] >= FkHz then
        begin AddReflExact; Break; end

      else if HtIdx >= HighH
        then Break

      else if FkHz = FProf.ObliqueFreq[AngIdx, HtIdx] then
        begin AddReflExact; Break; end

      else if (FkHz > FProf.ObliqueFreq[AngIdx, HtIdx]) and (FkHz <= FProf.ObliqueFreq[AngIdx, HtIdx+1])
        then begin AddReflInterp; Break; end

      else
        Inc(HtIdx);
    until false; //next HtIdx


    if Done then Exit;
    
  until false;   //next AngIdx
end;


procedure TReflectrix.SetLayer(ALr: TIonoLayer);
const
  LayerEnd: array[TIonoLayer] of integer = (10, 20, 30);
begin
  LowH := HighH + 1;
  HighH := LayerEnd[ALr];
  HtIdx := LowH;
  Lr := ALr;
end;


//EXACT FREQUENCY TO THREE PLACES (IN MHZ)
procedure TReflectrix.AddReflExact;
var
  Mode: PModeInfo;
begin
  Mode := @Refl[ModeCnt];
  Mode^.Ref.Elevation := Angles[AngIdx];
  Mode^.Layer := Lr;

  FProf.PopulateModeInfo(Mode^, HtIdx);

  AddRefl;
end;


//INTERPOLATION
procedure TReflectrix.AddReflInterp;
var
  Mode: PModeInfo;
  r: Single;
begin
  Mode := @Refl[ModeCnt];
  Mode^.Ref.Elevation := Angles[AngIdx];
  Mode^.Layer := Lr;

  r := FProf.ObliqueFreq[AngIdx, HtIdx + 1] - FProf.ObliqueFreq[AngIdx, HtIdx];
  r := (FKhz - FProf.ObliqueFreq[AngIdx, HtIdx]) / Max(1, r);
  FProf.PopulateModeInfo(Mode^, HtIdx, r);

  AddRefl;
end;


procedure TReflectrix.AddReflCusp;
var
  Mode: PModeInfo;
begin
  //KEEP ANGLE COUNT CORRECT
  Dec(AngIdx);

  //INSERT OF CUSP
  Mode := @Refl[ModeCnt];
  Mode^.Ref.Elevation := PenAngles[Lr];
  Mode^.Layer := Lr;
  FProf.PopulateModeInfo(Mode^, HighH);
  AddRefl;

  Done := Done or (Lr = lrF2) or (PenAngles[Lr] >= MAX_NON_POLE_LAT);
  if Done then Exit;

  //INSERT CUSP FOR NEXT LAYER
  Mode := @Refl[ModeCnt];
  Mode^.Ref.Elevation := Refl[ModeCnt-1].Ref.Elevation + 0.001 * RinD;
  if FProf.F1.Fo > 0 then Mode^.Layer := Succ(Lr) else Mode^.Layer := lrF2;
  FProf.PopulateModeInfo(Mode^, HighH+1);
  AddRefl;
end;


procedure TReflectrix.AddRefl;
var
  Xfsq, Xmut, Corr: Single;
  Mode: PModeInfo;
begin
  Mode := @Refl[ModeCnt];

  //CORRECT MARTYN S THEOREM
  Xfsq := Sqr(FMhz / FProf.F2.Fo);
  Xmut := 1 - Sqr(Mode^.Ref.VertFreq / FMhz);
  Corr := Xfsq * Xmut * CorrToMartynsTheorem(Mode^.Ref);
  Mode^.Ref.VirtHeight := Mode^.Ref.VirtHeight + Corr;

  //ground distance, in radians
  Mode^.HopDist := HopDistance(Mode^.Ref.Elevation, Mode^.Ref.VirtHeight);

  //min and max distance
  if Mode^.HopDist < SkipDistance then SkipDistance := Mode^.HopDist;
  if (Mode^.HopDist >= MaxDistance) and (Mode^.Ref.Elevation >= MinAngle)
    then MaxDistance := Mode^.HopDist;

  //if array full then done
  Inc(ModeCnt);
  Done := ModeCnt > High(Refl);
end;






//------------------------------------------------------------------------------
//                   find modes for the given hop distance
//------------------------------------------------------------------------------
procedure TReflectrix.FindModes(AHopDist: Single; AHopCnt: integer);
var
  r: integer;
begin
  Modes := nil;
  ModeCnt := 0;
  if AHopDist >= MaxDistance then Exit;

  SetLength(Modes, MAX_MODES);
  r := -1;

  repeat
    Inc(r);
    if r >= High(Refl) then Break;

    if Refl[r].HopDist < Refl[r+1].HopDist then
      begin
      if AHopDist < Refl[r].HopDist then Continue
      else if AHopDist = Refl[r].HopDist then AddModeExact(r, AHopDist, AHopCnt)
      else if AHopDist > Refl[r+1].HopDist then Continue
      else if AHopDist = Refl[r+1].HopDist then begin Inc(r); AddModeExact(r, AHopDist, AHopCnt); end
      else if Abs(Refl[r+1].HopDist - Refl[r].HopDist) <= (0.001 / EarthR)
        then AddModeExact(r, AHopDist, AHopCnt) else AddModeInterp(r, AHopDist, AHopCnt);
      end

    else if Refl[r].HopDist > Refl[r+1].HopDist  then
      begin
      if Refl[r].HopDist < AHopDist then Continue
      else if Refl[r].HopDist = AHopDist then AddModeExact(r, AHopDist, AHopCnt)
      else if AHopDist < Refl[r+1].HopDist then Continue
      else if AHopDist = Refl[r+1].HopDist then begin Inc(r); AddModeExact(r, AHopDist, AHopCnt); end
      else if Abs(Refl[r+1].HopDist - Refl[r].HopDist) <= (0.001 / EarthR)
        then AddModeExact(r, AHopDist, AHopCnt) else AddModeInterp(r, AHopDist, AHopCnt);
      end

    else
      begin
      //perhaps a bug in voacap: should be the other way around
      if Abs(AHopDist - Refl[r].HopDist) <= (0.001 / EarthR)
        then Continue
        else AddModeExact(r, AHopDist, AHopCnt);
      end;

  until
    ModeCnt = Length(Modes);

  SetLength(Modes, ModeCnt);
end;


procedure TReflectrix.AddModeExact(AIdx: integer; AHopDist: Single; AHopCnt: integer);
begin
  Modes[ModeCnt] := Refl[AIdx];
  if Modes[ModeCnt].Ref.Elevation >= MinAngle then
    begin
    //INMUF.FOR line 43
    Assert(Modes[ModeCnt].Ref.VirtHeight > 70);
    Modes[ModeCnt].HopDist := AHopDist;
    Modes[ModeCnt].Hopcnt := AHopCnt;
    Inc(ModeCnt);
    end;
end;


procedure TReflectrix.AddModeInterp(AIdx: integer; AHopDist: Single; AHopCnt: integer);
var
  r: Single;
  Mode: PModeInfo;
begin
  Mode := @Modes[ModeCnt];
  Mode^.Layer := Refl[AIdx].Layer;
  Mode^.HopDist := AHopDist;
  Mode^.HopCnt := AHopCnt;

  //DO LINEAR INTERPOLATION
  r := (AHopDist - Refl[AIdx].HopDist) / (Refl[AIdx+1].HopDist - Refl[AIdx].HopDist);
  Mode^.Ref.TrueHeight := Refl[AIdx].Ref.TrueHeight * (1-r) + Refl[AIdx+1].Ref.TrueHeight * r;
  Mode^.Ref.VirtHeight := Refl[AIdx].Ref.VirtHeight * (1-r) + Refl[AIdx+1].Ref.VirtHeight * r;
  Mode^.Ref.DevLoss := Refl[AIdx].Ref.DevLoss * (1-r) + Refl[AIdx+1].Ref.DevLoss * r;

  //BUT FORCE CORRECT GEOMETRY BY CALCULATING RADIATION ANGLE AND
  //SNELL"S LAW BY CALCULATING FV
  Mode^.Ref.Elevation := CalcElevationAngle(AHopDist, Mode^.Ref.VirtHeight);
  Mode^.Ref.VertFreq := FMhz * CosOfIncidence(Mode^.Ref.Elevation, Mode^.Ref.TrueHeight);

  if Mode^.Ref.Elevation >= MinAngle then
    begin
    Assert(Modes[ModeCnt].Ref.VirtHeight > 70);
    Inc(ModeCnt);
    end;
end;






//------------------------------------------------------------------------------
//                 find over-the-muf and zero distance modes
//------------------------------------------------------------------------------
procedure TReflectrix.AddOverTheMufAndVertModes(AHopDist: Single; AHopCnt: integer;
  AMuf: TCircuitMuf);
const
  EPS = 0.4001;
var
  i: integer;
  L: TIonoLayer;
  Layers: set of TIonoLayer;
  //NewMuf: TMufInfo;
  Mode: TModeInfo;
  ModeMuf: Single;
begin
  //WHAT LAYERS ARE IN
  Layers := [];
  for i:=0 to High(Modes) do Include(Layers, Modes[i].Layer);


  //CHECK ON VERY SHORT DISTANCE (TAKE-OFF ANGLE .GE. 89.9)
  //VERY SHORT DISTANCE, MAY NOT BE OVER MUF FOR F2 LAYER.
  //SO PROGRAM WILL DO ZERO DISTANCE WHICH MAY NOT BE IN THE REFLECTRIX
  if AMuf.MufInfo[AMuf.Layer].Ref.Elevation > JUST_BELOW_MAX_ELEV then
    begin AddVerticalMode(AHopDist, AHopCnt); Exit; end;


  //OVER-THE-MUF / INSERT MUF[L] MODE
  for L:=Low(TIonoLayer) to High(TIonoLayer) do
    if ModeCnt >= (MAX_MODES - 1) then Break
    else if L in Layers then Continue
    else if (L = lrF1) and (FProf.F1.Fo <= 0) then Continue
    else if ((FMhz+EPS) >= AMuf.MufInfo[L].Muf) and (AHopCnt = AMuf.MufInfo[L].HopCount) then
      begin
      Mode.Ref := AMuf.MufInfo[L].Ref;
      Mode.Layer := L;
      Mode.HopDist := AHopDist;
      Mode.Hopcnt := AHopCnt;
      AddMode(Mode);
      Include(Layers, L);
      end;


  if AMuf.MufInfo[AMuf.Layer].HopCount = AHopCnt then
    begin
    if Modes = nil then AddVerticalMode(AHopDist, AHopCnt);
    Exit;
    end;


  //CHECK ON ABOVE THE MUF FOR THIS ORDER HOP
  //FIND NEW MUF FOR MODE WITH THIS NUMBER OF HOPS
  for L:=Low(TIonoLayer) to High(TIonoLayer) do
    if ModeCnt >= (MAX_MODES - 1) then Break
    else if L in Layers then Continue
    else if (L = lrF1) and (FProf.F1.Fo <= 0) then Continue
    else if AHopCnt < AMuf.MufInfo[L].HopCount then Continue
    else
      begin
      Mode.Ref.TrueHeight := AMuf.MufInfo[L].Ref.TrueHeight;
      Mode.Ref.VertFreq := AMuf.MufInfo[L].Ref.VertFreq;
      Mode.Ref.DevLoss := AMuf.MufInfo[L].Ref.DevLoss;
      Mode.Layer := L;
      Mode.HopDist := AHopDist;
      Mode.Hopcnt := AHopCnt;


      //Mode.Ref.VirtHeight := FProf.GetVirtualHeightLinear(Mode.Ref.VertFreq);
      Mode.Ref.VirtHeight := InterpolateTable(Mode.Ref.VertFreq, FProf.IgramVertFreq, FProf.IgramVirtHeight);
      Mode.Ref.Elevation := CalcElevationAngle(AHopDist, Mode.Ref.VirtHeight);
      //ESD
      ModeMuf := AMuf.MufInfo[L].Ref.VertFreq  / CosOfIncidence(Mode.Ref.Elevation, Mode.Ref.TrueHeight);

      //CORRECTION TO MARTYN S THEOREM,SEE CURMUF
      Mode.Ref.VirtHeight := Mode.Ref.VirtHeight +
        Sqr(ModeMuf /FProf.Layers[L]^.Fo) *
        Sqr(SinOfIncidence(Mode.Ref.Elevation, Mode.Ref.TrueHeight)) *
        CorrToMartynsTheorem(Mode.Ref);

      Mode.Ref.Elevation := CalcElevationAngle(AHopDist, Mode.Ref.VirtHeight);
      ModeMuf := AMuf.MufInfo[L].Ref.VertFreq / CosOfIncidence(Mode.Ref.Elevation, Mode.Ref.TrueHeight);
      if ModeMuf > (FMhz + Eps) then Continue;

      AddMode(Mode);
      Include(Layers, L);
      end;

  SetLength(Modes, ModeCnt);
end;


procedure TReflectrix.AddVerticalMode(AHopDist: Single; AHopCnt: integer);
var
  Mode: TModeInfo;
  Idx: integer;
  Freq, r: Single;
  Layer: TIonoLayer;
begin
  Freq := FMhz - 0.001;

  //find freq in IgramVertFreq
  Idx := GetIndexOf(Freq, FProf.IgramVertFreq);
  if Freq = FProf.IgramVertFreq[Idx] then r := 0
  else if Idx = High(FProf.IgramVertFreq) then Exit
  else with FProf do
    r := (Freq - IgramVertFreq[Idx]) / (IgramVertFreq[Idx+1] - IgramVertFreq[Idx]);

  //TrueHeight, VirtHeight, VertFreq, DevLoss
  FProf.PopulateModeInfo(Mode, Idx, r);
  Mode.Ref.Elevation := Pi/2;
  Mode.HopDist := AHopDist;
  Mode.HopCnt := AHopCnt;

  //which layer reflects?
  for Layer:=Low(TIonoLayer) to High(TIonoLayer) do
    if Mode.Ref.TrueHeight < FProf.Layers[Layer]^.Hm then
      begin Mode.Layer := Layer; Break; end;

  AddMode(Mode);
end;


procedure TReflectrix.AddMode(const AMode: TModeInfo);
begin
  Inc(ModeCnt);
  SetLength(Modes, ModeCnt);
  Modes[ModeCnt-1] := AMode;
end;



end.

