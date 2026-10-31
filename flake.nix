{
  description = "LLM Infrastructure Example";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lab = import ./vms { inherit pkgs; };
    in
    {
      packages.${system} = lab.apps;

      devShells.${system}.default = pkgs.mkShell {
        packages = lab.tools ++ [ pkgs.nixfmt ];
      };
      formatter.${system} = pkgs.nixfmt;

      apps.${system} = {
        vm-init = {
          type = "app";
          program = "${lab.apps.vm-init}/bin/vm-init";
        };
        vm-clean = {
          type = "app";
          program = "${lab.apps.vm-clean}/bin/vm-clean";
        };
        vm-up = {
          type = "app";
          program = "${lab.apps.vm-up}/bin/vm-up";
        };
        vm-down = {
          type = "app";
          program = "${lab.apps.vm-down}/bin/vm-down";
        };
        vm-status = {
          type = "app";
          program = "${lab.apps.vm-status}/bin/vm-status";
        };
        vm-ssh = {
          type = "app";
          program = "${lab.apps.vm-ssh}/bin/vm-ssh";
        };
        ansible-apply = {
          type = "app";
          program = "${lab.apps.ansible-apply}/bin/ansible-apply";
        };
        ansible-postcheck = {
          type = "app";
          program = "${lab.apps.ansible-postcheck}/bin/ansible-postcheck";
        };
      };
    };
}
