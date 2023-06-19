{ pkgs, lib, ... }:

let
  tokenHelperBin = pkgs.writeScript "vault-token-helper.rb" ''
    #!${pkgs.ruby}/bin/ruby
    ${builtins.readFile ./vault-token-helper.rb}
  '';

  vaultWithTokenHelperConfig =
    pkgs.writeTextFile {
      name = "vault";
      text = ''
        token_helper = "${tokenHelperBin}"
      '';
    };
in
{ vault, additional ? [], INSECUREvaultSkipVerify ? false }:
  ''
    ${if INSECUREvaultSkipVerify then ''
      echo ""
      echo "******* INSECURE ******** VAULT TLS CHAIN WON'T BE VERIFIED ******************"
      echo ""

      export VAULT_SKIP_VERIFY=1
    '' else ""}

    # set default vault server
    export VAULT_ADDR="${vault.address}"

    ${lib.concatStringsSep "\n" (
      map (_vault: ''
      thisToken="$(HOME=$IMPURE_HOME VAULT_ADDR=${_vault.address} ${pkgs.vault}/bin/vault token lookup -format=json | ${pkgs.jq}/bin/jq -r '.data.id')"
      echo -n "$thisToken" | VAULT_ADDR="${_vault.address}" ${tokenHelperBin} store
      '') ([vault] ++ additional)
    )}

    # set config file so that the token helper is used when we use vault
    export VAULT_CONFIG_PATH="${vaultWithTokenHelperConfig}"

    function getVaultToken {
      export VAULT_CONFIG_PATH="${vaultWithTokenHelperConfig}"
      if [ -z "$1" ]
      then
        ${pkgs.vault}/bin/vault token lookup -format=json | ${pkgs.jq}/bin/jq -r '.data.id'
      else
        VAULT_ADDR="$1" ${pkgs.vault}/bin/vault token lookup -format=json | ${pkgs.jq}/bin/jq -r '.data.id'
      fi
    }
  ''
