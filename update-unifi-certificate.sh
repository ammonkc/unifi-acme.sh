#!/bin/bash

# Copyright 2018 Ammon Casey
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ -z "$1" ]; then
	echo "No domain included.  See documentation for usage instructions."
	exit 1
fi

# The domain for which acme.sh generated/generates a certificate
DOMAIN="$1"

if [ -z "$2" ]; then
	# No certificate location specified.  Check the default location first.
	if [ -d "${HOME}/.acme.sh/${DOMAIN}" ]; then
		WORKDIR="${HOME}/.acme.sh/${DOMAIN}"
		echo "Found certificate directory at default location: ${WORKDIR}"
	else
		echo "No certificate directory path included.  See documentation for usage instructions."
		exit 1
	fi
else
	WORKDIR="$2"
	if [ ! -d "${WORKDIR}" ]; then
		echo "Certificate directory not found: ${WORKDIR}"
		exit 1
	fi
fi

# Are we on a CloudKey?
uname -a | grep CloudKey > /dev/null
CLOUD_KEY="$?"

# Find out what user we are
CURRENT_USER="$(whoami)"

SSLDIR="/etc/ssl"
CERTDIR="${SSLDIR}/private"
BACKUPDIR="${SSLDIR}/backup"
KEYSTOREDIR="/usr/lib/unifi/data"
KEYPASS="aircontrolenterprise"
TIMESTAMP="$(date "+%Y%m%d%H%M.%S")"

echo "Updating UniFi Controller certificate"

if [ $CLOUD_KEY -eq 0 ]; then
	echo "* Stopping nginx..."
	systemctl stop nginx

	echo "* Backup current cert directory"
	mkdir -p $BACKUPDIR
	cp -r $CERTDIR "${BACKUPDIR}/${TIMESTAMP}"

	echo "* Modifying controller config for initial setup..."
	sed -i /etc/default/unifi -e '/UNIFI_SSL_KEYSTORE/s/^/# /'
fi

echo "* Stopping UniFi controller..."
systemctl stop unifi

echo "* Creating PKCS12 keystore..."
openssl pkcs12 -export -passout pass:aircontrolenterprise \
 -in "${WORKDIR}/${DOMAIN}.cer" \
 -inkey "${WORKDIR}/${DOMAIN}.key" \
 -out "${WORKDIR}/keystore.pkcs12" -name unifi \
 -CAfile "${WORKDIR}/fullchain.cer" -caname root

echo "* Importing certificate into Unifi Controller keystore..."
keytool -noprompt -trustcacerts -importkeystore \
 -deststorepass $KEYPASS \
 -destkeypass $KEYPASS \
 -destkeystore "${WORKDIR}/unifi.keystore.jks" \
 -srckeystore "${WORKDIR}/keystore.pkcs12" \
 -srcstoretype PKCS12 -srcstorepass $KEYPASS -alias unifi

