The files in this folder are sample input and output of the dvoa.dll wrapper
around the DVOACAP engine.

input.json - the input parameters that correspond to the default settings of
  the original Voacapwin.exe.
 
input2.json - specifies a range of receiver locations on the lat/lon grid, and 
  a range of UTC hours.
  
input3.json - specifies a range of receiver locations on the azumuth/distance
   grid, and a range of frequencies.
   
output.json - sample output from dvoa.dll in the JSON format.

output.txt - sample output from dvoa.dll that corresponds to the input parameters
  in input.json. Compare to the output from the original Voacapwin.exe.
 
voacapx.out - output from the original Voacapwin.exe with its default settings,
  except that the antennas changed to Isotropic.