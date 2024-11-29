{ pkgs }:

let
  terranixSrc = pkgs.fetchFromGitHub {
    owner = "terranix";
    repo = "terranix";
    rev = "7734e2ee6a1472807a33ce1e7da794bed2aaf91c";
    sha256 = "sha256-1Pu2j5xsBTuoyga08ZVf+rKp3FOMmJh/0fXen/idOrA=";
  };

  mkTerranixConfiguration = {
    config,
    extraArgs ? {},
    strip_nulls ? true,
  }:
    let
      terranixCore = import "${terranixSrc}/core/default.nix" {
        inherit pkgs extraArgs strip_nulls;
        terranix_config = config;
      };
    in
    terranixCore.config;
in
{
  inherit
    mkTerranixConfiguration;
}
