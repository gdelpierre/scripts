#! /usr/bin/env python2.7

from collections import Counter
from pprint import pprint
from re import search
from sys import argv

def count_extension(filename):
    with open(filename, 'r') as file:
        # New empty counter.
        ext_dict = Counter()
        for line in file:
            # Remove newlines / carriage returns.
            line = line.strip()
            # Should be a non-empty line, with 200 OK and GET.
            if line and "GET" in line and line.split('|')[13] == '200':
                ext_line = line.split('|')[3]
                if '.' in ext_line:
                  # extensions should be like this regex.
                  clean_ext = search('[a-zA-Z0-9]+', \
                              ext_line.split('.')[-1])
                  # If regex returning None or a digit, do not add it.
                  if clean_ext is not None and \
                     clean_ext.group(0).isdigit() is not True:
                    # lower the extension.
                    ext_dict[clean_ext.group(0).lower()] += 1

    pprint(sorted(((v,k) for k,v in ext_dict.iteritems()), reverse=True))

if __name__ == '__main__':
    count_extension(argv[1])
