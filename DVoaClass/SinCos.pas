//------------------------------------------------------------------------------
//DVOACAP - an HF propagation prediction engine based on the VOACAP algorithms.
//
//Copyright (C) 2013-2025 Alex Shovkoplyas, VE3NEA.
//
//This file is distributed under the MIT License. See the LICENSE file in the
//project root for the full license text.
//------------------------------------------------------------------------------
unit SinCos;

interface

uses
  Math;


type
  TSinCos = record Sn, Cs: Single; end;
  TSinCosArray = array of TSinCos;


function MakeSinCosArray(X: Single; Len: integer): TSinCosArray;




implementation

function MakeSinCosArray(X: Single; Len: integer): TSinCosArray;
var
  i: integer;
begin
  Assert(Len > 1);
  SetLength(Result, Len);

  Result[0].Sn := 0;
  Result[0].Cs := 1;
  
  Result[1].Sn := Sin(x);
  Result[1].Cs := Cos(x);

  for i:=2 to Len-1 do
    begin
    Result[i].Sn := Result[1].Sn * Result[i-1].Cs + Result[1].Cs * Result[i-1].Sn;
    Result[i].Cs := Result[1].Cs * Result[i-1].Cs - Result[1].Sn * Result[i-1].Sn;
    end;
end;



end.
 
