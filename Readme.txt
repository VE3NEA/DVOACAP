                             D-VOACAP v.0.931 beta
                             --------------------
                             
D-VOACAP is an HF propagation prediction engine written in Delphi and based  
on the VOACAP algorithms. This is not a port of the VOACAP Fortran code, 
the algorithms have been reverse-engineered from the code an then implemented
from scratch in a modern language. Special tests have been performed to ensure 
that the new code produces the same numerical results as the old one, within 5 
significant digits. The purpose of the project is two-fold: 1) provide an easy
to use and flexible propagation prediction library for inclusion in Ham 
software, and 2) make the source code of the engine easy to understand for 
those who want to learn the algorithms.

With this library, your software no longer depends on the installation of the
VOACAP program, you do not have to run an external exe as a child process and
simulate the punch cards in its input file. There are no limits on the number
of frequencies, hours and receiver locations for which the predictions are 
calculated, you can call the engine with any combination of the parameters.

There are a few differences in therms of functionality between the original 
VOACAP and DVOACAP:
- DVOACAP does not take into account the Es layer. In VOACAP, Es is disabled
by default but may be enabled;
- only an isotropic antenna is implemented in the library. Other antennas must 
be modeled by the user by creating descendants of the TAntennaModel class;
- a few bugs were found and fixed in the VOACAP Fortran code in the process of
reverse engineering, see VOACAP_bug_fixes.zip included in the package for more
info. These fixes are also included in D-VOACAP.

The library seems to work faster than the original exe. A significant speed 
improvement may be achieved due to proper ordering of predictions. For example, 
the library computes a complete set of propagation maps, like those in the 
HamCap program, 4 times faster than Voacapw.exe because the predictions are 
automatically grouped in such a way that many intermediate results are re-used. 
Further speed improvement may be achieved by creating multiple instances of the 
engine and running them on separate threads, as demonstrated in the included
DVoaMap demo program.

The source code of the prediction engine is located in the DVoaClass folder
in the attached zip file. The programmers who work with Object Pascal will use 
an instance of the engine class, TVoacapEngine, directly by assigning the values 
to its properties and calling its methods. For those who use other programming 
languages, there is a simple wrapper around the engine, dvoa.dll. This DLL 
exports a single function that receives a string with the input parameters 
encoded in the JSON format, and returns the results in the JSON, CSV, or 
native VOA format. The source code of the wrapper are located in the DVoaDll 
folder. A demo program that loads and uses the dll is in the DVoaDllTestCmd 
folder, with source code.

Both the library and the wrapper compile and work on Linux - TNX James Watson.
See the Linux folder for further info.

The JSON format of the parameters is self-explanatory. The SampleIO folder
contains a few examples of the parameters that demonstate different ways of
specifying the frequencies, hours, and receiver locations. The zip also includes
sample output in all three formats, and voacapx.out, the file producded by
the original Voacapw.exe for the same parameters. 


The function exported from the DLL is declared in Object Pascal as follows:

function Predict(ArgsStr: PAnsiChar): PAnsiChar; stdcall;

The C declaration of this function is:

extern "C" {char* __declspec(dllexport) __stdcall Predict(char* ArgsStr);}





Version history

v.0.931b
  - syntax error in input.json fixed;
  - binaries recompiled, files required for running the demo moved to the demo folder.

v.0.93b
  - the first public release, Beta version;
  - Map demo program included.

v.0.92a
  - the library now compiles and works on Linux, TNX James Watson;
  - the json input parser now correctly extracts the specified SSN;
  - examples of location ranges in the input parameters are included.  
  - optional Label field added to the json input format. If present, the label 
    text is copied to the json and csv output.
  
v.0.91a
  - compatibility with FPC;
  - some small fixes in the code.
  
v.0.9a
  - initial release of the Alpha version.
  
  

73 Alex VE3NEA
