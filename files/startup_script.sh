#!/bin/bash
set -e

# Send the log output from this script to user-data.log, syslog, and the console
# Inspired by https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

readonly COMPUTE_INSTANCE_METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
readonly GOOGLE_CLOUD_METADATA_REQUEST_HEADER="Metadata-Flavor: Google"


# Get the value at a specific Instance Metadata path.
function get_instance_metadata_value {
  local -r path="$1"
  curl --silent --show-error --location --header "$GOOGLE_CLOUD_METADATA_REQUEST_HEADER" "$COMPUTE_INSTANCE_METADATA_URL/$path"
}

# Get the value of the given Custom Metadata Key
function get_instance_custom_metadata_value {
  local -r key="$1"
  get_instance_metadata_value "instance/attributes/$key"
}

# Get the GCE Region in which this Compute Instance currently resides
function get_instance_region {
  # The value returned for zone will be of the form "projects/121238320500/zones/us-west1-a" so we need to split the string
  # by "/" and return the 4th string.
  # Then we split again by '-' and return the first two fields.
  # from 'europe-west1-b' to 'europe-west1'
  get_instance_metadata_value "instance/zone" | cut -d'/' -f4 | awk -F'-' '{ print $1"-"$2 }'
}

instance_ip_address=$(get_instance_metadata_value "instance/network-interfaces/0/ip")
instance_name=$(get_instance_metadata_value "instance/name")
instance_region=$(get_instance_region)
project_id=$(get_instance_metadata_value "project/project-id")

CONSUL_ZIP_URL="https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip"
CONSUL_CHECKSUM_URL="https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_SHA256SUMS"
VAULT_ZIP_URL="https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_linux_amd64.zip"
VAULT_CHECKSUM_URL="https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_SHA256SUMS"

export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq upgrade
apt-get -qq install --no-install-recommends curl unzip jq

# Fetch Hashicorp signing key from Keybase
curl -s https://keybase.io/hashicorp/pgp_keys.asc | gpg --import --quiet

mkdir fetch ; cd fetch
curl -s -O $CONSUL_ZIP_URL -O $CONSUL_CHECKSUM_URL -O $CONSUL_CHECKSUM_URL.sig
curl -s -O $VAULT_ZIP_URL -O $VAULT_CHECKSUM_URL -O $VAULT_CHECKSUM_URL.sig

echo -e "\nFetched files:"
ls -lh
sleep 1
echo -e

gpg --verify --quiet consul_${consul_version}_SHA256SUMS{.sig,} || \
     (echo "Could not verify signature of Consul archive!"; exit 1) || exit 1
gpg --verify --quiet vault_${vault_version}_SHA256SUMS{.sig,} || \
     (echo "Could not verify signature of Vault archive!"; exit 1) || exit 1

sha256sum --check --ignore-missing consul_${consul_version}_SHA256SUMS || \
     (echo "Could not verify checksum of Consul archive!"; exit 1) || exit 1
sha256sum --check --ignore-missing vault_${vault_version}_SHA256SUMS || \
     (echo "Could not verify checksum of Vault archive!"; exit 1) || exit 1

for file in *.zip
do
    unzip -d /usr/bin $file || (echo "Could not extract '$file'!"; exit 1) || exit 1
    rm -v $file $${file/linux_amd64.zip/SHA256SUMS}{,.sig}
done

for service in consul vault
do
    mkdir -p /etc/$${service}.d
    useradd --system --user-group --create-home --home-dir /var/lib/$service $service
done

cat <<EOF > /etc/consul.d/bootstrap.json
{
  "data_dir": "/var/lib/consul",
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "enable_token_persistence": true,
    "tokens": {
      "master": "${bootstrap_token}"
    }
  },
  "encrypt": "${consul_encryption_key}",
  "domain": "${domain}",
  "advertise_addr": "$${instance_ip_address}",
  "bind_addr": "$${instance_ip_address}",
  "client_addr": "0.0.0.0",
  "datacenter": "gcp-$${instance_region}",
  "node_name": "$${instance_name}",
  "server": true,
  "bootstrap": true,
  "node_meta": $(get_instance_custom_metadata_value "?recursive=true")
}
EOF

cat <<EOF > /etc/vault.d/bootstrap.json
{
  "storage": [ { "consul": { "address": "http://localhost:8500" } } ],
  "listener": [
      { "tcp": { "address": "127.0.0.1:8200", "tls_disable": true } },
      { "tcp": { "address": "$${instance_ip_address}:8200", "tls_disable": true } }
  ],
  "seal": {
    "gcpckms": {
      "project": "$${project_id}",
      "region": "$${instance_region}",
      "key_ring": "$(get_instance_custom_metadata_value "vault-keyring")",
      "crypto_key": "$(get_instance_custom_metadata_value "vault-cryptokey")"
    }
  }
}
EOF

cat <<EOF > /etc/systemd/system/consul.service
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
Environment="OPTIONS=agent -config-dir=/etc/consul.d/"
EnvironmentFile=-/etc/default/consul
ExecStart=/usr/bin/consul \$OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/vault.service
[Unit]
Description=Vault service
Documentation=https://www.vaultproject.io/
Requires=network-online.target
After=network-online.target

[Service]
PrivateDevices=yes
PrivateTmp=yes
ProtectSystem=full
ProtectHome=read-only
SecureBits=keep-caps
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
Environment="OPTIONS=server -config=/etc/vault.d/"
EnvironmentFile=-/etc/default/vault
ExecStart=/usr/bin/vault \$OPTIONS
KillSignal=SIGINT
TimeoutStopSec=30s
Restart=on-failure
StartLimitInterval=60s
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

systemctl start consul
systemctl start vault

# Sleep a random amount, then try to initialize Vault
# This does check if Vault is already initialized
sleep $[ ( $RANDOM % 30 )  + 10 ]s
export VAULT_ADDR="http://127.0.0.1:8200"
if ! vault operator init -status
then
    vault operator init \
        -recovery-shares=1 -recovery-threshold=1 \
        -recovery-pgp-keys=keybase:reyu -root-token-pgp-key=keybase:reyu \
        -format=json > /tmp/vault-recovery.json
    consul kv put vault-recovery @/tmp/vault-recovery.json
fi
