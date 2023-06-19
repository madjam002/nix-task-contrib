{ pkgs, lib, ... }:

with lib;

# roles can either be an array of roles mounted as the default ssh-client mount path,
# or an list of attrs like so:
# { role = "rolename"; mount = "mount-path-of-ssh-client"; vault.address = "optional-vault-address"; }
roles:
  ''
  export PATH=$PATH:${pkgs.openssh}/bin

  keys="$HOME/.vault-ssh"

  # only start agent if not already running or keys do not exist.
  # if it's already running, add keys to existing ssh agent
  if [ ! -f "$HOME/.vault-ssh/id_rsa" ] || [ -z "$SSH_AUTH_SOCK" ]; then
    taskRunFinally "rm -rf $keys"

    mkdir -p $keys

    ${pkgs.bash}/bin/bash -c "yes | ssh-keygen -t ed25519 -f $keys/id_rsa -N \"\""

    chmod 0600 $keys/*

    eval "$(ssh-agent)"
    taskRunFinally "${pkgs.openssh}/bin/ssh-agent -k"
  fi

  ${concatStringsSep "\n" (map (sshRoleNameOrAttrs:
    let
      sshRoleName = if isAttrs sshRoleNameOrAttrs then sshRoleNameOrAttrs.role else sshRoleNameOrAttrs;
      mountPath = (if isAttrs sshRoleNameOrAttrs then (sshRoleNameOrAttrs.mount or null) else null) or "ssh-client";
      beforeEnv =
        if isAttrs sshRoleNameOrAttrs && (sshRoleNameOrAttrs.vault or null) != null
        then "VAULT_ADDR=${sshRoleNameOrAttrs.vault.address} "
        else "";
    in
    ''
      ${beforeEnv}${pkgs.vault}/bin/vault write -field=signed_key ssh-client/sign/${sshRoleName} \
        public_key=@$keys/id_rsa.pub > $keys/id_rsa-cert.pub

      ssh-keygen -Lf $keys/id_rsa-cert.pub

      ssh-add $keys/id_rsa
      rm $keys/id_rsa-cert.pub
    ''
  ) (roles))}
  ''
