#!/usr/bin/env python
#
# mod_jk.py
#
# Contacts a mod_jk status page to get or set worker attributes.
#
# Copyright (c) 2015 Christopher Schultz
#
# Christopher Schultz licenses this file to You under the Apache License,
# Version 2.0 (the "License"); you may not use this file except in
# compliance with the License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

import os
import sys
import getopt
import ssl
import urllib
import urllib2
import xml.etree.ElementTree as ET

def read_config(filename, settings) :
    for line in open(filename):
        if line[0] == '#': next
        line = line.rstrip()
        if line :
            values = line.split('=', 1)
            settings[values[0].strip()] = [ val.strip() for val in values[1].split(',') ]
# END read_config()

def status(servers, balancers, workers, attributes) :

    for server in servers :

        url = protocol + server + jk_status_path + '?mime=xml'

        headers = { 'User-Agent' : 'mod_jk.py / Python-urllib',
                    'Connection' : 'close' }
        req = urllib2.Request(url, None, headers)


        response = urllib2.urlopen(req)
        html = response.read()

#        print(html)

        root = ET.fromstring(html)

        jk_version=root.find('{http://tomcat.apache.org}software').attrib['jk_version']

        print('+ ' + server + ' (' + jk_version + ')')

        srv_balancers = { bal.attrib['name'] : { 'attrs' : bal.attrib, 'members' : { worker.attrib['name'] : worker.attrib for worker in bal.findall('{http://tomcat.apache.org}member') }  } for bal in root.find('{http://tomcat.apache.org}balancers').findall('{http://tomcat.apache.org}balancer')}

        if balancers : l_balancers = balancers
        else : l_balancers = srv_balancers.keys()

        for balancer in l_balancers :

            if not balancer in srv_balancers:
                print(" - " + balancer + " (not found in this server)")
                continue

            print(" - " + balancer)
            members = srv_balancers[balancer]['members']
            if workers : l_workers = workers
            else : l_workers = members.keys()

            # Print Status
            for worker in l_workers :
                print('   - ' + worker)
                member = members[worker]
                if not attributes : attributes = member.keys()

                for attr in attributes :
                    if attr in member :
                        print('       ' + attr + '=' + member[attr])
                    else :
                        print('       ' + attr + '=[unknown]')

# END OF status()

# Expecting a dictionary of 'attributes'
def update(servers, balancers, workers, attributes) :

    for server in servers :
        print('+ Updating ' + server)
        url = protocol + server + jk_status_path;

        headers = { 'User-Agent' : 'mod_jk.py / Python-urllib',
                    'Connection' : 'keepalive' }

        if not balancers:
            print('*** No balancers defined; doing nothing - TODO: detect balancers')
            return

        if not workers:
            print('*** No workers defined; doing nothing - TODO: detect workers')
            return

        for balancer in balancers :
            for worker in workers :
                print('  Updating load-balancer ' + balancer + ' worker ' + worker)
                postdata = { 'cmd' : 'update',
                         'w' : balancer,
                         'sw' : worker }

                # vwa is 'activation' and 0 means 'ACTIVE'
                for ( key, val ) in attributes.iteritems():
                    if key in attribute_map:
                        if key in attribute_value_map:
                            postdata[attribute_map[key]] = attribute_value_map[key][val]
                        else:
                            postdata[attribute_map[key]] = val
                    else:
                        postdata[key] = val;

                data = urllib.urlencode(postdata)

                req = urllib2.Request(url + '?' + data, None, headers)

                response = urllib2.urlopen(req)

# END OF update()

def usage(script):
  print(script + ' [options]')
  print
  print('Options:')
  print('  -c file      Specify a file to configure this script')
  print('  -s server    Specify a server to check/update')
  print('  -b balancer  Specify a balancer to check/update')
  print('  -w worker    Specify a server to check/update')
  print('  -u key=value Update a balancer worker\'s settings')
  print
# END OF usage()

#######################################
# Main Program
#######################################

# Can add port number if desired

jk_status_path='/jk-status'
protocol = 'https://'
confFile = os.path.dirname(sys.argv[0]) + '/mod_jk.conf'
attributes = []
servers = [ ]
balancers=[ ]
workers = [ ]

username=''
password=''
skip_hostname_verification = False

attribute_map = {
                  'state'      : None,
                  'activation' : 'vwa',
                  'route'      : 'vwn', 'worker'     : 'wvn',
                  'factor'     : 'vwf',
                  'redirect'   : 'vwr',
                  'domain'     : 'vwc',
                  'distance'   : 'vwd',
                  'host'       : 'vahst', 'hostname'   : 'vahst',
                  'port'       : 'vaprt'
                }

