{ pkgs, lib, ... }:

with lib;
with builtins;

{
  id ? null,
  deps ? {},
  getOutput ? null,
  src,
  before ? [],
  backend ? {},
  tfvars ? {},
  path ? [],
  terraform ? pkgs.terraform,
  dynamicNixOSSystems ? null,
  dynamicNixOSSystemVaultSSHRoles ? null,
}:
let
  terraformPkg = terraform.overrideAttrs (oldAttrs: rec {
    # we patch terraform to support a dynamic lock file provided by environment variable
    # as the src where .tf modules are will be readonly
    patches = oldAttrs.patches ++ [ ./dynamicLockFile.patch ];
  });

  getBackendConfigFile = { deps }:
    builtins.toFile "backendConfig.json" (builtins.toJSON (
      if isFunction backend then (backend { inherit deps; }) else backend
    ));

  getVariablesFile = { deps }:
    builtins.toFile "terraform.tfvars.json" (builtins.toJSON (
      if isFunction tfvars then (tfvars { inherit deps; }) else tfvars
    ));

  beforeScripts = { deps }:
    builtins.concatStringsSep "\n" (if isFunction before then (before { inherit deps; }) else before);

  getSetupScript = { deps }:
    let
      backendConfigFile = getBackendConfigFile { inherit deps; };
      variablesFile = getVariablesFile { inherit deps; };
    in
    ''
      ${beforeScripts { inherit deps; }}

      # Backend config
      ##
      envsubst < ${backendConfigFile} > $TMPDIR/backendConfig.json

      ##

      export TF_CLI_ARGS_plan="-var-file ${variablesFile}"
      export TF_CLI_ARGS_apply="-var-file ${variablesFile}"
      export TF_CLI_ARGS_import="-var-file ${variablesFile}"
      export TF_CLI_ARGS_init="-backend-config=$TMPDIR/backendConfig.json"
      export TF_DATA_DIR="$TMPDIR/.terraform"
      export NIX_TERRAFORM_LOCKFILE_PATH="$TMPDIR/.terraform.lock.hcl"

      terraform init
    '';

  getInitScript = { deps }:
    ''
      ${getSetupScript { inherit deps; }}
    '';

  getShellHook = { deps }:
    ''
      ${getSetupScript { inherit deps; }}

      ${pkgs.nodejs}/bin/node ${./dynamicNixOSSystemsFromTerraform}/showDeployables.js
    '';

  getInitApplyScript = { deps }:
    ''
      ${getInitScript { inherit deps; }}

      # apply with input=false if terminal is not interactive
      if [ -t 0 ] ; then
        terraform apply
      else
        echo "Non-interactive terminal, will apply any changes immediately"
        terraform apply -input=false -auto-approve
      fi

      ${pkgs.nodejs}/bin/node ${./dynamicNixOSSystemsFromTerraform}/dumpDeployablesForOutput.js > $TMPDIR/deployables

      taskSetOutput "$(terraform output -json | ${pkgs.jq}/bin/jq --argjson deployables "$(cat $TMPDIR/deployables)" '{"dynamicNixOSSystems":$deployables} * with_entries(.value |= .value)')"
    '';

  needsToBeLazy = isFunction backend || isFunction before || isFunction tfvars;

  deployNixOSSystem = pkgs.writeShellScriptBin "deployNixOSSystem" ''
    set -e

    tfAttr="$1"
    switchMode="$2"

    ${pkgs.nodejs}/bin/node ${./dynamicNixOSSystemsFromTerraform}/deploySystem.js "$1" "$2"
  '';
in
lib.mkTask {
  inherit id;
  inherit deps;
  inherit getOutput;
  dir = src;
  path = with pkgs; [
    terraformPkg
    envsubst
    lib.mixins.dynamicNixOSSystems.commands
    deployNixOSSystem
  ] ++ path;
  run =
    if needsToBeLazy then ({ deps }: getInitApplyScript { inherit deps; }) else (getInitApplyScript { deps = {}; });
  shellHook =
    if needsToBeLazy then ({ deps }: getShellHook { inherit deps; }) else (getShellHook { deps = {}; });
}
// lib.mixins.dynamicNixOSSystems.output
// (if dynamicNixOSSystems != null then {
  inherit dynamicNixOSSystems;
  getDynamicNixOSSystems = output: if hasAttr "dynamicNixOSSystems" output then output.dynamicNixOSSystems else [];
  inherit dynamicNixOSSystemVaultSSHRoles;
} else {})
// (if dynamicNixOSSystems != null && dynamicNixOSSystemVaultSSHRoles != null then {
  inherit dynamicNixOSSystemVaultSSHRoles;
} else {})
