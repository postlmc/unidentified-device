# Point clients that ship their own CA bundle (Homebrew's azure-cli certifi,
# portable-ruby, brew's ca-certificates) at the system bundle, so the eMudhra
# and AAA blocklist in /etc/pki/ca-trust/source/blocklist applies to them too.
# Login shells only; see recipes/recipe.yml for why those roots are distrusted.
export REQUESTS_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
export SSL_CERT_FILE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
export CURL_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
