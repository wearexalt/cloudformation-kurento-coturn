#!/usr/bin/env bash

#/ AWS CloudFormation init script.
#/
#/ This script is downloaded and executed from the Kurento AWS CloudFormation
#/ template, during the instance initialization phase.
#/
#/ Note that `sudo` is not needed: this script runs from the Ubuntu AMI's
#/ user data section (for `cloud-init`), and `cloud-init` already runs as root.
#/
#/ Log file for debug: /var/log/cfn-init.log

# Bash options for strict error checking.
set -o errexit -o errtrace -o pipefail -o nounset
shopt -s inherit_errexit 2>/dev/null || true

# Trace all commands (to stderr).
set -o xtrace



# Kurento Media Server
# ====================

# Make sure that GnuPG is installed (needed for `apt-key adv`).
apt-get update ; apt-get install --yes gnupg

# Import the Kurento repository signing key.
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 5AFA7A83

# Get Ubuntu version definitions.
source /etc/lsb-release

# Add the repository to Apt.
tee /etc/apt/sources.list.d/kurento.list >/dev/null <<EOF
# Kurento Media Server - Release packages
deb [arch=amd64] http://ubuntu.openvidu.io/{{KmsVersion}} ${DISTRIB_CODENAME} kms6
EOF

# Install.
apt-get update ; apt-get install --yes kurento-media-server

# Enable system service.
systemctl enable kurento-media-server


# Coturn
# ======

# Certbot
snap install core; sudo snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
certbot certonly --standalone --non-interactive --agree-tos -m "kurento@thatsuseful.com"

# Install.
apt-get update 
apt-get install --yes coturn certbot kurento-media-server

# Enable system service.
tee /etc/default/coturn >/dev/null <<'EOF'
TURNSERVER_ENABLED=1
EOF

# Configure.
# shellcheck disable=2154
tee /etc/turnserver.conf >/dev/null <<'EOF'
# The external IP address of this server, if Coturn is behind a NAT.
# It must be an IP address, not a domain name.
#listening-ip=<privateIp>
#external-ip=<publicIp>/<privateIp>

# STUN listener port for UDP and TCP.
# Default: 3478.
#listening-port=3478

# TURN lower and upper bounds of the UDP relay ports.
# Default: 49152, 65535.
min-port=57001
max-port=65535

# Uncomment to enable moderately verbose logs.
# Default: verbose mode OFF.
verbose

# TURN fingerprints in messages.
fingerprint

# TURN long-term credential mechanism.
lt-cred-mech

# TURN static user account for long-term credential mechanism.
user={{TurnUser}}:{{TurnPassword}}

# TURN realm used for the long-term credential mechanism.
realm=xaltexperiences.com

# Set the log file name.
# The log file can be reset sending a SIGHUP signal to the turnserver process.
log-file=/var/log/turn.log

# Disable log file rollover and use log file name as-is.
simple-log

# Secure form for password 'qwerty':
cli-password=$5$79a316b350311570$81df9cfb9af7f5e5a76eada31e7097b663a0670f99a3c07ded3f1c8e59c5658a

# Certificate file.
cert=/etc/letsencrypt/live/turn.xaltexperiences.com/fullchain.pem

# Private key file
pkey=/etc/letsencrypt/live/turn.xaltexperiences.com/privkey.pem
EOF

# Create the log file, with correct permissions.
install -o turnserver -g turnserver -m 644 /dev/null /var/log/turn.log



# Launch script
# =============

tee /usr/local/bin/launch-kms.sh >/dev/null <<'EOF'
#!/usr/bin/env bash

# Bash options for strict error checking.
set -o errexit -o errtrace -o pipefail -o nounset
shopt -s inherit_errexit 2>/dev/null || true

# Settings.
# Uses the AWS link-local address to retrieve instance metadata:
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
PRIVATE_IP="$(curl --silent "http://169.254.169.254/latest/meta-data/local-ipv4")"
PUBLIC_IP="$(curl --silent "http://169.254.169.254/latest/meta-data/public-ipv4")"
EXTERNAL_IP="${PUBLIC_IP}\/${PRIVATE_IP}"

# Aux function: set value to a given parameter.
function set_parameter {
    local FILE="$1"         # File path to be edited.
    local PARAM="$2"        # Parameter to be set.
    local VALUE="$3"        # Value to be set into PARAM.
    local COMMENT="${4:-;}" # (Optional) Character used for commented-out lines.

    local REGEX="^${COMMENT}?\s*${PARAM}=.*"

    if grep --extended-regexp -q "${REGEX}" "${FILE}"; then
        sed --regexp-extended -i "s/${REGEX}/${PARAM}=${VALUE}/" "${FILE}"
    else
        echo "${PARAM}=${VALUE}" >>"${FILE}"
    fi
}

# Config for Coturn.
set_parameter /etc/turnserver.conf "listening-ip" "${PRIVATE_IP}" "#"
set_parameter /etc/turnserver.conf "external-ip" "${EXTERNAL_IP}" "#"
systemctl restart coturn

# Config for Kurento Media Server.
set_parameter /etc/kurento/modules/kurento/BaseRtpEndpoint.conf.ini "minPort" "40000" ";"
set_parameter /etc/kurento/modules/kurento/BaseRtpEndpoint.conf.ini "maxPort" "57000" ";"
set_parameter /etc/kurento/modules/kurento/WebRtcEndpoint.conf.ini "turnURL" "{{TurnUser}}:{{TurnPassword}}@${PUBLIC_IP}:3478" ";"
systemctl restart kurento-media-server
EOF
chmod 755 /usr/local/bin/launch-kms.sh

# System startup script.
tee /etc/rc.local >/dev/null <<'EOF'
#!/bin/sh -e
/usr/local/bin/launch-kms.sh
exit 0
EOF

echo "Launching Media Server..."
/usr/local/bin/launch-kms.sh
