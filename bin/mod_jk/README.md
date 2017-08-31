A script to control groups of mod_jk instances.

    mod_jk.py [options]
    
    Options:
      -c file      Specify a file to configure this script
      -s server    Specify a server to check/update
      -b balancer  Specify a balancer to check/update
      -w worker    Specify a server to check/update
      -u key=value Update a balancer worker's settings

This script can read a configuration file specified with the `-c` argument, or will default to reading `mod_jk.conf` in the same directory where the script is located.

A sample configuration file is available, here, and fairly straightforward.
