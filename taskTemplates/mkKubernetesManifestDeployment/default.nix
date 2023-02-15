{ pkgs, lib, ... }:

with lib;
with builtins;

{
  stableId ? null,
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
          export additionalArgsJson="$(jo $rest)"
        else
          export additionalArgsJson="{}"
        fi

        depsOut="$(taskGetDeps)"
        depsEscaped="$(jq --null-input -cM --arg deps "$depsOut" '$deps')"

        nix eval --raw --impure --allow-unsafe-native-code-during-evaluation \
          --apply "(manifest: manifest ({ deps = (builtins.fromJSON $depsEscaped); } // (builtins.fromJSON(builtins.getEnv \"additionalArgsJson\"))))" \
          $NIX_TASK_FLAKE_PATH.manifests.$manifestAttr
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
    '';
in
mkTask {
  inherit stableId;
  inherit deps;
  inherit getOutput;

  path = with pkgs; [
    nix
    bashInteractive
    jq
    jo
    kubectl
  ] ++ path;

  run = ({ deps }: getRunScript { inherit deps; });
} // { inherit manifests; }
