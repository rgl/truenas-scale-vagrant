#!/bin/bash
set -euxo pipefail

ip_address="${1:-10.10.0.11}"
truenas_ip_address="${2:-10.10.0.2}"
k3s_version="${3:-v1.26.2+k3s1}"
k9s_version="${4:-v0.27.3}"
helm_version="${5:-v3.11.2}"
democratic_csi_chart_version="${6:-0.13.5}"
democratic_csi_tag="${7:-v1.8.1}"
gitea_chart_version="${8:-7.0.4}"
gitea_version="${9:-1.19.0}"
fqdn="$(hostname --fqdn)"
k3s_fqdn="s.$(hostname --domain)"
k3s_url="https://$k3s_fqdn:6443"

# install iscsi tools.
# NB to manually mount the iscsi target use, e.g.:
#       apt-get install -y open-iscsi
#       echo 'InitiatorName=iqn.2020-01.test:rpijoy' >/etc/iscsi/initiatorname.iscsi
#       systemctl restart iscsid
#       iscsiadm --mode discovery --type sendtargets --portal 10.10.0.2:3260 # list the available targets (e.g. 10.10.0.2:3260,1 iqn.2005-10.org.freenas.ctl:ubuntu)
#       iscsiadm --mode node --targetname iqn.2005-10.org.freenas.ctl:ubuntu --login # start using the target.
#       find /etc/iscsi -type f # list the configuration files.
#       ls -lh /dev/disk/by-path/*-iscsi-iqn.* # list all iscsi block devices (e.g. /dev/disk/by-path/ip-10.10.0.2:3260-iscsi-iqn.2005-10.org.freenas.ctl:ubuntu-lun-0 -> ../../sdb)
#       mkfs.ext4 /dev/sdb
#       lsblk /dev/sdb # lsblk -O /dev/sdb
#       blkid /dev/sdb
#       mount -o noatime /dev/sdb /mnt
#       ls -laF /mnt
#       umount /mnt
#       iscsiadm --mode node --targetname iqn.2005-10.org.freenas.ctl:ubuntu --logout # stop using the target.
# see https://wiki.archlinux.org/index.php/Open-iSCSI
# see https://github.com/open-iscsi/open-iscsi
# see https://tools.ietf.org/html/rfc7143
# see https://github.com/democratic-csi/democratic-csi#ubuntu--debian
apt-get install -y open-iscsi

# install k9s.
wget -qO- "https://github.com/derailed/k9s/releases/download/$k9s_version/k9s_Linux_amd64.tar.gz" \
  | tar xzf - k9s
install -m 755 k9s /usr/local/bin/
rm k9s

# install helm.
# see https://helm.sh/docs/intro/install/
echo "installing helm $helm_version client..."
wget -qO- "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz" | tar xzf - --strip-components=1 linux-amd64/helm
install helm /usr/local/bin
rm helm
helm completion bash >/usr/share/bash-completion/completions/helm

# install k3s.
# see server arguments at e.g. https://github.com/k3s-io/k3s/blob/v1.26.2+k3s1/pkg/cli/cmds/server.go#L543-L551
# or run k3s server --help
# see https://docs.k3s.io/installation/configuration
# see https://docs.k3s.io/reference/server-config
curl -sfL https://raw.githubusercontent.com/k3s-io/k3s/$k3s_version/install.sh \
  | \
    INSTALL_K3S_CHANNEL="latest" \
    INSTALL_K3S_VERSION="$k3s_version" \
    K3S_TOKEN="abracadabra" \
    sh -s -- \
      server \
      --node-ip "$ip_address" \
      --cluster-cidr '10.12.0.0/16' \
      --service-cidr '10.13.0.0/16' \
      --cluster-dns '10.13.0.10' \
      --cluster-domain 'cluster.local' \
      --flannel-iface 'eth1' \
      --flannel-backend 'host-gw' \
      --tls-san "$k3s_fqdn" \
      --kube-proxy-arg proxy-mode=ipvs \
      --cluster-init
crictl completion bash >/usr/share/bash-completion/completions/crictl
kubectl completion bash >/usr/share/bash-completion/completions/kubectl

# symlink the default kubeconfig path so local tools like k9s can easily
# find it without exporting the KUBECONFIG environment variable.
install -m 700 -d ~/.kube
ln -s /etc/rancher/k3s/k3s.yaml ~/.kube/config

# wait for this node to be Ready.
# e.g. s1     Ready    control-plane,master   3m    v1.26.2+k3s1
$SHELL -c 'node_name=$(hostname); echo "waiting for node $node_name to be ready..."; while [ -z "$(kubectl get nodes $node_name | grep -E "$node_name\s+Ready\s+")" ]; do sleep 3; done; echo "node ready!"'

