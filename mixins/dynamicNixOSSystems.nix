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

    ${lib.scripts.configureSSHHost}/bin/configureSSHHost "$remote" \
      StrictHostKeyChecking=no UserKnownHostsFile=$(mktemp)

    export NIX_SSHOPTS="-F $HOME/.ssh/config"

    case "$mode" in
      "boot")
        echo "Deploying system for activation on next boot"

        systemDrv="$(taskEval "task: (task.dynamicNixOSSystems.$1 ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped))).config.system.build.toplevel.drvPath")"

        systemOut="$(nix-store --realise $systemDrv)"

        nix-copy-closure -s --to $remote \
          $systemOut

        ssh -F $HOME/.ssh/config -o BatchMode=yes "$remote" \
          "sudo nix-env -p /nix/var/nix/profiles/system --set $systemOut && sudo $systemOut/bin/switch-to-configuration boot"

        echo "Success"
        ;;
      "switch-unsafe")
        echo "Deploying system immediately using switch-to-configuration, this may break connectivity with the host"
        echo "Ctrl+C now if you would like to cancel this operation"

        systemDrv="$(taskEval "task: (task.dynamicNixOSSystems.$1 ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped))).config.system.build.toplevel.drvPath")"

        systemOut="$(nix-store --realise $systemDrv)"

        nix-copy-closure -s --to $remote \
          $systemOut

        ssh -F $HOME/.ssh/config -o BatchMode=yes "$remote" \
          "sudo nix-env -p /nix/var/nix/profiles/system --set $systemOut && sudo $systemOut/bin/switch-to-configuration switch"

        echo "Success"
        ;;
      "build")
        systemDrv="$(taskEval "task: (task.dynamicNixOSSystems.$1 ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped))).config.system.build.toplevel.drvPath")"

        nix-store --realise $systemDrv
        ;;
      "deploy-anywhere-yes-i-really-want-to-do-this")
        # EXPERIMENTAL
        systemDrv="$(taskEval "task: (task.dynamicNixOSSystems.$1 ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped))).config.system.build.toplevel.drvPath")"
        systemPath="$(nix-store --realise $systemDrv)"

        diskoDrv=$(taskEval "task: (task.dynamicNixOSSystems.$1 ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped))).config.system.build.diskoScript.drvPath")
        diskoPath="$(nix-store --realise $diskoDrv)"

        # TODO is it okay to expect this to be in PATH?
        nixos-anywhere -s $diskoPath $systemPath "''${@:5}" "$remote"
        ;;
      *)
        echo "Deploying system using Nixus, will rollback if there are any issues"

        nixApplyExpr=$(cat <<EOF
task:
  let
    systemConfig = (task.dynamicNixOSSystems.$1 ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped)));
  in
  (task.dynamicDeployScript {
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

        deployScriptDrv="$(taskEval "$nixApplyExpr")"

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

    taskEval "let inArgs = { deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $argsJsonEscaped); in task: with (task.dynamicNixOSSystems.$1 (inArgs)); __toJSON ({ out = config.system.build.toplevel; args = builtins.toJSON ({ nixpkgs = pkgs.path; deploy = config.deploy; system = config.system.build.toplevel.system; name = $nameEscaped; systemArgs = inArgs; }); })"
  '';

  tfDeployDynamicNixOSSystem = pkgs.writeShellScriptBin "tfDeployDynamicNixOSSystem" ''
    set -e
    export PATH=$PATH:${pkgs.nix}/bin:${pkgs.git}/bin:${pkgs.jq}/bin:${pkgs.openssh}/bin

    remote="$1"
    system="$2"
    mode="$3"
    args="$args"

    systemDrv="$(nix show-derivation $system | jq -r 'keys[0]')"

    # make sure system is built and realised first
    nix-store --realise $systemDrv

    name="$(echo $args | jq -r '.name')"

    argsJson="$(jq --null-input -cM --argjson args "$args" --arg out "$system" --arg remote "$remote" '{args:$args,out:$out,remote:$remote}')"
    argsJsonEscaped="$(jq --null-input -cM --arg argsJson "$argsJson" '$argsJson')"

    case "$mode" in
      "boot")
        echo "Deploying system for activation on next boot"

        systemOut="$(nix-store --realise $systemDrv)"

        nix-copy-closure --to $remote \
          $systemOut

        ssh -F $HOME/.ssh/config -o BatchMode=yes "$remote" \
          "sudo nix-env -p /nix/var/nix/profiles/system --set $systemOut && sudo $systemOut/bin/switch-to-configuration boot"

        echo "Success"
        ;;
      *)
        echo "Deploying system using Nixus, will rollback if there are any issues"

        deployScriptDrv="$(taskEval "task: (task.dynamicDeployScript (builtins.fromJSON $argsJsonEscaped)).$name.drvPath")"

        echo $deployScriptDrv

        deployScriptOut="$(nix-store --realise $deployScriptDrv)"

        ${lib.scripts.configureSSHHost}/bin/configureSSHHost "$remote" \
          StrictHostKeyChecking=no UserKnownHostsFile=$(mktemp)

        $deployScriptOut
        ;;
    esac
  '';

  tfBuildDiskImageForDynamicNixOSSystem = pkgs.writeShellScriptBin "tfBuildDiskImageForDynamicNixOSSystem" ''
    set -e
    export PATH=$PATH:${pkgs.nix}/bin:${pkgs.git}/bin:${pkgs.jq}/bin:${pkgs.openssh}/bin

    system="$1"
    args="$args"

    name="$(echo $args | jq -r '.name')"

    argsJson="$(jq --null-input -cM --argjson args "$args" --arg out "$system" '{args:$args,out:$out}')"
    argsJsonEscaped="$(jq --null-input -cM --arg argsJson "$argsJson" '$argsJson')"

    diskImage="$(nix eval --impure --json \
      --apply "flake: let args = (builtins.fromJSON $argsJsonEscaped).args; out = (flake.dynamicSystemDiskImage (flake.dynamicNixOSSystems.\''${args.name} args.systemArgs)); in { drvPath = out.image.drvPath; filename = out.filename; }" \
      $NIX_TASK_FLAKE_PATH)"

    diskImageDrv="$(echo $diskImage | jq -r '.drvPath')"
    filename="$(echo $diskImage | jq -r '.filename')"

    nix-store --realise $diskImageDrv > /dev/null

    diskImagePath="$(nix-store --query $diskImageDrv)/$filename"

    jq --null-input -cM --arg path "$diskImagePath" '{path:$path}'
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
      cp ${tfBuildDiskImageForDynamicNixOSSystem}/bin/* $out/bin/
    '';

  output = {
    dynamicDeployScript = { args, out, remote }:
      import nixus { deploySystem = args.system; hostPkgs = pkgs; } ({ config, ... }: {
        nodes = {
          ${args.name} = ({ lib, config, ... }: ({
            nixpkgs = args.nixpkgs;
            configuration = {
              _pkgs = if (hasAttr "pkgs" args) then args.pkgs else (import args.nixpkgs { system = args.system; });
              system.build.toplevel = out;
            };
          } // (filterAttrs (k: v: k != "diskOptions") args.deploy) // {
            host = remote;
          }));
        };
      });

    dynamicSystemDiskImage = system:
      let
        diskImageOptions = {
          pkgs = system.pkgs;
          lib = system.pkgs.lib;
          config = system.config;

          format = "qcow2";
          diskSize = 16 * 1024;
          partitionTableType = "efi";
          fsType = "ext4";
        } // (if hasAttr "diskOptions" system.config.deploy then system.config.deploy.diskOptions else {});

        filename = "nixos." + {
          qcow2 = "qcow2";
          vdi   = "vdi";
          vpc   = "vhd";
          raw   = "img";
        }.${diskImageOptions.format} or diskImageOptions.format;
      in
      {
        image = (import "${pkgs.path}/nixos/lib/make-disk-image.nix") (diskImageOptions);
        inherit filename;
      };
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
