#!/usr/bin/env bash
# Distrust every eMudhra (emSign) root and AAA Certificate Services, then
# regenerate the extracted CA bundles. See recipes/recipe.yml for why.
#
# The PEMs in files/system/etc/pki/ca-trust/source/blocklist/ were copied by
# the files module, but the base image's ca-certificates package moves: it can
# trust emSign roots that are not in that directory (emSign Root CS CA - G2
# did not exist in the Aurora image when the directory was written). So every
# emSign or AAA anchor the base currently trusts is blocklisted here too, and
# the build fails if any survives.
set -euo pipefail

blocklist=/etc/pki/ca-trust/source/blocklist
mkdir -p "${blocklist}"

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

# Extraction is per purpose and defaults to server-auth, which misses roots
# trusted only for email or code signing (emSign Root CA - C2 and G2).
for purpose in server-auth email code-signing; do
    trust extract --format=pem-bundle --filter=ca-anchors --purpose="${purpose}" \
        "${work}/${purpose}.pem"
done
cat "${work}"/*.pem > "${work}/anchors.pem"

python3 -I - "${work}/anchors.pem" "${blocklist}" <<'EOF'
import re, subprocess, sys

bundle, dest = sys.argv[1:3]
pattern = re.compile(r"OU=emSign PKI|O=eMudhra|CN=emSign|CN=AAA Certificate Services")
blocks = re.findall(
    r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\n",
    open(bundle).read(), re.S)
for block in blocks:
    subject = subprocess.run(
        ["openssl", "x509", "-noout", "-subject", "-nameopt", "RFC2253"],
        input=block, capture_output=True, text=True, check=True).stdout
    if pattern.search(subject):
        cn = re.search(r"CN=([^,\n]*)", subject).group(1)
        name = re.sub(r"[^a-z0-9]+", "-", cn.lower()).strip("-")
        open(f"{dest}/{name}.pem", "w").write(block)
        print(f"blocklisted: {cn}")
EOF

update-ca-trust extract

# Blocklisted certificates stay in `trust list` as "trust: distrusted", so
# check the anchors that are actually trusted instead.
if trust list --filter=ca-anchors | grep -iE "label: .*(emSign|eMudhra|AAA Certificate Services)"; then
    echo "ERROR: eMudhra or AAA roots are still trusted"; exit 1
fi
echo "emSign and AAA Certificate Services are distrusted."