cat > "${WORKDIR}/identrust.cer" << EOF
-----BEGIN CERTIFICATE-----
MIIDSjCCAjKgAwIBAgIQRK+wgNajJ7qJMDmGLvhAazANBgkqhkiG9w0BAQUFADA/
MSQwIgYDVQQKExtEaWdpdGFsIFNpZ25hdHVyZSBUcnVzdCBDby4xFzAVBgNVBAMT
DkRTVCBSb290IENBIFgzMB4XDTAwMDkzMDIxMTIxOVoXDTIxMDkzMDE0MDExNVow
PzEkMCIGA1UEChMbRGlnaXRhbCBTaWduYXR1cmUgVHJ1c3QgQ28uMRcwFQYDVQQD
Ew5EU1QgUm9vdCBDQSBYMzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
AN+v6ZdQCINXtMxiZfaQguzH0yxrMMpb7NnDfcdAwRgUi+DoM3ZJKuM/IUmTrE4O
rz5Iy2Xu/NMhD2XSKtkyj4zl93ewEnu1lcCJo6m67XMuegwGMoOifooUMM0RoOEq
OLl5CjH9UL2AZd+3UWODyOKIYepLYYHsUmu5ouJLGiifSKOeDNoJjj4XLh7dIN9b
xiqKqy69cK3FCxolkHRyxXtqqzTWMIn/5WgTe1QLyNau7Fqckh49ZLOMxt+/yUFw
7BZy1SbsOFU5Q9D8/RhcQPGX69Wam40dutolucbY38EVAjqr2m7xPi71XAicPNaD
aeQQmxkqtilX4+U9m5/wAl0CAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNV
HQ8BAf8EBAMCAQYwHQYDVR0OBBYEFMSnsaR7LHH62+FLkHX/xBVghYkQMA0GCSqG
SIb3DQEBBQUAA4IBAQCjGiybFwBcqR7uKGY3Or+Dxz9LwwmglSBd49lZRNI+DT69
ikugdB/OEIKcdBodfpga3csTS7MgROSR6cz8faXbauX+5v3gTt23ADq1cEmv8uXr
AvHRAosZy5Q6XkjEGB5YGV8eAlrwDPGxrancWYaLbumR9YbK+rlmM6pZW87ipxZz
R8srzJmwN0jP41ZL9c8PDHIyh8bwRLtTcm1D9SZImlJnt1ir/md2cXjbDaJWFBM5
JDGFoqgCWjBH4d1QB7wCCZAA62RjYJsWvIjJEubSfZGL+T0yjWW06XyxV3bqxbYo
Ob8VZRzI9neWagqNdwvYkQsEjgfbKbYK7p2CNTUQ
-----END CERTIFICATE-----
EOF

echo "* Importing certificate via ace.jar..."
java -jar /usr/lib/unifi/lib/ace.jar import_cert \
 "${WORKDIR}/${DOMAIN}.cer" \
 "${WORKDIR}/ca.cer" \
 "${WORKDIR}/identrust.cer"

if [ $CLOUD_KEY -eq 0 ]; then
	if [ -d "${BACKUPDIR}/${TIMESTAMP}" ]; then
		echo "* Setting permissions on certificate and key for initial setup..."
		chown ${CURRENT_USER}:ssl-cert "${WORKDIR}/fullchain.cer"
		chown ${CURRENT_USER}:ssl-cert "${WORKDIR}/${DOMAIN}.key"
		chown ${CURRENT_USER}:ssl-cert "${WORKDIR}/unifi.keystore.jks"

		chmod 640 "${WORKDIR}/fullchain.cer"
		chmod 640 "${WORKDIR}/${DOMAIN}.key"
		chmod 640 "${WORKDIR}/unifi.keystore.jks"

		echo "* Remove old cert files..."
		rm "${CERTDIR}/cert.tar"
		rm "${CERTDIR}/cloudkey.crt"
		rm "${CERTDIR}/cloudkey.key"
		rm "${CERTDIR}/cloudkey.unifi.keystore.jks"
		rm "${KEYSTOREDIR}/keystore"

		echo "* Install new cert files..."
		cp "${WORKDIR}/fullchain.cer" "${CERTDIR}/cloudkey.crt"
		cp "${WORKDIR}/${DOMAIN}.key" "${CERTDIR}/cloudkey.key"
		cp "${WORKDIR}/unifi.keystore.jks" "${CERTDIR}/unifi.keystore.jks"
		ln -s "${CERTDIR}/unifi.keystore.jks" "${KEYSTOREDIR}/keystore"

		tar -cvf "${CERTDIR}/cert.tar" "${CERTDIR}/cloudkey.crt" "${CERTDIR}/cloudkey.key" "${CERTDIR}/unifi.keystore.jks"

		sed -i /etc/default/unifi -e '/UNIFI_SSL_KEYSTORE/s/^# //'

	fi
fi

echo "* Starting UniFi Controller..."
systemctl start unifi

if [ $CLOUD_KEY -eq 0 ]; then
	echo "* Starting nginx..."
	systemctl start nginx
fi
