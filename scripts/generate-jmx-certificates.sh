#!/bin/bash

# Script to generate JMX SSL certificates for Kafka cluster

set -e

# Configuration
NAMESPACE=${NAMESPACE:-default}
VALIDITY_DAYS=${VALIDITY_DAYS:-3650}
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD:-$(openssl rand -base64 16)}
TRUSTSTORE_PASSWORD=${TRUSTSTORE_PASSWORD:-$(openssl rand -base64 16)}
KEY_PASSWORD=${KEY_PASSWORD:-$KEYSTORE_PASSWORD}

# Certificate details
COUNTRY="US"
STATE="State"
LOCALITY="City"
ORGANIZATION="Organization"
ORGANIZATIONAL_UNIT="IT"
COMMON_NAME="kafka-jmx"

# Create temporary directory for certificate generation
CERT_DIR=$(mktemp -d)
echo "Working in temporary directory: $CERT_DIR"

cd $CERT_DIR

# Generate CA key and certificate
echo "Generating CA key and certificate..."
openssl req -new -x509 -keyout ca-key.pem -out ca-cert.pem -days $VALIDITY_DAYS \
    -passout pass:$KEY_PASSWORD \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=JMX-CA"

# Generate server key and certificate request
echo "Generating server key and certificate request..."
keytool -keystore jmx-keystore.jks -alias kafka-jmx -validity $VALIDITY_DAYS -genkey -keyalg RSA \
    -storepass $KEYSTORE_PASSWORD -keypass $KEY_PASSWORD \
    -dname "CN=$COMMON_NAME, OU=$ORGANIZATIONAL_UNIT, O=$ORGANIZATION, L=$LOCALITY, ST=$STATE, C=$COUNTRY"

# Export the certificate request
keytool -keystore jmx-keystore.jks -alias kafka-jmx -certreq -file jmx-cert-req.csr \
    -storepass $KEYSTORE_PASSWORD -keypass $KEY_PASSWORD

# Sign the certificate with CA
echo "Signing certificate with CA..."
openssl x509 -req -CA ca-cert.pem -CAkey ca-key.pem -in jmx-cert-req.csr -out jmx-cert-signed.pem \
    -days $VALIDITY_DAYS -CAcreateserial -passin pass:$KEY_PASSWORD

# Import CA certificate to keystore
echo "Importing CA certificate to keystore..."
keytool -keystore jmx-keystore.jks -alias CARoot -import -file ca-cert.pem \
    -storepass $KEYSTORE_PASSWORD -noprompt

# Import signed certificate to keystore
echo "Importing signed certificate to keystore..."
keytool -keystore jmx-keystore.jks -alias kafka-jmx -import -file jmx-cert-signed.pem \
    -storepass $KEYSTORE_PASSWORD -noprompt

# Create truststore and import CA certificate
echo "Creating truststore..."
keytool -keystore jmx-truststore.jks -alias CARoot -import -file ca-cert.pem \
    -storepass $TRUSTSTORE_PASSWORD -noprompt

# Generate client certificate for JMX access (optional)
echo "Generating client certificate for JMX access..."
keytool -keystore jmx-client-keystore.jks -alias jmx-client -validity $VALIDITY_DAYS -genkey -keyalg RSA \
    -storepass $KEYSTORE_PASSWORD -keypass $KEY_PASSWORD \
    -dname "CN=jmx-client, OU=$ORGANIZATIONAL_UNIT, O=$ORGANIZATION, L=$LOCALITY, ST=$STATE, C=$COUNTRY"

# Export client certificate request
keytool -keystore jmx-client-keystore.jks -alias jmx-client -certreq -file jmx-client-cert-req.csr \
    -storepass $KEYSTORE_PASSWORD -keypass $KEY_PASSWORD

# Sign client certificate with CA
openssl x509 -req -CA ca-cert.pem -CAkey ca-key.pem -in jmx-client-cert-req.csr -out jmx-client-cert-signed.pem \
    -days $VALIDITY_DAYS -CAcreateserial -passin pass:$KEY_PASSWORD

# Import CA and signed certificate to client keystore
keytool -keystore jmx-client-keystore.jks -alias CARoot -import -file ca-cert.pem \
    -storepass $KEYSTORE_PASSWORD -noprompt
keytool -keystore jmx-client-keystore.jks -alias jmx-client -import -file jmx-client-cert-signed.pem \
    -storepass $KEYSTORE_PASSWORD -noprompt

# Output the generated files
echo ""
echo "Certificate generation completed!"
echo "Generated files:"
echo "  - jmx-keystore.jks (Server keystore)"
echo "  - jmx-truststore.jks (Truststore)"
echo "  - jmx-client-keystore.jks (Client keystore for JMX access)"
echo "  - ca-cert.pem (CA certificate)"
echo ""
echo "Passwords:"
echo "  Keystore password: $KEYSTORE_PASSWORD"
echo "  Truststore password: $TRUSTSTORE_PASSWORD"
echo ""
echo "To create Kubernetes secrets, run:"
echo ""
echo "kubectl create secret generic kafka-jmx-certs -n $NAMESPACE \\"
echo "  --from-file=jmx-keystore.jks=$CERT_DIR/jmx-keystore.jks \\"
echo "  --from-file=jmx-truststore.jks=$CERT_DIR/jmx-truststore.jks"
echo ""
echo "kubectl create secret generic kafka-jmx-passwords -n $NAMESPACE \\"
echo "  --from-literal=JMX_KEYSTORE_PASSWORD=$KEYSTORE_PASSWORD \\"
echo "  --from-literal=JMX_TRUSTSTORE_PASSWORD=$TRUSTSTORE_PASSWORD"
echo ""
echo "For values.yaml configuration:"
echo ""
echo "jmxCertificates:"
echo "  keystore: $(base64 -w 0 jmx-keystore.jks)"
echo "  truststore: $(base64 -w 0 jmx-truststore.jks)"
echo ""
echo "jmxPasswords:"
echo "  keystorePassword: $KEYSTORE_PASSWORD"
echo "  truststorePassword: $TRUSTSTORE_PASSWORD"
echo ""
echo "Client keystore for JMX access: $CERT_DIR/jmx-client-keystore.jks"