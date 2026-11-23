# nixos-orca

[Orca](https://github.com/stablyai/orca)（stablyai/orca のデスクトップアプリ）を NixOS に入れて、自動で最新版に追従させるための flake です。Orca は nixpkgs に入っていません（[stablyai/orca#20128](https://github.com/stablyai/orca/issues/20128)）。この flake は公式リリースの AppImage をバージョンとハッシュで固定して包みます。

対応は `x86_64-linux` だけです。

## この flake が提供するもの

| 出力 | 内容 |
| --- | --- |
| `packages.x86_64-linux.default` | Orca 本体。`orca-ide`、`orca-ide-desktop`、デスクトップエントリ、アイコンを含みます。 |
| `nixosModules.default` | `programs.orca.enable = true;` で上のパッケージをシステムに入れます。 |
| `checks.x86_64-linux.vm` | NixOS の VM で X セッションを起動し、Orca のウィンドウが表示されることを確かめるテストです。 |
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

4. `/mnt/etc/nixos/configuration.nix` のユーザー名 `owner` とホスト名 `matrix-mini` を書き換えます。
5. インストールします。

   ```sh
   sudo nixos-install --flake /mnt/etc/nixos#matrix-mini
   ```

6. 再起動してログインし、アプリ一覧から「Orca」を起動します。

`system.stateVersion` は、インストールした時点の値のまま変えません。

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

## ライセンスと参考

Orca 本体は MIT ライセンスです。パッケージの構成は [FelipeMalacarne/orca-flake](https://github.com/FelipeMalacarne/orca-flake)（MIT）を参考にしましたが、この flake はそれに依存していません。
