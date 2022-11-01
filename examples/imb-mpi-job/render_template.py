#!/usr/bin/python3

import argparse
import os
import sys
import time
import yaml
from jinja2 import Template

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='render jinja template with yaml config file')
    parser.add_argument('-i', '--input', help='input file name (stdin if not specified)')
    parser.add_argument('-o', '--output', help='output file name (stdout if not specified)')
    parser.add_argument('-c', '--config', help='yaml config file')
    args = parser.parse_args()

    if args.input is not None:
        with open(args.input) as file:
            template = Template(file.read())
    else:
        template = Template(sys.stdin.read())

    if args.config is not None:
        with open(args.config) as file:
            config = yaml.safe_load(file)
    else:
        config = {}

    config['env'] = os.environ
    config['timestamp'] = time.strftime('%Y%m%d-%H%M%S')

    if args.output is not None:
        with open(args.output, 'w') as file:
            file.write(template.render(config))
    else:
        print(template.render(config))

