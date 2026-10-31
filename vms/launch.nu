#!/usr/bin/env nu

def --wrapped main [script: path, action: string, ...args: string] {
    $env.LC_ALL = "C.UTF-8"
    umask rwx------ | ignore # 作成するファイルやディレクトリを、実行ユーザのみが読み書きできるように設定

    # 起動・停止 action のみ同時実行を防止
    if $action in [vm-up vm-down] {
        mkdir .state
        (exec flock
            --nonblock # 他の処理がロック中なら失敗
            --no-fork  # 子プロセスを作らず実行
            .state/vm.lock # ロックファイル
            $nu.current-exe
            --no-config-file # 個人のnu設定ファイルを読み込まない
            $script $action ...$args
        )
    } else {
        # その他 action は普通に実行
        exec $nu.current-exe --no-config-file $script $action ...$args
    }
}
