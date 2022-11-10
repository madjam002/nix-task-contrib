{ stdenv, nodejs, yarn, lib }:

let
  outputHashByPlatform = {
    "x86_64-linux" = "sha256-9jf3TfIVtJzR1YGMgJ+AHrTW/kro4nAcR+pnHYKDQW4=";
    "aarch64-darwin" = "sha256-2j13HGmVxOLSG6bty3GWBGy3xsIfLwYzZeMFy1GsBa0=";
  };
  copySrc = src: builtins.concatStringsSep "" (lib.mapAttrsToList (fileName: srcItem: ''
    if [[ -d "${srcItem}" ]]; then
      mkdir -p ${fileName} && cp --no-preserve=mode -r ${srcItem}/* ${fileName}
    elif [[ -f "${srcItem}" ]]; then
      mkdir -p $(dirname ${fileName})
      cp --no-preserve=mode -r ${srcItem} ./${fileName}
    fi
  '') src);
in
stdenv.mkDerivation {
  name = "terraform-vault-http-backend";

  phases = [ "build" ];

  buildInputs = [
    nodejs
    yarn
  ];

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = outputHashByPlatform.${stdenv.system};

  build = ''
    mkdir -p $out
    cd $out

    export HOME=$TMPDIR/home # yarn requires a home directory

    ${copySrc {
      "index.js" = ./index.js;
      "package.json" = ./package.json;
      "yarn.lock" = ./yarn.lock;
    }}

    yarn --pure-lockfile
  '';
}
