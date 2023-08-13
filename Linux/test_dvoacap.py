import argparse
from ctypes import *


def predict(in_file, out_file):
    dvoacap = CDLL("libdvoa.so")  # define the library
    dvoacap.Predict.restype = c_char_p  # define the return type (char *)
    in_str = in_file.read().encode()

    predict_txt = dvoacap.Predict(in_str)

    out_file.write(predict_txt.decode())  # do the prediction...
    print("Done")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Wrapper for the DVOACAP library")
    parser.add_argument(
        "-i",
        "--infile",
        default="input.json",
        type=argparse.FileType(),
        help="json formatted input file",
    )
    parser.add_argument(
        "-o",
        "--outfile",
        default="output.txt",
        type=argparse.FileType("w"),
        help="formatted prediction output",
    )
    args = parser.parse_args()

    predict(args.infile, args.outfile)
    args.infile.close()
    args.outfile.close()
