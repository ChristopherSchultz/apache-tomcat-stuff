#!/usr/bin/env python
#
# mod_jk.py
#
# Contacts a mod_jk status page to check on workers.
#
# Copyright (c) 2015-2022 Christopher Schultz
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
import argparse
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

def status(servers, balancers, workers, attributes, options) :
    status = 0

    print_server = (1 < len(servers))
    print_balancer = (1 != len(balancers))
    print_worker = (1 != len(workers))

    ok_msg = ""
    warn_msg = ""
    error_msg = ""

    for server in servers :

        url = protocol + server + jk_status_path + '?mime=xml'

        headers = { 'User-Agent' : 'mod_jk.py / Python-urllib',
                    'Connection' : 'close' }
#        print 'Connecting to', url
        req = urllib2.Request(url, None, headers)


        response = urllib2.urlopen(req)
        html = response.read()

#        print(html)

        root = ET.fromstring(html)

        jk_version=root.find('{http://tomcat.apache.org}software').attrib['jk_version']

#        print('+ ' + server + ' (' + jk_version + ')')

        srv_balancers = { bal.attrib['name'] : { 'attrs' : bal.attrib, 'members' : { worker.attrib['name'] : worker.attrib for worker in bal.findall('{http://tomcat.apache.org}member') }  } for bal in root.find('{http://tomcat.apache.org}balancers').findall('{http://tomcat.apache.org}balancer')}

        if balancers : l_balancers = balancers
        else : l_balancers = srv_balancers.keys()

        for balancer in l_balancers :
            if not balancer in srv_balancers:
                print "CRITICAL - balancer '" + balancer + "' was not found in server '" + server + "'"
                exit(2)

            members = srv_balancers[balancer]['members']
            if workers : l_workers = workers
            else : l_workers = members.keys()

            # Print Status
            for worker in l_workers :
                errmsg = ""
                crit = warn = False
                name = ""
                if print_server : name += "server=" + server
                if print_balancer :
                    if name : name += ", "
                    name += "balancer=" + balancer
                if print_worker :
                    if name : name += ", "
                    name += "worker=" + worker
                if name : name += ":"

                member = members[worker]

                if int(member['errors']) > 0 :
                  status = max(status, 1)
                  warn = True
                  if errmsg: errmsg += ", "
                  errmsg += "errors=" + member['errors']

                if int(member['client_errors']) > 0 and not options['ignore_client_errors']:
                  status = max(status, 1)
                  warn = True
                  if errmsg: errmsg += ", "
                  errmsg += "client_errors=" + member['client_errors']

                if int(member['busy']) > 100 :
                  status = max(status, 1)
                  warn = True
                  if errmsg: errmsg += ", "
                  errmsg += "busy=" + member['busy']

                if member['state'] != 'OK' and member['state'] != 'OK/IDLE' :
                  status = max(status, 1)
                  warn = True
                  if errmsg: errmsg += ", "
                  errmsg += "state=" + member['state']

                if member['activation'] == 'DIS' :
                  status = max(status, 1)
                  warn = True
                  if errmsg: errmsg += ", "
                  errmsg += "activation=" + member['activation']
                elif member['activation'] == 'STO' :
                  status = max(status, 2)
                  crit = True
                  if errmsg: errmsg += ", "
                  errmsg += "activation=" + member['activation']

                if crit :
                    error_msg += ("\n" if error_msg else "") + "CRITICAL - " + name + errmsg + ', ' + ', '.join([ (attribute + '=' + (member[attribute] if member.has_key(attribute) else "?")) for attribute in attributes])
                elif warn :
                    warn_msg += ("\n" if warn_msg else "") + "WARNING - " + name + errmsg + ', ' + ', '.join([ (attribute + '=' + (member[attribute] if member.has_key(attribute) else "?")) for attribute in attributes])
                else :
                    ok_msg += ("\n" if ok_msg else "") + "OK - " + name + ', '.join([ (attribute + '=' + (member[attribute] if member.has_key(attribute) else "?")) for attribute in attributes])

    print error_msg + ("\n" if error_msg and warn_msg else "") + warn_msg + ("\n" if (error_msg or warn_msg) and ok_msg else "") + ok_msg

    exit(status)

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

