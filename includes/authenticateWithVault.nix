{ pkgs, lib, ... }:

{ vault, INSECUREvaultSkipVerify ? false }:
  ''
    ${if INSECUREvaultSkipVerify then ''
      echo ""
      echo "******* INSECURE ******** VAULT TLS CHAIN WON'T BE VERIFIED ******************"
      echo ""

      export VAULT_SKIP_VERIFY=1
    '' else ""}

    export VAULT_ADDR="${vault.address}"
    export VAULT_TOKEN="$(HOME=$IMPURE_HOME PATH=$PATH:/${pkgs.ruby}/bin ${pkgs.vault}/bin/vault token lookup -format=json | ${pkgs.jq}/bin/jq -r '.data.id')"
  ''
