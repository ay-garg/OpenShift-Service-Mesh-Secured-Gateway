#!/bin/bash

# Step 1: Generate Root CA private key
openssl genrsa -out RootCA.key 2048

# Step 2: Generate Root CA CSR
openssl req -new -key RootCA.key -out RootCA.csr -subj "/CN=customCA"

# Step 3: Create the extension file for the Root CA
cat << EOF > extension-file
keyUsage               = critical,digitalSignature,keyEncipherment,keyCertSign
basicConstraints       = critical,CA:true
EOF

# Step 4: Create Root CA certificate
openssl x509 -req -days 1460 -in RootCA.csr -signkey RootCA.key -out RootCA.crt -sha256 -extfile extension-file

# Step 5: Generate server private key
openssl genrsa -out server.key 2048

# Step 6: Prompt for CN-value for server CSR
read -p "Enter CN-value for the server certificate: " CN_value

# Generate the server CSR using the CN-value
openssl req -new -key server.key -out server.csr -subj "/CN=$CN_value"

# Step 7: Sign the server certificate with the Root CA
openssl x509 -req -in server.csr -CA RootCA.crt -CAkey RootCA.key -CAcreateserial -out server.crt

# Step 8: Prompt for namespace and secret-name
read -p "Enter the namespace for the secret: " namespace
read -p "Enter the secret name: " secret_name

# Create the TLS secret using the provided namespace and secret name
oc -n "$namespace" create secret tls "$secret_name" --cert=server.crt --key=server.key

echo "Script completed successfully."