attribute_value_map = {
                        'activation' : { 'ACT' : 0, 'ACTIVE' : 0,
                                         'DIS' : 1, 'DISABLED' : 1,
                                         'STO' : 2, 'STOPPED' : 2,
                                         'STP' : 2 }
                      }

changes = {}
settings = {}

try:
    opts, args = getopt.getopt(sys.argv[1:],
                               'hc:s:b:w:a:u:c:',
                               ['server=', 'balancer=', 'worker=', 'attribute=',
                                'update',
                                'config',
                                ''])
except getopt.GetoptError:
    usage(sys.argv[0])
    sys.exit(2)

for opt, arg in opts:
    if '--' == opt : break
    if opt == '-h':
        usage(sys.argv[0]);
        sys.exit(0)
    elif opt in ('-c', '--config'):
        confFile = arg;
    elif opt in ('-s', '--server'):
        if arg[0] == '-':
            arg = arg[1:]
            if arg in servers:
                servers.remove(arg)
        else:
            if not arg in servers:
                servers.append(arg)
    elif opt in ('-b', '--balancer'):
        if arg[0] == '-':
            arg = arg[1:]
            if arg in balancers:
                balancers.remove(arg)
        else:
            if not arg in balancers:
                balancers.append(arg)
    elif opt in ('-w', '--worker'):
        if arg[0] == '-':
            arg = arg[1:]
            if arg in workers:
                workers.remove(arg)
        else:
            if not arg in workers:
                workers.append(arg)
    elif opt in ('-a', '--attribute'):
        if arg[0] == '+':
            arg = arg[1:]
            if not arg in attributes:
                attributes.append(arg)
        elif arg[0] == '-':
            arg = arg[1:]
            if arg in attributes:
                attributes.remove(arg)
        elif arg[0] == '=':
            arg = arg[1:]
            attributes = [ arg ]
        else:
            if not arg in attributes:
                attributes.append(arg)
    elif opt in ('-u', '--update'):
        vals = [ val.strip() for val in arg.split('=') ]
        changes.update({ vals[0] : vals[1] })

read_config(confFile, settings)

if 'servers' in settings: servers = settings['servers']
if 'balancers' in settings: balancers = settings['balancers']
if 'workers' in settings: balancers = settings['workers']
if not attributes:
  if 'attributes' in settings: attributes = settings['attributes']
  else : attributes = [ 'activation', 'state' ]

if 'username' in settings: username = settings['username'][0]
if 'skip_hostname_verification' in settings : skip_hostname_verification = (settings['skip_hostname_verification'][0] in ('true', 'True', 'yes', 'Yes', '1', 'on', 'On'))
if 'password' in settings: password = settings['password'][0]
if 'jk_status_path' in settings : jk_status_path = settings['jk_status_path'][0]
if 'protocol' in settings : protocol = settings['protocol'][0]

class IgnoreRedirectHandler(urllib2.HTTPRedirectHandler):
    def http_error_302(self, req, fp, code, msg, headers):
        print "Ignoring redirect"
        infourl = urllib.addinfourl(fp, headers, req.get_full_url())
        infourl.status = status
        infourl.code = code
        return infourl
    http_error_301 = http_error_303 = http_error_307 = http_error_302

redirect_ignorer = IgnoreRedirectHandler()

if username and password :
    server_urls = [protocol + host for host in servers]

    password_mgr = urllib2.HTTPPasswordMgrWithDefaultRealm()

    [password_mgr.add_password(None, url, username, password) for url in server_urls]

    auth_handler = urllib2.HTTPBasicAuthHandler(password_mgr)
else :
    auth_handler = None

if skip_hostname_verification :
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    host_handler = urllib2.HTTPSHandler(0, context=ctx)
else :
    host_handler = None

if auth_handler or host_handler :
    if auth_handler and host_handler :
        urllib2.install_opener(urllib2.build_opener(redirect_ignorer, auth_handler, host_handler))
    elif auth_handler :
        urllib2.install_opener(urllib2.build_opener(redirect_ignorer, auth_handler))
    elif host_handler :
        urllib2.install_opener(urllib2.build_opener(redirect_ignorer, host_handler))

if changes:
  update(servers, balancers, workers, changes)

status(servers, balancers, workers, attributes)

