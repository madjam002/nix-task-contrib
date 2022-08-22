{ pkgs, ... }:

caCertificates:

let
  certificateFiles = [
    "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
  ];
  certificates = caCertificates;
  package = pkgs.runCommand "ca-certificates.crt"
    { files =
        certificateFiles ++
        [ (builtins.toFile "extra.crt" (pkgs.lib.concatStringsSep "\n" certificates)) ];
      preferLocalBuild = true;
      }
    ''
      cat $files > $out
    '';
in
''
  export SSL_CERT_FILE=${package}
''
