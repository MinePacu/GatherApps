# GatherTab

[English](README.en.md) | [한국어](README.md) | 日本語

GatherTabは、関連するmacOSアプリを作業単位でグループ化し、必要なときにまとめて前面に表示するSwiftUIベースのmacOSアプリです。ブラウザ、メッセンジャー、IDEなど、同じ作業で使うアプリをグループとして保存しておくと、グループをアクティブ化するだけでそれらのウインドウを前面に戻せます。

## 主な機能

- 実行中のアプリ一覧からアプリを選んでグループに追加
- アプリグループの保存と削除
- グループアイコンの自動生成
- 選択したグループのアプリウインドウをまとめてアクティブ化
- ツールバーボタンから開くフローティンググループスイッチャー
- グループ別のCommand-Tabランチャーアプリ生成
- `gathertab://activate-group/<GROUP_UUID>` URLスキームによるグループアクティブ化

## 要件

- macOS 14.0以降
- Xcode 15以降を推奨
- アプリウインドウを安定して前面に表示するには、macOSのアクセシビリティ権限が必要になる場合があります。

## はじめに

1. Xcodeで`GatherTab.xcodeproj`を開きます。
2. `GatherTab`スキームを選択します。
3. Runを押してアプリを起動します。
4. サイドバーの`グループを作成`ボタンで新しいグループを作成します。
5. 右側の実行中アプリ一覧で`+`ボタンを押して、グループにアプリを追加します。
6. `グループをアクティブ化`を押して、グループ内のアプリウインドウを前面に表示します。

## Command-Tabランチャー

各グループは、小さなmacOS `.app`ランチャーとして生成できます。生成されたランチャーは通常のアプリと同じようにCommand-Tabスイッチャーに表示され、選択するとGatherTabにグループのアクティブ化を依頼します。

- 生成場所: `~/Applications/GatherTab Launchers/`
- 生成方法: グループ詳細画面で`ランチャーを生成`をクリック
- 実装メモ: [docs/launcher-apps.md](docs/launcher-apps.md)

## データ保存場所

GatherTabはグループデータと生成されたアイコンをユーザーのApplication Support領域に保存します。

- グループデータ: `~/Library/Application Support/GatherTab/groups.json`
- グループアイコン: `~/Library/Application Support/GatherTab/Icons/`
- ウインドウヘルパー診断ファイル: `~/Library/Application Support/GatherTab/window-helper-diagnostics.txt`

## プロジェクト構成

- `GatherTab/`: メインのSwiftUIアプリ
- `GatherTabWindowHelper/`: アプリウインドウを前面に表示する補助ランタイム
- `GatherTabLauncherRuntime/`: グループ別ランチャーアプリで使うランタイム
- `GatherTabTests/`: ユニットテスト
- `GatherTabUITests/`: UIテスト
- `docs/`: 追加の設計および実装ドキュメント

## テスト

XcodeのTestアクションを使うか、ターミナルで次のコマンドを実行します。

```sh
xcodebuild test -project GatherTab.xcodeproj -scheme GatherTab
```

## 注記

- 生成されたランチャーアプリは、デフォルトではローカル開発用に作成されます。配布にはコード署名とnotarization手順が必要です。
- ランチャーアプリはウインドウを直接制御しません。GatherTabのURLスキームを呼び出し、グループのアクティブ化をメインアプリに委譲します。
