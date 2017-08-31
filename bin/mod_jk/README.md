# mod_jk.py

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

## Examples

Using a worker setup like the following:

    worker.list=balancer
    worker.balancer.type=lb
    worker.balancer.balance_workers=node1,node2
    worker.node1.host=host1
    worker.node2.host=host2

And an example configuration file similar to:

    servers = foo.example.com,bar.example.com
    username = scott
    password = tiger

Show the status of all workers for balancer `balancer`:

    mod_jk.py -b balancer

Disable all nodes for balancer `balancer`:

    mod_jk.py -b balancer -u activation=DIS

Disable only `node1` for balancer `balancer`:

    mod_jk -b balancer -w node1 -u activation=DIS

Get the `errors` stats for all workers for balancer `balancer`:

    mod_jk -b balancer -a errors

