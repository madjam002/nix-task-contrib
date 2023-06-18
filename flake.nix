{
  description = "Sample standard library of tasks and actions for nix-task";

  inputs = {
    utils.url = "github:gytis-ivaskevicius/flake-utils-plus";
    nix-task.url = "github:madjam002/nix-task";
    yarnpnp2nix.url = "github:madjam002/yarnpnp2nix";
    yarnpnp2nix.inputs.utils.follows = "utils";
  };

  outputs = inputs@{ self, utils, nix-task, yarnpnp2nix, ... }:
    let
      flake = utils.lib.mkFlake {
        inherit self inputs;

        outputsBuilder = channels:
          let
            packagesFn = { pkgs }: {
              terraformVaultHttpBackend = pkgs.callPackage ./packages/terraform-vault-http-backend {};
            };
            libFn = args@{ pkgs }:
              let
                pkgs = args.pkgs // (packagesFn { pkgs = args.pkgs; });
                lib = pkgs.lib // nix-task.lib // {
                  nixus = pkgs.callPackage ./packages/nixus {};
                  includes = {
                    authenticateWithVault = import ./includes/authenticateWithVault.nix { inherit pkgs; inherit lib; };
                    registerCACertificates = import ./includes/registerCACertificates.nix { inherit pkgs; inherit lib; };
                    sshAgentWithVaultSSHRoles = import ./includes/sshAgentWithVaultSSHRoles.nix { inherit pkgs; inherit lib; };
                    terraformVaultHttpBackend = import ./includes/terraformVaultHttpBackend.nix { inherit pkgs; inherit lib; inherit yarnpnp2nix; };
                  };
                  mixins = {
                    dynamicNixOSSystems = import ./mixins/dynamicNixOSSystems.nix { inherit pkgs; inherit lib; };
                  };
                  taskTemplates = {
                    mkKubernetesManifestDeployment = import ./taskTemplates/mkKubernetesManifestDeployment { inherit pkgs; inherit lib; };
                    mkTerraformWorkspace = import ./taskTemplates/mkTerraformWorkspace { inherit pkgs; inherit lib; };
                  };
                  scripts = {
                    configureSSHHost = "${pkgs.nodePackages.zx}/bin/zx ${./scripts/configureSSHHost.mjs}";
                  };
                };
              in
              lib;
          in
          {
            lib = { pkgs }: with (libFn { inherit pkgs; }); {
              inherit nixus;
              inherit includes;
              inherit mixins;
              inherit taskTemplates;
              inherit scripts;
            };
            packages = packagesFn;
          };
      };
    in
    flake;
}
