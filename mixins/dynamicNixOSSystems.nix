{ pkgs, lib, ... }:

with lib;
with builtins;

let
  deployDynamicNixOSSystem = pkgs.writeShellScriptBin "deployDynamicNixOSSystem" ''
    set -e
    export PATH=$PATH:${pkgs.nix}/bin:${pkgs.git}/bin:${pkgs.jq}/bin:${pkgs.openssh}/bin

    mode="$4" # switch, boot, switch-unsafe (defaults to switch)
    remote="$2"
    remoteEscaped="$(jq --null-input -cM --arg remote "$remote" '$remote')"
    argsJsonEscaped="$(jq --null-input -cM --arg jsonIn "$3" '$jsonIn')"

    depsOut="$(taskGetDeps)"
    depsEscaped="$(jq --null-input -cM --arg deps "$depsOut" '$deps')"

    case "$mode" in
      "boot")
        echo "Deploying system for activation on next boot"

        systemDrv="$(nix eval --raw \
          --apply "a: (a ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped))).config.system.build.toplevel.drvPath" \
          $NIX_TASK_FLAKE_PATH.dynamicNixOSSystems.$1)"

        systemOut="$(nix-store --realise $systemDrv)"

        nix-copy-closure --to $remote \
          $systemOut

        ssh -o BatchMode=yes "$remote" \
          "sudo nix-env -p /nix/var/nix/profiles/system --set $systemOut && sudo $systemOut/bin/switch-to-configuration boot"

        echo "Success"
        ;;
      "switch-unsafe")
        echo "Deploying system immediately using switch-to-configuration, this may break connectivity with the host"
        echo "Ctrl+C now if you would like to cancel this operation"

        systemDrv="$(nix eval --raw \
          --apply "a: (a ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped))).config.system.build.toplevel.drvPath" \
          $NIX_TASK_FLAKE_PATH.dynamicNixOSSystems.$1)"

        systemOut="$(nix-store --realise $systemDrv)"

        nix-copy-closure --to $remote \
          $systemOut

        ssh -o BatchMode=yes "$remote" \
          "sudo nix-env -p /nix/var/nix/profiles/system --set $systemOut && sudo $systemOut/bin/switch-to-configuration switch"

        echo "Success"
        ;;
      "build")
        systemDrv="$(nix eval --raw \
          --apply "a: (a ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped))).config.system.build.toplevel.drvPath" \
          $NIX_TASK_FLAKE_PATH.dynamicNixOSSystems.$1)"

        nix-store --realise $systemDrv
        ;;
      *)
        echo "Deploying system using Nixus, will rollback if there are any issues"

        nixApplyExpr=$(cat <<EOF
flake:
  let
    systemConfig = (flake.dynamicNixOSSystems.$1 ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped)));
  in
  (flake.dynamicDeployScript {
    out = systemConfig.config.system.build.toplevel;
    args = {
      pkgs = systemConfig.pkgs;
      nixpkgs = systemConfig.pkgs.path;
      deploy = systemConfig.config.deploy;
      system = systemConfig.config.system.build.toplevel.system;
      name = "$1";
    };
    remote = $remoteEscaped;
  }).$1.drvPath
EOF
)

        deployScriptDrv="$(nix eval --raw \
          --apply "$nixApplyExpr" \
          $NIX_TASK_FLAKE_PATH)"

        deployScriptOut="$(nix-store --realise $deployScriptDrv)"

        $deployScriptOut
        ;;
    esac
  '';

  tfQueryDynamicNixOSSystem = pkgs.writeShellScriptBin "tfQueryDynamicNixOSSystem" ''
    set -e
    export PATH=$PATH:${pkgs.nix}/bin:${pkgs.git}/bin:${pkgs.jq}/bin:${pkgs.openssh}/bin

    inData="$(jq -r -cM)"
    argsJsonEscaped="$(jq --null-input -cM --arg jsonIn "$inData" '$jsonIn')"
    nameEscaped="$(jq --null-input -cM --arg nameIn "$1" '$nameIn')"

    depsOut="$(taskGetDeps)"
    depsEscaped="$(jq --null-input -cM --arg deps "$depsOut" '$deps')"

    nix eval --json \
      --apply "a: with (a ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped))); { out = config.system.build.toplevel; args = builtins.toJSON ({ nixpkgs = pkgs.path; deploy = config.deploy; system = config.system.build.toplevel.system; name = $nameEscaped; }); }" \
      $NIX_TASK_FLAKE_PATH.dynamicNixOSSystems.$1
  '';

  tfDeployDynamicNixOSSystem = pkgs.writeShellScriptBin "tfDeployDynamicNixOSSystem" ''
    set -e
    export PATH=$PATH:${pkgs.nix}/bin:${pkgs.git}/bin:${pkgs.jq}/bin:${pkgs.openssh}/bin

    remote="$1"
    system="$2"
    args="$args"

    systemDrv="$(nix show-derivation $system | jq -r 'keys[0]')"

    # make sure system is built and realised first
    nix-store --realise $systemDrv

    name="$(echo $args | jq -r '.name')"

    argsJson="$(jq --null-input -cM --argjson args $args --arg out $system --arg remote $remote '{args:$args,out:$out,remote:$remote}')"
    argsJsonEscaped="$(jq --null-input -cM --arg argsJson "$argsJson" '$argsJson')"

    deployScriptDrv="$(nix eval --impure --raw \
      --apply "a: (a (builtins.fromJSON $argsJsonEscaped)).$name.drvPath" \
      $NIX_TASK_FLAKE_PATH.dynamicDeployScript)"

    deployScriptOut="$(nix-store --realise $deployScriptDrv)"

    $deployScriptOut
  '';
in
{
  commands = pkgs.runCommand "dynamicnixossystem-commands"
    {}
    ''
      mkdir -p $out/bin/
      cp ${deployDynamicNixOSSystem}/bin/* $out/bin/
      cp ${tfQueryDynamicNixOSSystem}/bin/* $out/bin/
      cp ${tfDeployDynamicNixOSSystem}/bin/* $out/bin/
    '';

  output = {
    dynamicDeployScript = { args, out, remote }:
      import nixus { deploySystem = args.system; } ({ config, ... }: {
        nodes = {
          ${args.name} = ({ lib, config, ... }: ({
            nixpkgs = args.nixpkgs;
            configuration = {
              _pkgs = if (hasAttr "pkgs" args) then args.pkgs else (import args.nixpkgs {});
              system.build.toplevel = out;
            };
          } // args.deploy // {
            host = remote;
          }));
        };
      });
  };

  writeAnsibleInventory = { deps, tasksWithHosts }:
    let
      tasksWithHostsById = listToAttrs (map (task: { name = task.id; value = task; }) tasksWithHosts);
      hosts = flatten (map (task:
        let
          systems = tasksWithHostsById."${task.id}".getDynamicNixOSSystems (if hasAttr task.id deps then deps."${task.id}".output else {});
        in
        systems
      ) tasksWithHosts);
      ansibleInventory = {
        all = {
          hosts = listToAttrs (map (host:
            let
              remoteSplit = splitString "@" host.remote;
              user = (elemAt remoteSplit 0);
              remoteHost = (elemAt remoteSplit 1);
            in
            {
              name = remoteHost;
              value = {
                ansible_user = user;
              };
            }) hosts);
        };
      };
    in
    ''
      export ANSIBLE_INVENTORY=$TMPDIR/ansible-inventory.json

      echo ${builtins.toJSON (builtins.toJSON (ansibleInventory))} > $ANSIBLE_INVENTORY
    '';
}
