#!/bin/bash
#adding comments to make code readable

set -o pipefail
LOG_FILE="/var/log/OKE-mlflow-initialize.log"
log() { 
	echo "$(date) [${EXECNAME}]: $*" >> "${LOG_FILE}" 
}


##### SA VAD DACA PUN CERTIFICATUL/SECRET IN ALT NAMESPACE
region=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/regionInfo/regionIdentifier`
obj_storage_namespace=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/obj_storage_namespace`
bucket_name=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/bucket_name`
customer_access_key=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/customer_access_key`
customer_secret_key=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/customer_secret_key`
mlflow_image=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/mlflow_image`
load_balancer_ip=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/load_balancer_ip`
oke_cluster_id=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/oke_cluster_id`
configure_oracle_auth=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/configure_oracle_auth`
issuer=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/oci_domain`
client_id=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/client_id`
client_secret=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/client_secret`

issuer_fqdn="${issuer#https://}"
country=`echo $region|awk -F'-' '{print $1}'`
city=`echo $region|awk -F'-' '{print $2}'`




cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF


yum install kubectl git -y >> $LOG_FILE


mkdir -p /home/opc/.kube
echo "source <(kubectl completion bash)" >> ~/.bashrc
echo "alias k='kubectl'" >> ~/.bashrc
echo "source <(kubectl completion bash)" >> /home/opc/.bashrc
echo "alias k='kubectl'" >> /home/opc/.bashrc
source ~/.bashrc



yum install python36-oci-cli -y >> $LOG_FILE

echo "export OCI_CLI_AUTH=instance_principal" >> ~/.bash_profile
echo "export OCI_CLI_AUTH=instance_principal" >> ~/.bashrc
echo "export OCI_CLI_AUTH=instance_principal" >> /home/opc/.bash_profile
echo "export OCI_CLI_AUTH=instance_principal" >> /home/opc/.bashrc




while [ ! -f /root/.kube/config ]
do
    sleep 5
	source ~/.bashrc
	oci ce cluster create-kubeconfig --cluster-id ${oke_cluster_id} --file /root/.kube/config  --region ${region} --token-version 2.0.0 >> $LOG_FILE
done

cp /root/.kube/config /home/opc/.kube/config
chown -R opc:opc /home/opc/.kube/


mkdir -p /opt/MLFLOW
cd /opt/MLFLOW


cat <<EOF | tee /opt/MLFLOW/mlflow_namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mlflow
EOF


kubectl --kubeconfig /root/.kube/config create -f /opt/MLFLOW/mlflow_namespace.yaml



LBIP=$load_balancer_ip


DOMAIN="mlflow.${LBIP}.nip.io"


mkdir -p /opt/LB_certs
cd /opt/LB_certs
openssl req -x509             -sha256 -days 356             -nodes             -newkey rsa:2048             -subj "/CN=${DOMAIN}/C=$country/L=$city"             -keyout rootCA.key -out rootCA.crt


cat > csr.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
[ dn ]
C = $country
ST = $city
L = $city
O = Mlflow
OU = Mlflow
CN = ${DOMAIN}
[ req_ext ]
subjectAltName = @alt_names
[ alt_names ]
DNS.1 = ${DOMAIN}
IP.1 = ${LBIP}
EOF


openssl genrsa -out "${DOMAIN}.key" 2048
openssl req -new -key "${DOMAIN}.key" -out "${DOMAIN}.csr" -config csr.conf

cat > cert.conf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${DOMAIN}
IP.1 = ${LBIP}
EOF


openssl x509 -req     -in "${DOMAIN}.csr"     -CA rootCA.crt -CAkey rootCA.key     -CAcreateserial -out "${DOMAIN}.crt"     -days 365     -sha256 -extfile cert.conf

kubectl --kubeconfig /root/.kube/config create secret tls mlflow-tls-cert --key=$DOMAIN.key --cert=$DOMAIN.crt -n mlflow







cat <<EOF | tee /opt/MLFLOW/mlflow_config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mlflow
  namespace: mlflow
data:
  MLFLOW_S3_ENDPOINT_URL: "https://$obj_storage_namespace.compat.objectstorage.$region.oraclecloud.com"
  MLFLOW_ARTIFACT_URI: "s3://$bucket_name"
  AWS_DEFAULT_REGION: "$region"
EOF


kubectl --kubeconfig /root/.kube/config apply -f /opt/MLFLOW/mlflow_config.yaml



