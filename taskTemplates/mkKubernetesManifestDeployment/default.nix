{ pkgs, lib, ... }:

with lib;
with builtins;

{
  stableId ? null,
  tags ? null,
  deps ? {},
  getOutput ? null,
  before ? [],
  manifests,
  kubectlArgs ? { deps }: "",
  applyScript ? { deps }: ''
    MANIFEST=`renderManifest default`
    echo "$MANIFEST" | kubectl apply $kubectlArgs --wait -f -
  '',
  dryRunScript ? { deps }: ''
    MANIFEST=`renderManifest default`
    echo "$MANIFEST" | kubectl apply $kubectlArgs --dry-run=server --wait -f -
  '',
  afterApply ? null,
  fetchOutput ? null,
  custom ? {},
  path ? [],
}:
let
  beforeScripts = { deps }:
    builtins.concatStringsSep "\n" (if isFunction before then (before { inherit deps; }) else before);

  initScript = { deps }:
    let
      _kubectlArgs = kubectlArgs { inherit deps; };
    in
    ''
      ${beforeScripts { inherit deps; }}

      renderManifest() {
        manifestAttr=$1
        shift # remove first arg value from rest below
        rest="$@"

        if [ -n "$1" ]; then
          additionalArgs="$(jo $rest)"
        else
          additionalArgs="{}"
        fi
        additionalArgsJson="$(jq --null-input -cM --arg additionalArgs "$additionalArgs" '$additionalArgs')"

        depsOut="$(taskGetDeps)"
        depsEscaped="$(jq --null-input -cM --arg deps "$depsOut" '$deps')"

        taskEval "task: (manifest: manifest ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON $additionalArgsJson))) task.manifests.$manifestAttr"
      }

      kubectlArgs="${_kubectlArgs}"
    '';

  getRunScript = { deps }:
    ''
      ${initScript { inherit deps; }}

      if taskRunShouldApply; then
        ${applyScript { inherit deps; }}
      else
        echo "Running dry-run script as nix-task is in dry-run mode"
        ${dryRunScript { inherit deps; }}
      fi

      ${if afterApply != null then afterApply { inherit deps; } else ""}
    '';

  getShellHook = { deps }:
    ''
      ${initScript { inherit deps; }}
    '';
in
mkTask {
  inherit stableId;
  inherit deps;
  inherit tags;
  inherit getOutput;

  path = with pkgs; [
    nix
    bashInteractive
    jq
    jo
    kubectl
  ] ++ path;

  run = ({ deps }: getRunScript { inherit deps; });

  shellHook = ({ deps }: getShellHook { inherit deps; });

  inherit fetchOutput;
  inherit custom;
} // { inherit manifests; }