# Merge items in 'items' into 'list'. If any item starts with '-' it is removed from 'list'.
def merge(list, items):
  #print "Merging",items,"into",list
  if(items != None):
    for item in items:
      if(item[0] == '-'):
        item=item[1:]
        print "Possibly removing",item
        if(item in list):
          list.remove(item)
      elif(not item in list):
        list.append(item)
# end of merge()

#######################################
# Main Program
#######################################

# Can add port number if desired

jk_status_path='/jk-status'
protocol = 'https://'
confFile = None
attributes = []

servers = [ ]
balancers=[ ]
workers = [ ]

username=''
password=''
skip_hostname_verification = False
ignore_cert_checks = False

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

parser = argparse.ArgumentParser(description='Queries and possibly updates a mod_jk reverse-proxy server.')

parser.add_argument('-c', '--config', required=True, type=str, help='Configuration file for this script', metavar='config', default=os.path.dirname(sys.argv[0]) + '/mod_jk.conf')
parser.add_argument('-s', '--server', type=str, help='The server to check or update', metavar='server', action='append')
parser.add_argument('-b', '--balancer', type=str, help='The balancer to check or update', metavar='balancer', action='append')
parser.add_argument('-w', '--worker', type=str, help='The worker to check or update', metavar='worker', action='append')
parser.add_argument('-a', '--attribute', type=str, help='Attribute to be reported; can be specified multiple times; default: activation, state', metavar='attr', action='append')
parser.add_argument('-u', '--update', type=str, help='Update an attribute; can be specifief multiple times', metavar='attr=value', action='append');
parser.add_argument('--ignore-client-errors', action="store_true", help='Ignore client-errors on a worker')
args = parser.parse_args()
options = vars(args)
#print(options)

# Read config file first
confFile=options['config']
read_config(confFile, settings)

# Allow command-line arguments to override anything
merge(servers, options['server'])
merge(balancers, options['balancer'])
merge(workers, options['worker'])
merge(attributes, options['attribute'])
if(options['update'] != None):
    for change in options['update']:
        vals = [ val.strip() for val in change.split('=') ]
        changes[vals[0]] = vals[1];

# Use config file for defaults
if not servers and 'servers' in settings: servers = settings['servers']
if not balancers and 'balancers' in settings: balancers = settings['balancers']
if not workers and 'workers' in settings: balancers = settings['workers']
if not attributes and 'attributes' in settings: attributes = settings['attributes']
if 'protocol' in settings : protocol = settings['protocol'][0]
if 'jk_status_path' in settings : jk_status_path = settings['jk_status_path'][0]
if 'username' in settings: username = settings['username'][0]
if 'password' in settings: password = settings['password'][0]
if 'skip_hostname_verification' in settings : skip_hostname_verification = (settings['skip_hostname_verification'][0] in ('true', 'True', 'yes', 'Yes', '1', 'on', 'On'))
if 'ignore_cert_checks' in settings : ignore_cert_checks = (settings['ignore_cert_checks'][0] in ('true', 'True', 'yes', 'Yes', '1', 'on', 'On'))

class IgnoreRedirectHandler(urllib2.HTTPRedirectHandler):
    def http_error_302(self, req, fp, code, msg, headers):
        print 'Ignoring redirect to', headers['Location']
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

ctx = ssl.create_default_context()

if skip_hostname_verification :
    ctx.check_hostname = False
if ignore_cert_checks :
    ctx.verify_mode = ssl.CERT_NONE

host_handler = urllib2.HTTPSHandler(0, context=ctx)

if auth_handler or host_handler :
    if auth_handler and host_handler :
        urllib2.install_opener(urllib2.build_opener(redirect_ignorer, auth_handler, host_handler))
    elif auth_handler :
        urllib2.install_opener(urllib2.build_opener(redirect_ignorer, auth_handler))
    elif host_handler :
        urllib2.install_opener(urllib2.build_opener(redirect_ignorer, host_handler))

if changes:
  update(servers, balancers, workers, changes)

status(servers, balancers, workers, attributes, options)

