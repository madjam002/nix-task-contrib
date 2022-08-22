{ pkgs, lib, ... }:

with lib;

roles:
  ''
  export PATH=$PATH:${pkgs.openssh}/bin

  keys="$TMPDIR/.ssh"
  taskRunFinally "rm -rf $keys"

  mkdir -p $keys
  ${pkgs.bash}/bin/bash -c "yes | ssh-keygen -t ed25519 -f $keys/id_rsa -N \"\""

  chmod 0600 $keys/*

  eval "$(ssh-agent)"
  taskRunFinally "${pkgs.openssh}/bin/ssh-agent -k"

  ${concatStringsSep "\n" (map (sshRoleName: ''
    ${pkgs.vault}/bin/vault write -field=signed_key ssh-client/sign/${sshRoleName} \
      public_key=@$keys/id_rsa.pub > $keys/id_rsa-cert.pub

    ssh-keygen -Lf $keys/id_rsa-cert.pub

    ssh-add $keys/id_rsa
    rm $keys/id_rsa-cert.pub
  '') (roles))}
  ''