export customer_access_key
export customer_secret_key

access_key_encoded=$(python3 -c "
import os
import base64
customer_access_key = os.getenv('customer_access_key')
encoded_access_key = base64.b64encode(customer_access_key.encode()).decode('utf-8')
print(encoded_access_key)")


secret_key_encoded=$(python3 -c "
import os
import base64
customer_secret_key = os.getenv('customer_secret_key')
encoded_secret_key = base64.b64encode(customer_secret_key.encode()).decode('utf-8')
print(encoded_secret_key)")




cat <<EOF | tee /opt/MLFLOW/mlflow_secret_oci_access.yaml
apiVersion: v1
kind: Secret
metadata:
  name: mlflow-tracking-secret
  namespace: mlflow
data: 
  AWS_ACCESS_KEY_ID: "$access_key_encoded"
  AWS_SECRET_ACCESS_KEY: "$secret_key_encoded"
EOF

kubectl --kubeconfig /root/.kube/config apply -f /opt/MLFLOW/mlflow_secret_oci_access.yaml








cat <<EOF | tee /opt/MLFLOW/mlflow_deploy.yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: mlflow-tracking-server
  namespace: mlflow
  labels:
    app: mlflow-tracking-server

spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow-tracking-server-pods
  template:
    metadata:
      labels:
        app: mlflow-tracking-server-pods
    spec:
      containers:
        - name: mlflow-tracking-server-pod
          image: $mlflow_image
          imagePullPolicy: Always
          ports:
            - containerPort: 5000
          resources:
            requests:
              memory: "8Gi"
              cpu: "2"
            limits:
              memory: "8Gi"
              cpu: "2"  
          env: 
          - name: MLFLOW_S3_ENDPOINT_URL
            valueFrom:
              configMapKeyRef:
                name: mlflow
                key: MLFLOW_S3_ENDPOINT_URL
          - name: AWS_DEFAULT_REGION
            valueFrom:
              configMapKeyRef:
                name: mlflow
                key: AWS_DEFAULT_REGION
          - name: MLFLOW_ARTIFACT_URI
            valueFrom:
              configMapKeyRef:
                name: mlflow
                key: MLFLOW_ARTIFACT_URI
          - name: AWS_ACCESS_KEY_ID
            valueFrom:
              secretKeyRef:
                name: mlflow-tracking-secret
                key: AWS_ACCESS_KEY_ID
          - name: AWS_SECRET_ACCESS_KEY
            valueFrom:
              secretKeyRef:
                name: mlflow-tracking-secret
                key: AWS_SECRET_ACCESS_KEY                
EOF

kubectl --kubeconfig /root/.kube/config apply -f /opt/MLFLOW/mlflow_deploy.yaml

sleep 30




cat <<EOF | tee /opt/MLFLOW/mlflow_api_service.yaml
apiVersion: v1
kind: Service
metadata:
  name: mlflow-api-service
  namespace: mlflow
spec:
  selector:
    app: mlflow-tracking-server-pods
  ports:
    - port: 5001
      targetPort: 5000
      protocol: TCP
      name: api
EOF

kubectl --kubeconfig /root/.kube/config apply -f /opt/MLFLOW/mlflow_api_service.yaml


kubectl --kubeconfig /root/.kube/config apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/cloud/deploy.yaml
sleep 30

kubectl --kubeconfig /root/.kube/config delete svc ingress-nginx-controller -n ingress-nginx



cat <<EOF | tee /opt/MLFLOW/nginx_service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  labels:
    nginx: ingressgateway
  annotations:
    oci.oraclecloud.com/load-balancer-type: "lb"
    service.beta.kubernetes.io/oci-load-balancer-backend-protocol: "TCP"
    service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
spec:
  type: LoadBalancer
  loadBalancerIP: $load_balancer_ip
  selector:
    app.kubernetes.io/name: ingress-nginx
  ports:
    - name: https
      port: 443
      targetPort: 443
    - name: http
      port: 80
      targetPort: 80
EOF

kubectl --kubeconfig /root/.kube/config apply -f /opt/MLFLOW/nginx_service.yaml





cat <<EOF | tee /opt/MLFLOW/mlflow_api_ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mlflow-api-ingress
  namespace: mlflow
spec:
  ingressClassName: nginx
  tls:
  - hosts:
      - "$DOMAIN"
    secretName: mlflow-tls-cert
  rules:
    - host: "$DOMAIN"
      http:
        paths:
          - pathType: Prefix
            path: "/api"
            backend:
              service:
                name: mlflow-api-service
                port:
                  number: 5001
EOF

kubectl --kubeconfig /root/.kube/config apply -f /opt/MLFLOW/mlflow_api_ingress.yaml


if [ "$configure_oracle_auth" != false ]; then
  mkdir /opt/oauth

  cat <<EOF | tee /opt/oauth/oauth_namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: oauth
EOF

  kubectl --kubeconfig /root/.kube/config apply -f /opt/oauth/oauth_namespace.yaml

  OAUTH2_PROXY_COOKIE_SECRET=$(python -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')

  cat <<EOF | tee /opt/oauth/oauth_deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: oauth
  labels:
    app: oauth2-proxy
  name: oauth2-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: oauth2-proxy
  template:
    metadata:
      labels:
        app: oauth2-proxy
    spec:
      containers:
      - args:
        - --provider=oidc
        - --provider-display-name="Oracle Identity Domains"
        - --oidc-issuer-url=$issuer/
        # added skip issuer since issuer might differ from provider url
        - --insecure-oidc-skip-issuer-verification=true
        - --redirect-url=https://$DOMAIN/oauth2/callback
        - --upstream=file:///dev/null
        - --http-address=0.0.0.0:4180
        - --email-domain=*
        - --set-xauthrequest=true
        - --session-cookie-minimal=true
        - --whitelist-domain=$issuer_fqdn
        env:
        - name: OAUTH2_PROXY_CLIENT_ID
          value: $client_id
        - name: OAUTH2_PROXY_CLIENT_SECRET
          value: $client_secret 
        - name: OAUTH2_PROXY_COOKIE_SECRET
          value: $OAUTH2_PROXY_COOKIE_SECRET
        image: quay.io/oauth2-proxy/oauth2-proxy:latest
        imagePullPolicy: Always
        name: oauth2-proxy
        ports:
        - containerPort: 4180
          protocol: TCP
EOF

  kubectl --kubeconfig /root/.kube/config apply -f /opt/oauth/oauth_deployment.yaml

  cat <<EOF | tee /opt/oauth/oauth_service.yaml
apiVersion: v1
kind: Service
metadata:
  namespace: oauth
  labels:
    app: oauth2-proxy
  name: oauth2-proxy
spec:
  selector:
    app: oauth2-proxy
  ports:
  - name: http
    port: 4180
    protocol: TCP
    targetPort: 4180
EOF

  kubectl --kubeconfig /root/.kube/config apply -f /opt/oauth/oauth_service.yaml

  cat <<EOF | tee /opt/oauth/oauth_ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: oauth
  name: oauth2-proxy
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - "$DOMAIN"
    secretName: mlflow-tls-cert
  rules:
  - host: "$DOMAIN"
    http:
      paths:
      - path: /oauth2
        pathType: Prefix
        backend:
          service:
            name: oauth2-proxy
            port:
              number: 4180
EOF

  kubectl --kubeconfig /root/.kube/config apply -f /opt/oauth/oauth_ingress.yaml


  cat <<EOF | tee /opt/MLFLOW/mlflow_service.yaml
apiVersion: v1
kind: Service
metadata:
  name: mlflow-tracking-service
  namespace: mlflow
spec:
  selector:
    app: mlflow-tracking-server-pods
  ports:
    - port: 5000
      targetPort: 5000
EOF

  kubectl --kubeconfig /root/.kube/config apply -f /opt/MLFLOW/mlflow_service.yaml



  cat <<EOF | tee /opt/MLFLOW/mlflow_ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mlflow-ingress-nginx
  namespace: mlflow
  annotations:
    nginx.ingress.kubernetes.io/auth-url: "https://$DOMAIN/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://$DOMAIN/oauth2/start?rd=\$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "x-auth-request-user, x-auth-request-email"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
      - "$DOMAIN"
    secretName: mlflow-tls-cert
  rules:
    - host: "$DOMAIN"
      http:
        paths:
          - pathType: Prefix
            path: "/"
            backend:
              service:
                name: mlflow-tracking-service
                port:
                  number: 5000
EOF

  kubectl --kubeconfig /root/.kube/config apply -f /opt/MLFLOW/mlflow_ingress.yaml

fi



echo "Load Balancer IP is ${LBIP}" |tee -a $LOG_FILE
echo "Point your browser to https://${DOMAIN}" |tee -a $LOG_FILE