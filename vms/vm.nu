#!/usr/bin/env nu

# VM作成で使うUbuntuイメージ
const IMAGE = "images:ubuntu/26.04/cloud"

let root = (pwd | path expand)
let definitions = $env.LLM_VM_DEFINITIONS
let preseed = (open ($definitions | path join "preseed.yaml"))
let project = $preseed.projects.0.name
let state = ($root | path join ".state")

# 状態の保存先作成関数
def --env prepare-state [] {
    mkdir $state
    $env.root = $root
    $env.state = $state
    $env.project = $project
}

# LDAPパスワードとWebUIの秘密値作成関数
def prepare-secrets [] {
    let secrets = ($state | path join "secrets.json")
    if not ($secrets | path exists) {
        let values = {
            ldap_admin_password: (^openssl rand -hex 24 | str trim)
            ldap_bind_password: (^openssl rand -hex 24 | str trim)
            ldap_demo_password: (^openssl rand -hex 24 | str trim)
            webui_secret_key: (^openssl rand -hex 24 | str trim)
        }
        let temporary = ($state | path join "secrets.tmp")
        $values | to json | save --force $temporary
        mv --force $temporary $secrets
    }
}

# 操作未指定時のヘルプ表示
def main [] {
    help main
}

# VMのリソース（仮想NICやストレージ等）の作成（管理ユーザ用）
def "main vm-init" [] {
    open --raw ($definitions | path join "preseed.yaml")
    | ^incus admin init --force-local --preseed
}

# VMのリソース削除（管理ユーザ用）
# --force 指定時はプロジェクト内のVM・ディスク・イメージも削除
def "main vm-clean" [--force] {
    let options = if $force { ["--force"] } else { [] }
    for item in $preseed.projects {
        ^incus project delete $"local:($item.name)" ...$options
    }
    for item in $preseed.networks {
        let network_project = ($item.project? | default "default")
        ^incus network delete $"local:($item.name)" --project $network_project
    }
    for item in $preseed.storage_pools {
        ^incus storage delete $"local:($item.name)"
    }
    print "preseed.yamlに記載したIncusリソースを削除しました。手元の設定・秘密値は保持しています。"
}

# VMの作成と起動
def "main vm-up" [] {
    prepare-state
    let instances = (^incus list local: --project $project --format json | from json)
    for source in (glob ($definitions | path join "instances" "*.yaml") | sort) {
        let name = (open $source).name
        let current = ($instances | where name == $name)
        if ($current | is-empty) {
            let cloud_init = (open --raw ($definitions | path join "cloud-init" $"($name).yaml"))
            open --raw $source
            | ^incus init $IMAGE $"local:($name)" --project $project --vm --no-profiles --config $"cloud-init.user-data=($cloud_init)"
        }
        if ($current | is-empty) or ($current.0.status == "Stopped") {
            ^incus start $"local:($name)" --project $project
        }
    }
    print "VMを起動しました。SSHと初期設定の完了はansible-applyで待機します。"
}

# VMの停止
def "main vm-down" [] {
    prepare-state
    let stop_seconds = ($env.VM_WAIT_SECONDS? | default --empty "180")
    let instances = (^incus list local: --project $project --format json | from json)
    mut names = []
    for source in (glob ($definitions | path join "instances" "*.yaml") | sort) {
        let name = (open $source).name
        let current = ($instances | where name == $name)
        if not ($current | is-empty) and ($current.0.status != "Stopped") {
            $names = ($names | append $"local:($name)")
        }
    }
    if not ($names | is-empty) {
        ^incus stop ...$names --project $project --timeout $stop_seconds
    }
    print "対象VMを停止しました。ディスク、ネットワーク、プロジェクトは保持しています。"
}

# VMの状態表示
def "main vm-status" [] {
    prepare-state
    exec incus list local: --project $project
}

# 指定したVMへのSSH接続
def --wrapped "main vm-ssh" [name: string, ...args: string] {
    if $name not-in [ldap webui llm] {
        error make {msg: $"不明なVM名です: ($name)"}
    }
    prepare-state
    let instance = (open ($definitions | path join "instances" $"($name).yaml"))
    let ip = $instance.devices.eth0."ipv4.address"
    let known_hosts = ($state | path join "known_hosts")
    exec ssh -o StrictHostKeyChecking=accept-new -o $"UserKnownHostsFile=($known_hosts)" $"ansible@($ip)" ...$args
}

# VMへのAnsible適用
def --wrapped "main ansible-apply" [...args: string] {
    prepare-state
    prepare-secrets
    $env.ANSIBLE_CONFIG = ($root | path join "ansible" "ansible.cfg")
    exec ansible-playbook -i ($root | path join "ansible" "inventory.yaml") ($root | path join "ansible" "site.yml") ...$args
}

# 構築済み環境の動作確認
def --wrapped "main ansible-postcheck" [...args: string] {
    prepare-state
    $env.ANSIBLE_CONFIG = ($root | path join "ansible" "ansible.cfg")
    exec ansible-playbook -i ($root | path join "ansible" "inventory.yaml") ($root | path join "ansible" "postcheck.yml") ...$args
}
