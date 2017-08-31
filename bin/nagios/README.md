# check_jmxproxy
A script for Nagios and Nagios-like monitoring systems that probes a Tomcat instance's JmxProxyServlet for information about the internal state of the server.

    Usage: check_jmxproxy [-v] [-a auth] [-A agent] -U <url> -w <warn> -c <critical>
    
      -A, --useragent
        Specify the User-Agent that will be sent when contacting the server.
    
      -a, --authorization
        Specify the BASIC authorization string that will be used to satisfy
        a WWW-Authenticate challenge. Should be in the form 'user:password'.
    
      -c, --critical
        Specifies the 'critical' level against which the number returned
        from the JMX proxy will be compared. Append a ':' to the end of
        the critical value in order to perform a less-than comparison.
    
      -h, --help
        Shows this help message.
    
      -r, --regexp
        Specifies the regular expression that will be used to capture the
        numeric portion of the JMX proxy's response. The first capture group
        in the regular expression will be used as the numeric response.
        Default: '^OK.*=\s*([0-9]+)$'
    
      -R, --filtering-regexp
        Specifies the regular expresison that will be used to filter the
        response from the JMX proxy before echoing it to the output stream
        after a "JMX OK", "JMX WARN", or "JMX CRITICAL" message. If the
        response from the JMX proxy is malformed, the response will not be
        filtered.
    
      -t, --timeout
        Specifies the timeout, in seconds, to wait for a response before
        the request to the server is considered a failure. Default is 180
        (3 minutes).
    
      -U, --url
        Specifies the URL that check_jmxproxy will contact.
    
      -v, --verbose
        Enabled verbose logging of what check_jmxproxy is doing.
    
      -w, --warn
        Specifies the 'warning' level against which a number returned
        from the JMX proxy will be compared. Append a ':' to the end of
        the warning value in order to perform a less-than comparison.
    
### Example
    check_jmxproxy -U 'http://host/manager/jmxproxy?get=java.lang:type=Memory&att=HeapMemoryUsage&key=used' -w 33554432 -c 50331648
    
This example will report CRITICAL if the current JVM heap size exceeds 48MiB or WARN if the heap size exceeds 32MiB.
