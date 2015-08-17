#! /usr/bin/env python2.7

import re
from collections import defaultdict
from sys import argv

def count_extension(filename):
    with open(filename, 'r') as file:
        ext_dict = defaultdict(int)
        for line in file:
            line = line.strip()
            if line:
                ext_line = line.split('|')[3]
                if '.' in ext_line:
                  clean_ext = re.search('[a-zA-Z]+', \
                              ext_line.split('.')[-1])
                  if clean_ext is not None:
                    ext_dict[clean_ext.group(0).lower()] += 1

    print ext_dict

if __name__ == '__main__':
    count_extension(argv[1])
