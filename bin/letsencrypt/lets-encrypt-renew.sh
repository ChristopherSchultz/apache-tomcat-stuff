#!/bin/sh

##
## lets-encrypt-renew.sh
##
## Renews Let's Encrypt certificates and installs the renewed certificates
## into a running Tomcat.
##

CATALINA_BASE="${CATALINA_BASE:-${HOME}/tomcat}"
HOSTNAME="${1:-${HOSTNAME}}"
CONNECTOR_ADDRESS="${2:-127.0.0.1}"
CONNECTOR_PORT="${3:-8443}"
SERVICE_PORT="${4:-${CONNECTOR_PORT}}"
JMXUSER=${JMXUSER:-jmxproxy}
JMXPASSWORD=${JMXPASSWORD:-jmxproxy}
CERTBOT_HOME="${CERTBOT_HOME:-$(dirname "${0}")}"

LE_BASE="/etc/letsencrypt/live/${HOSTNAME}"
JAVA_HOME="${JAVA_HOME:-/usr/local/java-8}"

# Attempt certificate renewal
"${CERTBOT_HOME}/certbot-auto" renew

# Check to see if LT certificate is newer than Java keystore
if [ "${LE_BASE}/cert.pem" -nt "${CATALINA_BASE}/${HOSTNAME}.p12" ] ; then

  # Move the old keystore file out of the way; save a backup
  mv --backup=numbered "${CATALINA_BASE}/${HOSTNAME}.p12" "${CATALINA_BASE}/${HOSTNAME}.p12"

  echo "Creating keystore ${CATALINA_BASE}/${HOSTNAME}.p12 from files in $LE_BASE"

  # Use PKCS12 keystore format
  openssl pkcs12 -export -in "${LE_BASE}/cert.pem" -inkey "${LE_BASE}/privkey.pem" \
               -certfile "${LE_BASE}/fullchain.pem" \
               -out "${CATALINA_BASE}/${HOSTNAME}.p12" -name tomcat \
               -passout "pass:changeit"

  echo "Reconfiguring Tomcat connector on port ${CONNECTOR_PORT}..."
  result=$(curl "https://$JMXUSER:$JMXPASSWORD@localhost:${SERVICE_PORT}/manager/jmxproxy?invoke=Catalina%3Atype%3DProtocolHandler%2Cport%3D${CONNECTOR_PORT}%2Caddress%3D%22${CONNECTOR_ADDRESS}%22&op=reloadSslHostConfigs")
  
  if [ $(expr "$result" : '^OK') -gt 0 ] ; then
    echo "ProtocolHandler has reloaded"
  else
    echo "Error: ProtocolHandler did not reload properly; response=$result"
  fi
fi

