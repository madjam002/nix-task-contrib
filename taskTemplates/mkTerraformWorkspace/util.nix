{ pkgs }:

with builtins;
with pkgs.lib;
with pkgs;

let
  tfExpr = expr: { __expression = expr; };

  formatTfValue = val:
    if (isAttrs val && hasAttr "__expression" val) then val.__expression
    else (
      if (isString val) && (hasPrefix "\${" val) && (hasSuffix "}" val) then
        (pipe val [ (removePrefix "\${") (removeSuffix "}") ]) # var reference in terraform shouldn't use string interpolation since tf version 0.12
      else toJSON val
    );

  generateModulesFile = modules:
    writeTextFile {
      name = "modules.tf";
      text = (
        concatStringsSep "\n" (
          map (conf: ''
            ${if hasAttr "extra" conf then conf.extra else ""}

            module "${conf.id}" {
              source = "${conf.src}"
              ${if hasAttr "dependsOn" conf then "depends_on = [${concatStringsSep "," conf.dependsOn}]" else ""}
              ${if hasAttr "config" conf then conf.config else ""}

            ${concatStringsSep "\n" (
              pkgs.lib.mapAttrsToList (name: val: "  ${name} = ${formatTfValue val}") conf.variables
            )}
            }
          '') modules
        )
      );
    };
in
{
  inherit tfExpr;
  inherit formatTfValue;
  inherit generateModulesFile;
}
