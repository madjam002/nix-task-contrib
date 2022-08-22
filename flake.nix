{
  description = "Sample tasks and actions for Nix Task";

  inputs = {
    utils.url = github:gytis-ivaskevicius/flake-utils-plus;
    nix-task.url = github:madjam002/nix-task;
  };

  outputs = inputs@{ self, utils, nix-task, ... }:
    let
      flake = utils.lib.mkFlake {
        inherit self inputs;

        outputsBuilder = channels:
          let
            libFn = { pkgs }:
              let
                lib = pkgs.lib // nix-task.lib // {
                  nixus = pkgs.callPackage ./packages/nixus {};
                  includes = {
                    authenticateWithVault = import ./includes/authenticateWithVault.nix { inherit pkgs; inherit lib; };
                    registerCACertificates = import ./includes/registerCACertificates.nix { inherit pkgs; inherit lib; };
                    sshAgentWithVaultSSHRoles = import ./includes/sshAgentWithVaultSSHRoles.nix { inherit pkgs; inherit lib; };
                    terraformVaultHttpBackend = import ./includes/terraformVaultHttpBackend.nix { inherit pkgs; inherit lib; };
                  };
                  mixins = {
                    dynamicNixOSSystems = import ./mixins/dynamicNixOSSystems.nix { inherit pkgs; inherit lib; };
                  };
                  taskTemplates = {
                    mkTerraformWorkspace = import ./taskTemplates/mkTerraformWorkspace { inherit pkgs; inherit lib; };
                  };
                };
              in
              lib;
          in
          {
            lib = { pkgs }: with (libFn { inherit pkgs; }); {
              inherit includes;
              inherit mixins;
              inherit taskTemplates;
            };
          };
      };
    in
    flake;
}
