#Building DVOACAP On Ubuntu

This document describes how to compile and install the DVOACAP library and associated DVoaDllTestCmd application on Ubuntu 13.10.

##Prerequisites
The [Free Pascal](http://www.freepascal.org/) compiler required to build the application is available in the Ubuntu repositories and may be installed with the following command;
    
    sudo apt-get install fp-compiler

##Building the library
From the directory 'DVoaDll' directory, execute the following commands to build the library and install it under /usr/lib.  The following assumes the use of the sudo command to elevate user privileges when installing the library.

    $ fpc -MDELPHI -B -fPIC dvoa.dpr
    $ sudo mkdir -p /usr/lib
    $ sudo cp libdvoa.so /usr/lib
    $ sudo ldconfig


##Building the DVoaDllTestCmd Application
The DVoaDllTestCmd application may be used to test the library and is built from the DVoaDllTestCmd directory with the following command to create the _DVoaDllTestCmd_ executable;

    $ fpc -MDELPHI -B DVoaDllTestCmd.dpr

The DVoaDllTestCmd does not accept any arguments and assumes the presence of a JSON formatted input file named _input.json_ to run.  This file is processed to produce a prediction saved in the file _output.txt_.

    $ ./DVoaDllTestCmd

##Using the library from Python scripts
The _predict_ method in the following script illustrates how the library may be accessed from within Python scripts using the ctypes functionality;

    import argparse
    from ctypes import *

    def predict(in_file, out_file):
        dvoacap = CDLL("libdvoa.so") #define the library
        dvoacap.Predict.restype=c_char_p #define the return type (char *)
        out_file.write(dvoacap.Predict(in_file.read())) #do the prediction...
    

    if __name__ == "__main__":
        parser = argparse.ArgumentParser(description="Wrapper for the DVOACAP library")
        parser.add_argument("-i", "--infile", \
                            default='input.json', 
                            type=argparse.FileType(), \
                            help="json formatted input file")
        parser.add_argument("-o", "--outfile", \
                            default='output.txt', \
                            type=argparse.FileType('w'), \
                            help="formatted prediction output")
        args = parser.parse_args()
    
        predict(args.infile, args.outfile)
        args.infile.close()
        args.outfile.close() 

The script reprodices the functionality of DVoaDllTestCmd but accepts arguments for the input and output files.  If arguments are not provided, the names 'input.json' and 'output.txt' are assumed.
