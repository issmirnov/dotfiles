#! /usr/bin/env python3
"""
A skeleton python script which reads from an a flag
and parses command line arguments
"""

import sys
import argparse

def main():
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument(
        "-f", "--foo",
        help="path to the input file (read from stdin if omitted)")

    args = parser.parse_args()

    print("foo: %s" % args.foo)

if __name__ == "__main__":
    main()
