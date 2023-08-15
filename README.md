# OpenShift-Service-Mesh-Secured-Gateway
Deploy Secured Gateway for an application in OpenShift 4 with Service Mesh.

## Create a new project and add it to `SMMR`.
```
$ oc new-project secured-gateway

$ oc edit smmr default -n istio-system
...
spec:
  members:
  - secured-gateway
```

## Deploy `httpd` sample app with sidecar injection enabled.
```
$ oc new-app registry.redhat.io/rhel8/httpd-24

$ oc get pod
NAME                        READY   STATUS    RESTARTS   AGE
httpd-24-5f8f5cf9dd-k2rmn   1/1     Running   0          19s

$ oc get svc
NAME       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
httpd-24   ClusterIP   172.30.76.104   <none>        8080/TCP,8443/TCP   23s

$ oc edit deployment httpd-24
...
spec:
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      deployment: httpd-24
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      annotations:
        openshift.io/generated-by: OpenShiftNewApp
        sidecar.istio.io/inject: 'true'

$ oc get pod
NAME                        READY   STATUS              RESTARTS   AGE
httpd-24-5f5846df8f-lmp5b   0/2     ContainerCreating   0          6s
httpd-24-5f8f5cf9dd-k2rmn   1/1     Running             0          89s

$ oc get pod
NAME                        READY   STATUS    RESTARTS   AGE
httpd-24-5f5846df8f-lmp5b   2/2     Running   0          15s
```

## Create a `virtualservice` with required host.
```
$ cat virtualservice 
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: httpd 
spec:
  gateways:
  - httpd 
  hosts:
  - httpd.apps.ayush.example.com
  http:
  - route:
    - destination:
        host: httpd-24
        port:
          number: 8080

$ oc create -f virtualservice 
virtualservice.networking.istio.io/httpd created
```

## Generate the TLS certificate and key for the secured gateway.

### Create a root CA and it's key.
```
$ openssl genrsa -out RootCA.key 2048
Generating RSA private key, 2048 bit long modulus
.....................................................................................+++
....................................................................+++
e is 65537 (0x10001)

$ openssl req -new -key RootCA.key -out RootCA.csr -subj "/CN=customCA"

$ cat extension-file 
keyUsage               = critical,digitalSignature,keyEncipherment,keyCertSign
basicConstraints       = critical,CA:true

$ openssl x509 -req -days 1460 -in RootCA.csr -signkey RootCA.key -out RootCA.crt -sha256 -extfile extension-file
Signature ok
subject=/CN=customCA
Getting Private key
```

### Create the certificate and key from root CA for secured gateway with valid hostname as mentioned in hosts for virtualservice.
```
$ openssl genrsa -out server.key 2048
Generating RSA private key, 2048 bit long modulus
.........+++
.+++
e is 65537 (0x10001)

$ openssl req -new -key server.key -out server.csr -subj "/CN=httpd.apps.ayush.example.com"

$ openssl x509 -req -in server.csr -CA RootCA.crt -CAkey RootCA.key -CAcreateserial -out server.crt
Signature ok
subject=/CN=httpd.apps.ayush.example.com
Getting CA Private Key
```

## Create secret in `istio-system` project with newly generated certificate and key.
```
$ oc -n istio-system create secret tls secured-gateway --cert=server.crt --key=server.key
secret/secured-gateway created
```

## Create the gateway in the application project by specifying secret name.
```
$ cat gateway 
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: httpd 
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443 
      name: https
      protocol: HTTPS
    tls:
      credentialName: secured-gateway
      httpsRedirect: true
      mode: SIMPLE
    hosts:
    - httpd.apps.ayush.example.com

$ oc create -f gateway 
Warning: tls.httpsRedirect should only be used with http servers
gateway.networking.istio.io/httpd created
```

## Verify if the route is accessible over `HTTPS` or not with custom certificates.
```
$ oc get route -n istio-system | grep -i secured-gateway
secured-gateway-httpd-b79ffc91d68b1651   httpd.apps.ayush.example.com                                      istio-ingressgateway   https         passthrough/Redirect   None

$ curl -kv https://httpd.apps.ayush.example.com
* About to connect() to httpd.apps.ayush.example.com port 443 (#0)
*   Trying 10.74.208.75...
* Connected to httpd.apps.ayush.example.com (10.74.208.75) port 443 (#0)
* Initializing NSS with certpath: sql:/etc/pki/nssdb
* skipping SSL peer certificate verification
* SSL connection using TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
* Server certificate:
* 	subject: CN=httpd.apps.ayush.example.com
* 	start date: Aug 15 14:58:34 2023 GMT
* 	expire date: Sep 14 14:58:34 2023 GMT
* 	common name: httpd.apps.ayush.example.com
* 	issuer: CN=customCA        <-----------
> GET / HTTP/1.1
> User-Agent: curl/7.29.0
> Host: httpd.apps.ayush.example.com
> Accept: */*
> 
< HTTP/1.1 403 Forbidden
< date: Tue, 15 Aug 2023 15:03:29 GMT
< server: istio-envoy
< last-modified: Mon, 12 Jul 2021 19:36:32 GMT
< etag: "133f-5c6f23d09f000"
< accept-ranges: bytes
< content-length: 4927
< content-type: text/html; charset=UTF-8
< x-envoy-upstream-service-time: 7
< 
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">

<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
	<head>
```
