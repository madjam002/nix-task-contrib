{ pkgs, lib, ... }:

let
  terraformVaultHttpBackend = pkgs.callPackage ../packages/terraform-vault-http-backend {};

  vaultHttpBackendBackgroundScript = ''
    PORT_FILE="$TMPDIR/.http-backend-port"

    pushd ${terraformVaultHttpBackend} > /dev/null

    if [ -f "$PORT_FILE" ]; then
      export BACKEND_PORT="$(cat $PORT_FILE)"
    fi

    if [ "$VAULT_SKIP_VERIFY" = "1" ]; then
      export NODE_TLS_REJECT_UNAUTHORIZED="0"
    fi

    taskRunInBackground NODE_EXTRA_CA_CERTS="$SSL_CERT_FILE" \
      PORT_FILE="$PORT_FILE" \
      PORT="$BACKEND_PORT" \
      ${pkgs.nodejs}/bin/node .

    # wait for server to start
    while [ ! -f "$PORT_FILE" ]
    do
      sleep 0.1
    done

    BACKEND_PORT="$(cat $PORT_FILE)"

    while ! ${pkgs.netcat}/bin/nc -z localhost $BACKEND_PORT; do
      sleep 0.1
    done

    export BACKEND_BASE_URL="http://localhost:$BACKEND_PORT"

    popd > /dev/null
  '';
in
vaultHttpBackendBackgroundScript
