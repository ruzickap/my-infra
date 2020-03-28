#!/bin/bash -e

set -o pipefail

if [ $# -gt 0 ] && [ -z ${ACTION+x} ]; then
  export ACTION="$1";
else
  export ACTION="${ACTION:-create}"
fi
export CLOUD_PLATFORM="${CLOUD_PLATFORM:-oci}"
export LETSENCRYPT_ENVIRONMENT="${LETSENCRYPT_ENVIRONMENT:-staging}" # or "production" with real certs
export PREFIX="${PREFIX:-$USER}"
export CLOUDFLARE_EMAIL="${CLOUDFLARE_EMAIL:-petr.ruzicka@gmail.com}"
export TF_VAR_cloudflare_email="${CLOUDFLARE_EMAIL}"
export CLOUDFLARE_API_KEY="${CLOUDFLARE_API_KEY:-4xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx9}"
export TF_VAR_cloudflare_api_key="${CLOUDFLARE_API_KEY}"
export TF_VAR_prefix="${PREFIX}"
export MY_DOMAIN="${MY_DOMAIN:-xvx.cz}"
export TF_VAR_my_domain="${MY_DOMAIN}"
export MY_NAME="${MY_NAME:-infra}"
export TF_VAR_my_name="${MY_NAME}"

variables_aws() {
  export S3_BACKEND_CONFIG_ENDPOINT="s3.amazonaws.com"
}

variables_oci() {
  export AWS_ACCESS_KEY_ID="${OCI_AWS_ACCESS_KEY_ID:-0xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx1}"
  export AWS_SECRET_ACCESS_KEY="${OCI_AWS_SECRET_ACCESS_KEY:-5xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=}"
  export OCI_COMPARTMENT_ID="${OCI_COMPARTMENT_ID:-ocid1.compartment.oc1.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx}"
  export TF_VAR_fingerprint="${OCI_FINGERPRINT:-xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx}"
  export TF_VAR_private_key_path="${OCI_PRIVATE_KEY_PATH:-$HOME/.oci/oci_api_key.pem}"
  export TF_VAR_tenancy_ocid="${OCI_TENANCY_OCID:-ocid1.tenancy.oc1.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx}"
  export TF_VAR_user_ocid="${OCI_USER_OCID:-ocid1.user.oc1.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx}"
  export TF_VAR_region="${TF_VAR_region:-eu-frankfurt-1}"
}

create_oci() {
  if NAMESPACE=$(oci os bucket get --bucket-name terraform-state 2>/dev/null | jq '.data.namespace' -r); then
    export NAMESPACE
  else
    NAMESPACE=$(oci os bucket create --name terraform-state --compartment-id="${OCI_COMPARTMENT_ID}" | jq '.data.namespace' -r)
  fi
  export S3_BACKEND_CONFIG_ENDPOINT="https://${NAMESPACE}.compat.objectstorage.${TF_VAR_region}.oraclecloud.com"
}

delete_oci() {
  oci os object delete --bucket-name terraform-state --name terraform.tfstate --force
  oci os bucket delete --name terraform-state --force
}

main() {
  cd "$(dirname "$0")"
  "variables_${CLOUD_PLATFORM}"
  echo "*** Cloud Platform: ${CLOUD_PLATFORM}, Action: ${ACTION}, Prefix: ${PREFIX}"

  case "${ACTION}" in
    create)
      "create_${CLOUD_PLATFORM}" && \
      ansible-playbook -i localhost, -e ansible_python_interpreter=/usr/bin/python3 --private-key "${HOME}/.ssh/id_rsa" site.yml
    ;;
    delete)
      ansible-playbook -i localhost, -e ansible_python_interpreter=/usr/bin/python3 --private-key "${HOME}/.ssh/id_rsa" site.yml && \
      "delete_${CLOUD_PLATFORM}"
    ;;
    *)
      echo -e "Unkkonwn parametrs!\nPlease use $0 {crete,delete}"
    ;;
  esac
}

main
