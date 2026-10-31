{ pkgs }:
let
  inherit (pkgs) lib;
  tools = [
    pkgs.incus-lts.client
    pkgs.ansible
    pkgs.openssh
    pkgs.nushell
  ];
  runtimePath = lib.makeBinPath (
    tools
    ++ [
      pkgs.openssl
      pkgs.util-linux
    ]
  );

  # definitionsには、成果物が格納されたパスが入る
  definitions = pkgs.runCommand "llm-lab-definitions" { } ''
    install -Dm644 ${./preseed.yaml} "$out/preseed.yaml"

    # incus
    install -Dm644 ${./instances/ldap.yaml} "$out/instances/ldap.yaml"
    install -Dm644 ${./instances/webui.yaml} "$out/instances/webui.yaml"
    install -Dm644 ${./instances/llm.yaml} "$out/instances/llm.yaml"

    # cloud-init
    install -Dm644 ${./cloud-init/ldap.yaml} "$out/cloud-init/ldap.yaml"
    install -Dm644 ${./cloud-init/webui.yaml} "$out/cloud-init/webui.yaml"
    install -Dm644 ${./cloud-init/llm.yaml} "$out/cloud-init/llm.yaml"
  '';
  mkApp =
    name:
    pkgs.writeTextFile {
      inherit name;
      destination = "/bin/${name}";
      executable = true;
      text = ''
        #!${pkgs.nushell}/bin/nu --no-config-file

        $env.PATH = ($env.PATH | prepend ("${runtimePath}" | split row ":"))
        $env.LLM_VM_DEFINITIONS = "${definitions}"

        def --wrapped main [...args: string] {
          exec ${pkgs.nushell}/bin/nu --no-config-file ${./launch.nu} ${./vm.nu} ${name} ...$args
        }
      '';
    };
  apps = lib.genAttrs [
    "vm-init"
    "vm-clean"
    "vm-up"
    "vm-down"
    "vm-status"
    "vm-ssh"
    "ansible-apply"
    "ansible-postcheck"
  ] mkApp;
in
{
  inherit definitions tools apps;
}
