# BasisMultiWorld

[English](README.md)

> **状態：スナップショット（2026-10-28）。** Basis `2f5b3e106` でビルド・動作確認しています。
> 定期的なメンテナンスは行っておらず、Basis は変化が速いため、利用前に上流の状況を確認してください。
> Issue やプルリクエストは歓迎しますが、対応までお時間をいただく場合があります。

小さなサーバー1台で、複数の [Basis](https://github.com/BasisVR/Basis) ワールドをそれぞれ別の名前
（`forest.worlds.example.com` など）で動かすための構成です。DNS の SRV レコードを使うので、
プレイヤーは名前を入力するだけで、ポート番号は不要です。

- **ワールドは1つのファイル（`worlds.conf`）で定義します。** `configure.sh` がそこから Docker Compose
  ファイルと各サーバーのワールド設定を生成します。
- **Basis はフォークしません。** 上流の `Basis Server/` を固定したコミットからビルドします。
- **DNS レコードも生成されます。** そのままインポートできます。
- **任意の追加機能：** ワールド間ポータル（動作確認済みのプロップ用スクリプト）、ワールドごとの管理ダッシュボード、
  Web プレイヤー（自動生成される Caddy の TLS の背後で WebSocket を使用）。

**まずは[チュートリアル](docs/tutorial.ja.md)をご覧ください。**

```sh
cp .env.example .env && chmod 600 .env     # 中身を記入
$EDITOR worlds.conf                        # 1行1ワールド。1行目がハブ（ポート 4296）
./fetch-basis.sh && ./configure.sh && sudo docker compose up -d --build
./dns-records.sh <サーバーのIPv4> > records.txt   # DNS にインポート（DNS only、プロキシなし）
```

SRV で接続するには、`experimental-branch-major-changes` のコミット `41789fb7d` 以降でビルドした
Basis クライアントが必要です。それより古いクライアントも接続はできますが、常にハブに入ります。

## AI の利用について

このリポジトリのスクリプト・設定・ドキュメント（日本語訳を含む）は、AI コーディングアシスタントの助けを借りて作成しました。
方針の決定とレビューはメンテナーが行い、すべての変更に責任を持ちます。Basis の
[AI.md](https://github.com/BasisVR/Basis/blob/developer/AI.md) と同様に、個々のコミットには AI 利用の表記を付けず、
この説明をもって開示としています。日本語の修正提案を歓迎します。

MIT ライセンスです。[LICENSE](LICENSE) を参照してください。