# wait for the kube-dns pod to be Running.
# e.g. coredns-fb8b8dccf-rh4fg   1/1     Running   0          33m
$SHELL -c 'while [ -z "$(kubectl get pods --selector k8s-app=kube-dns --namespace kube-system | grep -E "\s+Running\s+")" ]; do sleep 3; done'

# install persistent storage support.
# see https://github.com/democratic-csi/democratic-csi
# see https://github.com/democratic-csi/democratic-csi/blob/master/examples/freenas-api-iscsi.yaml
# see https://github.com/democratic-csi/charts/tree/master/stable/democratic-csi
# see https://github.com/democratic-csi/charts/issues/32 to known why the autor does not want to pin the version.
# see https://hub.docker.com/r/democraticcsi/democratic-csi/tags
# alternative: https://github.com/hpe-storage/truenas-csp
helm repo add democratic-csi https://democratic-csi.github.io/charts/
helm repo update
helm search repo democratic-csi/ --versions | head -10
cat >truenas-api-iscsi-values.yml <<EOF
controller:
  driver:
    image: docker.io/democraticcsi/democratic-csi:$democratic_csi_tag
node:
  driver:
    image: docker.io/democraticcsi/democratic-csi:$democratic_csi_tag
csiDriver:
  name: org.democratic-csi.iscsi
storageClasses:
  - name: truenas-iscsi-csi
    defaultClass: false
    reclaimPolicy: Delete
    volumeBindingMode: Immediate
    allowVolumeExpansion: true
    parameters:
      fsType: ext4
driver:
  config:
    driver: freenas-api-iscsi
    httpConnection:
      protocol: http
      host: $truenas_ip_address
      port: 80
      username: root
      password: root
    zfs:
      datasetProperties:
        "org.freenas:description": "{{ parameters.[csi.storage.k8s.io/pvc/namespace] }}/{{ parameters.[csi.storage.k8s.io/pvc/name] }}"
      datasetParentName: tank/k3s/v
      detachedSnapshotsDatasetParentName: tank/k3s/s
      zvolBlocksize: ""
      zvolCompression: ""
      zvolDedup: ""
      zvolEnableReservation: false
    iscsi:
      targetPortal: $truenas_ip_address:3260
      interface: ""
      namePrefix: "csi-k3s-"
      nameSuffix: ""
      targetGroups:
        - targetGroupPortalGroup: 1
          targetGroupInitiatorGroup: 1
          targetGroupAuthType: None
          targetGroupAuthGroup:
      extentCommentTemplate: "{{ parameters.[csi.storage.k8s.io/pvc/namespace] }}/{{ parameters.[csi.storage.k8s.io/pvc/name] }}"
      extentAvailThreshold: 0
      extentDisablePhysicalBlocksize: false
      extentBlocksize: 4096
      extentRpm: SSD
EOF
helm upgrade --install \
  zfs-iscsi \
  democratic-csi/democratic-csi \
  --version $democratic_csi_chart_version \
  --create-namespace \
  --namespace democratic-csi \
  --wait \
  --values truenas-api-iscsi-values.yml

# get all the storage classes.
kubectl get storageclass

# create an iscsi example persistent volume claim.
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: truenas-iscsi-csi-example
  namespace: default
spec:
  storageClassName: truenas-iscsi-csi
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
EOF
kubectl wait --for jsonpath='{.status.phase}'=Bound pvc/truenas-iscsi-csi-example

# get all the pvc and pv.
kubectl get pvc -A
kubectl get pv -A

# deploy gitea as an example stateful application.
# see https://gitea.com/gitea/helm-chart/#persistence
# see https://gitea.com/gitea/helm-chart/tags
# see https://hub.docker.com/r/gitea/gitea/tags
helm repo add gitea https://dl.gitea.io/charts/
helm repo update
helm search repo gitea/ --versions | head -10
cat >gitea-values.yml <<EOF
image:
  tag: $gitea_version
ingress:
  enabled: true
gitea:
  admin:
    username: gitea
    password: abracadabra # MUST be 6+ characters.
memcached:
  enabled: false
global:
  storageClass: truenas-iscsi-csi
EOF
helm upgrade --install \
  gitea \
  gitea/gitea \
  --version $gitea_chart_version \
  --create-namespace \
  --namespace gitea \
  --wait \
  --values gitea-values.yml

# list all the active iscsi sessions.
iscsiadm -m session

# get all the pvc and pv.
kubectl get pvc -A
kubectl get pv -A

# get the gitea resources.
kubectl get all -n gitea

# get all the ingresses.
kubectl get ingress -A
