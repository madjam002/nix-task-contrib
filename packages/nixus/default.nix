{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  name = "nixus";

  src = fetchFromGitHub {
    owner = "Infinisil";
    repo = "nixus";
    rev = "bc40879a51c0739b83e3a0bd6381fe0bf51b0649";
    sha256 = "sha256-JOMif698xVtPegtLGfHN8hJ3lPv4Oxnmf+zp6/JrwE8=";
  };

  phases = [ "patchPhase" "build" ];

  build = ''
    cp --no-preserve=mode -r $src $out
    cp --no-preserve=mode ${./default.nix.replacement} $out/default.nix
    cp --no-preserve=mode ${./options.nix.replacement} $out/modules/options.nix
  '';
}
