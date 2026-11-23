# nixos-orca

[Orca](https://github.com/stablyai/orca)（stablyai/orca のデスクトップアプリ）を NixOS に入れて、自動で最新版に追従させるための flake です。Orca は nixpkgs に入っていません（[stablyai/orca#20128](https://github.com/stablyai/orca/issues/20128)）。この flake は公式リリースの AppImage をバージョンとハッシュで固定して包みます。

対応は `x86_64-linux` だけです。

## この flake が提供するもの

| 出力 | 内容 |
| --- | --- |
| `packages.x86_64-linux.default` | Orca 本体。`orca-ide`、`orca-ide-desktop`、デスクトップエントリ、アイコンを含みます。 |
| `nixosModules.default` | `programs.orca.enable = true;` で上のパッケージをシステムに入れます。`services.orca-server` で常時起動のランタイムを動かします。 |
| `checks.x86_64-linux.vm` | NixOS の VM で X セッションを起動し、Orca のウィンドウが表示されることを確かめるテストです。 |
| `checks.x86_64-linux.server` | 3 台の VM で `services.orca-server` の起動、待ち受けアドレス、ファイアウォール、再起動、ペアリングを確かめるテストです。 |
| `examples/host` | ACEMAGIC Matrix Mini M1 向けの NixOS 構成例です。 |

## コマンド名（`orca` の衝突について）

Linux では `orca` という名前を GNOME のスクリーンリーダーが使っています。NixOS では GNOME、Plasma、COSMIC などが `services.orca.enable` を既定で有効にするので、同じ名前のコマンドを入れると衝突します。

この flake は Orca 公式の `.deb` と同じ名前に合わせました。

| コマンド | 役割 |
| --- | --- |
| `orca-ide` | Orca の CLI です。公式ドキュメントの `orca ...` は、Linux では `orca-ide ...` と読み替えます。 |
| `orca-ide-desktop` | デスクトップアプリを起動します。アプリ一覧の「Orca」はこのコマンドを実行します。 |
| `orca` | 既定では入れません。 |

Orca が開くターミナルの中では、Orca 自身が `orca` を PATH の先頭に置きます。そのため、エージェントは macOS と同じ `orca ...` を使えます。

スクリーンリーダーを使わず、普段のシェルでも `orca` と打ちたい場合は、次の 2 行を足します。両方を有効にすると、ビルド時にエラーで止まります。

```nix
programs.orca.shortCommand.enable = true;
services.orca.enable = false;
```

## NixOS マシンへのインストール

対象は ACEMAGIC Matrix Mini M1（Ryzen 7 7735HS、Radeon 680M）です。`examples/host` は次の設定を含みます。

- `programs.orca.enable = true;`
- `boot.kernelPackages = pkgs.linuxPackages_latest;`
- amdgpu（`hardware.graphics.enable` と `hardware.amdgpu.initrd.enable`）
- `hardware.enableRedistributableFirmware`（Wi-Fi のファームウェアを含みます）と AMD マイクロコード
- `services.fwupd.enable`
- `amd_pstate=active` と power-profiles-daemon
- GNOME、systemd-boot、NetworkManager、日本語ロケール
- Tailscale と `services.orca-server`（[常時起動の Orca ランタイム](#常時起動の-orca-ランタイム)を参照）

インストールは次の順に進めます。

1. NixOS のインストーラ USB で起動し、ディスクを分割して `/mnt` にマウントします。Windows 11 を残す場合は、既存の EFI パーティションを `/mnt/boot` にマウントします。
2. 構成例をコピーします。

   ```sh
   nix-shell -p git --run 'git clone https://github.com/Udon0729/nixos-orca'
   cd nixos-orca
   sudo mkdir -p /mnt/etc/nixos
   sudo cp examples/host/flake.nix examples/host/configuration.nix /mnt/etc/nixos/
   ```

3. `hardware-configuration.nix` をマシン上で生成します。このファイルはリポジトリに入っていません。生成しないと、評価がエラーで止まります。

   ```sh
   sudo nixos-generate-config --root /mnt --show-hardware-config \
     | sudo tee /mnt/etc/nixos/hardware-configuration.nix
   ```

4. `/mnt/etc/nixos/configuration.nix` のユーザー名 `owner`（`users.users` と `services.orca-server.user` の 2 か所）とホスト名 `matrix-mini` を書き換えます。
5. インストールします。

   ```sh
   sudo nixos-install --flake /mnt/etc/nixos#matrix-mini
   ```

6. 再起動してログインし、アプリ一覧から「Orca」を起動します。

`system.stateVersion` は、インストールした時点の値のまま変えません。

## 常時起動の Orca ランタイム

`services.orca-server` は、この NixOS マシンを Orca の入口にします。スマートフォンや Mac の Orca はこのマシンのランタイムに接続します。プロジェクト、ターミナル、エージェントはこのマシン上で動き続けるので、Mac がスリープしても止まりません。

### 仕組み

- `orca-ide serve --supervise` を、指定したユーザーの systemd ユーザーユニット `orca-server.service` として動かします。root では動きません。
- そのユーザーに lingering を設定します。ログインしなくても、起動時にユニットが立ち上がります。
- 状態は `~/.local/state/orca-server`（モード 700）に置きます。デスクトップアプリのプロファイル（`~/.config`）とは別です。
- ファイアウォールは、ポートを `interface`（既定は `tailscale0`）だけに開けます。ほかのインターフェースには開けません。
- Orca 自身も、localhost、LAN、Tailscale 以外の送信元を拒否します（`--refuse-public`）。

| オプション | 既定値 | 内容 |
| --- | --- | --- |
| `enable` | `false` | サービスを有効にします。 |
| `user` | なし（必須） | ランタイムを動かす一般ユーザーです。 |
| `interface` | `"tailscale0"` | ファイアウォールでポートを開ける唯一のインターフェースです。`bindAddress` がなければ、このインターフェースの IPv4 アドレスを待って使います。 |
| `bindAddress` | `null` | 待ち受けとペアリングリンクに使う IP アドレスを直接指定します。 |
| `port` | `6768` | TCP ポートです。 |
| `mobilePairing` | `false` | スマートフォンのペアリングと、`orca-server pair` によるペアリングを有効にします。 |
| `openFirewall` | `true` | `interface` にだけポートを開けます。 |

`mobilePairing` で待ち受け方が変わります。これは Orca の仕様です。

| `mobilePairing` | 待ち受けアドレス | ペアリングの方法 |
| --- | --- | --- |
| `false` | `interface` のアドレスだけ | サービスを止めて、ターミナルで `orca-server serve` を 1 回動かします（下記）。スマートフォンはペアリングできません。 |
| `true` | `0.0.0.0`（全インターフェース） | `orca-server pair` でいつでもリンクを作れます。到達できる範囲は、ファイアウォールが `interface` に限ります。 |

`examples/host` はスマートフォンを使う前提で、`mobilePairing = true` にしています。

`orca-server` コマンドは、サービスのプロファイルを対象にした `orca-ide` です。サービスを動かすユーザーで実行します。

### Tailscale の初回設定

`examples/host` は `services.tailscale.enable = true;` を含みます。認証キーはリポジトリに入れません。初回だけ、マシン上で次を実行してブラウザで認証します。

```sh
sudo tailscale up
tailscale ip -4
```

`orca-server.service` は、`tailscale0` に IPv4 アドレスが付くまで待ってから起動します。確認には次を使います。

```sh
systemctl --user status orca-server
orca-server status --json
```

認証キーで自動化したい場合は、キーをリポジトリの外のファイルに置き、`services.tailscale.authKeyFile = "/path/to/key";` を指定します。

### スマートフォンと Mac をペアリングする

ペアリングリンクは、このランタイムへのアクセス権です。パスワードと同じように扱ってください。

スマートフォン（Tailscale に接続した状態）では、マシン上で QR コードを表示し、Orca Mobile の **Pair** で読み取ります。

```sh
orca-server pair --mobile --address "$(tailscale ip -4)"
```

Mac では、マシン上でリンクを作ります。

```sh
orca-server pair --address "$(tailscale ip -4)"
```

Mac の Orca で **Settings → Remote Orca Servers → Add Server** を開き、リンクを貼ります。CLI でも追加できます。

```sh
orca environment add --name nixos --pairing-code 'orca://pair?...'
orca status --environment nixos --json
```

`mobilePairing = false` のまま Mac だけをペアリングする場合は、サービスを止めてから 1 回だけ手動で起動します。表示されたリンクを Mac に登録したら、Ctrl-C で止めてサービスに戻します。登録は再起動後も残ります。

```sh
systemctl --user stop orca-server
orca-server serve --refuse-public --port 6768 --bind "$(tailscale ip -4)" --pairing-address "$(tailscale ip -4)"
systemctl --user start orca-server
```

エージェントの認証情報は、サーバー側に必要です。マシン上で登録します。

```sh
orca-server account add --agent claude
orca-server account list
```

### Orca を更新したあと

`nixos-rebuild switch` は、ユーザーユニットを再起動しません。新しい Orca でランタイムを動かすには、次を実行するか、マシンを再起動します。

```sh
systemctl --user restart orca-server
```

Orca は、再起動してもターミナルが残ると起動ログに出します（`terminals survive an orcad restart: yes`）。エージェントが動いている状態での再起動は、このリポジトリのテストでは確かめていません。

### クラッシュが続いたとき

ランタイムが落ちると、Orca のスーパーバイザーが再起動します。ユニット全体が落ちると、systemd が再起動します。

ただし、15 分以内に 6 回落ちると、Orca は再起動をやめます。これは Orca 自身の安全装置で、マシンを再起動しても解除されません。`journalctl --user -u orca-server` に `Not starting: Orca serve failed 6 times in 15 minutes` と出ます。原因を直してから、記録を消して起動し直します。

```sh
systemctl --user stop orca-server
rm ~/.local/state/orca-server/serve-supervisor-brake.json
systemctl --user start orca-server
```

Orca のバージョンが変わったときも、この記録は無効になります。

### 計算サーバーを使う

計算サーバーで動いている既存の Orca ランタイムは、止めたり再起動したりしないでください。`orca environment stop`、`update`、`rollback` は、計算サーバーに対して実行しません。下の手順は、どちらも既存のランタイムに触れません。

Mac やスマートフォンから、NixOS マシン経由で計算サーバーの作業に届くかどうかは、まだ実機で確かめていません。考えられる構成は 2 つあります。どちらが動くかは未確認です。

**構成 A: 計算サーバーを NixOS 側の SSH ターゲットにする。** NixOS のランタイムが SSH で計算サーバーに入り、ワークスペースを開きます。計算サーバー側の Orca ランタイムは使いません。

1. サービスのユーザーの `~/.ssh/config` に計算サーバーを書き、鍵でログインできるようにします。公式ドキュメントによると、Orca は `~/.ssh/config` の Host を SSH ターゲットとして取り込みます。
2. NixOS マシンで `orca-server host list --json` を実行します。計算サーバーが `ssh:<target-id>` として出ることを確かめます。
3. NixOS のランタイムで、計算サーバー上のリポジトリを開きます。Mac の Orca で NixOS のサーバーを選び、SSH ターゲット上のプロジェクトを追加できるかを確かめます。
4. Mac で `orca worktree list --environment nixos --json` を実行します。計算サーバー上のワークスペースが出るかを確かめます。
5. スマートフォンの Orca Mobile で、NixOS のランタイムの下にそのワークスペースが出るかを確かめます。

`orca host list` は `--environment` で接続先を切り替えられません。SSH ターゲットの一覧は、NixOS マシン上で確認します。

**構成 B: 環境を連鎖させる（Mac → NixOS → 計算サーバーのランタイム）。** NixOS のランタイムに、計算サーバーの Orca ランタイムをペアリングします。

1. 計算サーバーで、動いているランタイムにリンクを作らせます。再起動は不要です。計算サーバーのランタイムが 1 つのアドレスに固定されている場合、このコマンドは失敗します。そのときは構成 A を使います。

   ```sh
   orca-ide pair --address <NixOS マシンから届くアドレス>
   ```

2. NixOS マシンで登録します。

   ```sh
   orca-server environment add --name compute --pairing-code 'orca://pair?...'
   orca-server status --environment compute --json
   ```

3. Mac の Orca で NixOS のサーバーを選びます。`compute` のプロジェクトやワークスペースが見えるか、開けるかを確かめます。

手順 3 で計算サーバーが見えなければ、連鎖は使えません。その場合、Mac とスマートフォンから計算サーバーへは、構成 A か、これまでどおりの直接のペアリングで届きます。

## 更新の流れ

Nix ストアに入った Orca は自分自身を更新できません。更新はこの flake を通して届きます。

1. `.github/workflows/update.yml` が 6 時間ごとに stablyai/orca の最新リリースを調べます。
2. 新しいリリースがあると、`scripts/update-pin.sh` が `sources.json` のバージョン、URL、ハッシュを書き換えます。
3. 同じジョブの中で `nix flake check`（パッケージのビルドと VM テスト）と `examples/host` の評価を実行します。
4. すべて成功したときだけ、`sources.json` のコミットを `main` に push します。失敗すると `main` は変わらず、GitHub が失敗をメールで通知します。次の実行がもう一度試します。

このワークフローは `GITHUB_TOKEN` だけを使います。`GITHUB_TOKEN` で作ったプルリクエストは CI を起動しないので、プルリクエストを経由しません。テストに通ったコミットだけを同じジョブから push します。

マシン側では、flake の入力を更新して切り替えます。

```sh
cd /etc/nixos
sudo nix flake update nixos-orca
sudo nixos-rebuild switch --flake .#matrix-mini
```

### 毎日の `nix flake update` を自動にする

システム構成を GitHub のリポジトリで管理している場合は、`templates/update-flake-lock.yml` をそのリポジトリの `.github/workflows/` にコピーします。このワークフローは毎日 `nix flake update` を実行し、全ホストの評価に通ったら `flake.lock` を push します。

マシン側は `git pull` して `nixos-rebuild switch` するだけになります。

### スケジュール実行が止まったとき

GitHub は、public リポジトリで 60 日間活動がないと、スケジュール実行を自動で無効にします。Orca のリリースが続く間は、更新のコミットが活動になるので止まりません。止まった場合は、次のどちらかで再開します。

- GitHub の **Actions** タブで **update** を開き、**Enable workflow** を押します。
- `gh workflow enable update.yml -R Udon0729/nixos-orca` を実行します。

すぐに 1 回動かすには、`gh workflow run update.yml -R Udon0729/nixos-orca` を実行します。

## ロールバック

新しい Orca に問題があるときは、1 つ前の世代に戻します。

```sh
sudo nixos-rebuild switch --rollback
```

起動時のブートメニューからも、以前の世代を選べます。

特定のバージョンに固定し続けたいときは、このリポジトリの過去のコミットを指定します。コミットは `git log -- sources.json` で探します。

```sh
sudo nix flake update nixos-orca --override-input nixos-orca github:Udon0729/nixos-orca/<コミット>
sudo nixos-rebuild switch --flake .#matrix-mini
```

## 手元での確認とメンテナンス

| やりたいこと | コマンド |
| --- | --- |
| すべてのチェックを実行する（x86_64-linux と KVM が必要） | `nix flake check -L` |
| 構成例を評価する（macOS でも動きます） | `./scripts/eval-example-host.sh` |
| 最新リリースに固定し直す | `./scripts/update-pin.sh` |
| 指定したリリースに固定する | `./scripts/update-pin.sh v1.4.271` |
| この flake の nixpkgs を更新する | `nix flake update` をブランチで実行し、プルリクエストを出す |

モジュールは、ホスト側の `pkgs` でパッケージを組み立てます。このリポジトリの `flake.lock` にある nixpkgs は、CI と `packages` 出力だけが使います。

## 既知の制限

- このリポジトリを private にすると、Nix は `access-tokens` の設定なしでは flake を取得できません（404 になります）。
- Orca は bubblewrap の FHS 環境の中で動きます。Orca のターミナルから起動したプロセスも、その中で動きます。この環境では `sudo` のような setuid コマンドは動きません（`buildFHSEnv` の仕様からの推定で、未検証です）。
- アプリ内の「Orca CLI を登録」は使いません。`~/.local/bin/orca-ide` に Nix ストアへのリンクを作りますが、FHS 環境の外では動きません。CLI は最初から `orca-ide` として入っています。
- アプリ内の更新確認は、新しいバージョンがあることを知らせるだけです。適用はこの flake の更新で行います。
- `services.orca-server` とデスクトップアプリは別のプロファイルを使います。同じプロジェクトをデスクトップアプリで見るには、アプリからこのマシンのランタイムにペアリングします。

## ライセンスと参考

Orca 本体は MIT ライセンスです。パッケージの構成は [FelipeMalacarne/orca-flake](https://github.com/FelipeMalacarne/orca-flake)（MIT）を参考にしましたが、この flake はそれに依存していません。
