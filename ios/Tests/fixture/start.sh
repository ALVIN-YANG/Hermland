#!/usr/bin/env bash
set -euo pipefail
[[ -f /.dockerenv && ${HERMLAND_IOS_TEST:-} == isolated ]] || exit 2
mkdir -p /run/sshd /etc/hermland/ssh-devices
ssh-keygen -q -t ed25519 -N '' -f /tmp/hermland-test-host
useradd --no-create-home --shell /usr/sbin/nologin hl-iphone001
usermod --password '*' hl-iphone001
useradd --no-create-home --shell /usr/sbin/nologin hl-iphone002
usermod --password '*' hl-iphone002
python3 /fixture/serve.py &
exec /usr/sbin/sshd -D -e -h /tmp/hermland-test-host -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no \
    -o AuthenticationMethods=publickey -o AuthorizedKeysFile=/etc/hermland/ssh-devices/%u.pub \
    -o ForceCommand=/bin/false -o PermitTTY=no -o AllowTcpForwarding=local \
    -o GatewayPorts=no -o AllowAgentForwarding=no -o X11Forwarding=no -o PermitTunnel=no
