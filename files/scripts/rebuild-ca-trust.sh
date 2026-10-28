#!/usr/bin/env bash
# Regenerate the extracted CA bundles after the blocklist is copied in.
# See recipes/recipe.yml for why the blocklist exists.
#
# files/system/etc/pki/ca-trust/source/blocklist/*.pem is copied by the files
# module, but the extracted bundles under /etc/pki/ca-trust/extracted are
# built artifacts: nothing reads the blocklist until update-ca-trust runs.
set -euo pipefail

update-ca-trust extract

# Blocklisted certificates stay in `trust list` as "trust: distrusted", so
# check the anchors that are actually trusted instead.
for cn in "emSign" "AAA Certificate Services"; do
    if trust list --filter=ca-anchors | grep -q "label: .*${cn}"; then
        echo "ERROR: ${cn} is still trusted"; exit 1
    fi
done
echo "emSign and AAA Certificate Services are distrusted."
