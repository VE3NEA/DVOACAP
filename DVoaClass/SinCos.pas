//------------------------------------------------------------------------------
//The contents of this file are subject to the Mozilla Public License
//Version 1.1 (the "License"); you may not use this file except in compliance
//with the License. You may obtain a copy of the License at
//http://www.mozilla.org/MPL/ Software distributed under the License is
//distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express
//or implied. See the License for the specific language governing rights and
//limitations under the License.
//
//The Original Code is SinCos.pas.
//
//The Initial Developer of the Original Code is Alex Shovkoplyas, VE3NEA.
//Portions created by Alex Shovkoplyas are
//Copyright (C) 2013 Alex Shovkoplyas. All Rights Reserved.
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
 
