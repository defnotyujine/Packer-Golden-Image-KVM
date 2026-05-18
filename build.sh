#!/bin/bash
set -e

META_URL=$1
SSH_PASSWORD=$2
IMAGE_NAME=${3:-"rhel-golden.qcow2"}

if [ -z "$META_URL" ] || [ -z "$SSH_PASSWORD" ]; then
    echo "Usage: ./build.sh <meta_url> <ssh_password> [image_name]"
    exit 1
fi

echo "Fetching meta from: $META_URL"
META=$(curl -sf "$META_URL")

KERNEL=$(echo $META | python3 -c "import sys,json; print(json.load(sys.stdin)['kernelLocation'])")
INITRD=$(echo $META | python3 -c "import sys,json; print(json.load(sys.stdin)['initrdLocation'])")
KERNEL_PARAMS=$(echo $META | python3 -c "import sys,json; print(json.load(sys.stdin)['kernelParameters'])")

echo "Kernel:  $KERNEL"
echo "Initrd:  $INITRD"
echo "Params:  $KERNEL_PARAMS"

packer init .
packer build \
    -var="kernel_url=$KERNEL" \
    -var="initrd_url=$INITRD" \
    -var="kernel_params=$KERNEL_PARAMS" \
    -var="ssh_password=$SSH_PASSWORD" \
    -var="image_name=$IMAGE_NAME" \
    rhel.pkr.hcl