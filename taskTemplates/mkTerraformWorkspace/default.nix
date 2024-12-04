{ pkgs, lib, ... }:

with lib;
with builtins;
with (import ./util.nix { inherit pkgs; });
with (import ./terranix.nix { inherit pkgs; });

{
  stableId ? null,
  deps ? {},
  tags ? null,
  getOutput ? null,
  src,
  srcNix ? null,
  before ? [],
  backend ? {},
  tfvars ? {},
  path ? [],
  terraform ? pkgs.terraform,
  modules ? null,
  modulesPath ? null, # @deprecated, use linkModules instead as it works on both Linux and macOS
  linkModules ? null,
  afterInit ? null,
  beforeApply ? null,
  afterPlanApply ? null,
  planArgs ? null,
  dynamicNixOSSystems ? null,
  dynamicNixOSSystemVaultSSHRoles ? null,
  impureEnvPassthrough ? null,
  preventDestroy ? false,
}:
let
  terraformPkg = terraform.overrideAttrs (oldAttrs: rec {
    # apply patches:
    # - support a dynamic lock file provided by environment variable
    #   as the src where .tf modules are will be readonly
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

  generatedModulesTfFile = { deps }:
    if modules != null then generateModulesFile (if isFunction modules then (modules { inherit deps; }) else modules) else null;

  getSetupScript = { deps, isShellHook ? false }:
    let
      backendConfigFile = getBackendConfigFile { inherit deps; };
      variablesFile = getVariablesFile { inherit deps; };
    in
    /* when in shellHook mode, we work from the current working directory, so changes to .tf files are reflected without rerunning nix-task shell.
      If modules are passed in, then the _generated.tf will be placed in the current working directory, so will need to be git ignored.

      Outside of shellHook mode, the .tf files are copied to a temporary directory, and terraform commands are run from there. */
    ''
      ${beforeScripts { inherit deps; }}

      # Backend config
      ##
      envsubst < ${backendConfigFile} > $TMPDIR/backendConfig.json

      ##

      export TF_CLI_ARGS_plan="-var-file ${variablesFile}"
      export TF_CLI_ARGS_apply="-var-file ${variablesFile}"
      export TF_CLI_ARGS_destroy="-var-file ${variablesFile}"
      export TF_CLI_ARGS_import="-var-file ${variablesFile}"
      export TF_CLI_ARGS_init="-backend-config=$TMPDIR/backendConfig.json"
      export TF_DATA_DIR="$TMPDIR/.terraform"
      export NIX_TERRAFORM_LOCKFILE_PATH="$TMPDIR/.terraform.lock.hcl"

      ${if isShellHook == true then
        ''

        ''
      else
        ''
        export NIX_TERRAFORM_WORKDIR="$TMPDIR/tf"
        mkdir -p $NIX_TERRAFORM_WORKDIR
        ln -s $PWD/* $NIX_TERRAFORM_WORKDIR/

        cd $NIX_TERRAFORM_WORKDIR
        ''}

      ${if modules != null then "cat ${generatedModulesTfFile { inherit deps; }} > $PWD/_generated.tf" else ""}

      ${if linkModules != null then
        ''
        rm -rf $PWD/_nixTfModules || true
        mkdir -p $PWD/_nixTfModules
        ${concatStringsSep "\n" (mapAttrsToList (name: value: "ln -s ${value} $PWD/_nixTfModules/${name}") linkModules)}
        ''
      else ""}

      ${if modulesPath != null then
      # modulesPath requires nix-task experimental.taskUserNamespaces and Linux
      ''
      mkdir -p $TMPDIR/tfModules
      ${concatStringsSep "\n" (mapAttrsToList (name: value: "ln -s ${value} $TMPDIR/tfModules/${name}") modulesPath)}

      mkdir -p /root/tfModules
      ${pkgs.util-linux}/bin/mount --bind $TMPDIR/tfModules /root/tfModules
      '' else ""}

      ${if srcNix != null then
      let
        generate = ''
          taskEval "task: builtins.toJSON (task.srcNix { deps = (builtins.fromJSON $depsEscaped); })" > _generated.tf.json

          ${if modules != null then ''
            ${concatStringsSep "\n" (
              map (conf: ''
                mkdir -p ./_nixTfModules/${conf.id}
                taskEval "task: builtins.toJSON ((task.moduleSrcNix { deps = (builtins.fromJSON $depsEscaped); }).${conf.id})" > ./_nixTfModules/${conf.id}/_generated.tf.json
              '') (modules { inherit deps; })
            )}
          '' else ""}
        '';
      in
      ''
        depsOut="$(taskGetDeps)"
        depsEscaped="$(jq --null-input -cM --arg deps "$depsOut" '$deps')"

        function reload {
          taskReloadFlake
          ${generate}

          echo "Generated tf.json"
        }

        ${generate}
      '' else ""}

      terraform init || true

      ${if afterInit != null then (if isFunction afterInit then (afterInit { inherit deps; }) else afterInit) else ""}
    '';

  getInitScript = { deps }:
    ''
      ${getSetupScript { inherit deps; }}
    '';

  getShellHook = { deps }:
    ''
      ${getSetupScript { inherit deps; isShellHook = true; }}

      ${pkgs.nodejs}/bin/node ${./dynamicNixOSSystemsFromTerraform}/showDeployables.js
    '';

  getDestroyScript = { deps }:
    ''
      ${getSetupScript { inherit deps; }}

      ${if preventDestroy == true then ''
        echo "This task has preventDestroy set to true"
        exit 1
      '' else ''
        if taskRunShouldApply; then
          # apply with input=false if terminal is not interactive
          if [ -t 0 ] ; then
            terraform destroy
          else
            echo "Non-interactive terminal, will destroy immediately"
            terraform destroy -input=false -auto-approve
          fi
        else
          # if dry run, then only do a terraform plan
          echo "Only running terraform plan as nix-task is in dry-run mode"
          terraform plan -destroy
        fi
      ''}
    '';

  getFetchOutputScript = { deps }:
    ''
      ${getSetupScript { inherit deps; }}

      ${pkgs.nodejs}/bin/node ${./dynamicNixOSSystemsFromTerraform}/dumpDeployablesForOutput.js > $TMPDIR/deployables

      taskSetOutput "$(terraform output -json | ${pkgs.jq}/bin/jq --argjson deployables "$(cat $TMPDIR/deployables)" '{"dynamicNixOSSystems":$deployables} * with_entries(.value |= .value)')"
    '';

  getPlanArgs = { deps }: if planArgs != null then (if isFunction planArgs then (planArgs { inherit deps; }) else planArgs) else "";

  getInitApplyScript = { deps }:
    ''
      ${getInitScript { inherit deps; }}

      ${if beforeApply != null then (if isFunction beforeApply then (beforeApply { inherit deps; }) else beforeApply) else ""}

      if taskRunShouldApply; then
        # apply with input=false if terminal is not interactive
        if [ -t 0 ] ; then
          terraform apply ${getPlanArgs { inherit deps; }}
        else
          echo "Non-interactive terminal, will apply any changes immediately"
          terraform apply -input=false -auto-approve ${getPlanArgs { inherit deps; }}
        fi
      else
        # if dry run, then only do a terraform plan
        echo "Only running terraform plan as nix-task is in dry-run mode"
        terraform plan ${getPlanArgs { inherit deps; }}
      fi

      ${if afterPlanApply != null then (if isFunction afterPlanApply then (afterPlanApply { inherit deps; }) else afterPlanApply) else ""}

      ${pkgs.nodejs}/bin/node ${./dynamicNixOSSystemsFromTerraform}/dumpDeployablesForOutput.js > $TMPDIR/deployables

      taskSetOutput "$(terraform output -json | ${pkgs.jq}/bin/jq --argjson deployables "$(cat $TMPDIR/deployables)" '{"dynamicNixOSSystems":$deployables} * with_entries(.value |= .value)')"
    '';

  needsToBeLazy = isFunction backend || isFunction before || isFunction tfvars || isFunction modules;

  deployNixOSSystem = pkgs.writeShellScriptBin "deployNixOSSystem" ''
    set -e

    tfAttr="$1"
    switchMode="$2"

    ${pkgs.nodejs}/bin/node ${./dynamicNixOSSystemsFromTerraform}/deploySystem.js "$1" "$2"
  '';
in
mkTask {
  inherit stableId;
  inherit deps;
  inherit tags;
  inherit getOutput;
  inherit impureEnvPassthrough;
  dir = src;
  path = with pkgs; [
    nix
    terraformPkg
    envsubst
    lib.mixins.dynamicNixOSSystems.commands
    deployNixOSSystem

    # include vault, nix-task-contrib is opinionated in that vault is used for a lot of tasks, so include it here to make life easier
    vault

    # include baseline of tools that are used by a lot of terraform scripts
    bash
    coreutils
    jq
    procps
    openssh
    gawk
    curl
    wget
    unzip
    libxslt
  ] ++ path;
  run =
    if needsToBeLazy then ({ deps }: getInitApplyScript { inherit deps; }) else (getInitApplyScript { deps = {}; });
  shellHook =
    if needsToBeLazy then ({ deps }: getShellHook { inherit deps; }) else (getShellHook { deps = {}; });
  custom.destroy = if needsToBeLazy then ({ deps }: getDestroyScript { inherit deps; }) else (getDestroyScript { deps = {}; });
  fetchOutput = if needsToBeLazy then ({ deps }: getFetchOutputScript { inherit deps; }) else (getFetchOutputScript { deps = {}; });
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
// (if srcNix != null then {
  srcNix = args: (mkTerranixConfiguration { config = (srcNix args); });
  moduleSrcNix = args: listToAttrs (
    map (
      conf: {
        name = conf.id;
        value = if (conf.srcNix or null) != null then (mkTerranixConfiguration { config = conf.srcNix; }) else null;
      }
    ) (if modules != null then modules args else [])
  );
} else {})
