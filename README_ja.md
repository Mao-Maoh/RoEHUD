# RoEHUD

[English](README.md) | [日本語](README_ja.md)

RoEHUDは、FINAL FANTASY XI用の非公式Windower 4アドオンです。エミネンス・
レコードの目標、詳細情報、現在のエリア・ジョブ・曜日・天候などに応じた
オススメをコンパクトなHUDに表示します。

本アドオンは現在開発段階にあるため、UIの視認性やデータベースの網羅性において不十分な箇所がです。  
英語データベースにおけるテキストの改行位置につきましては、現時点では大部分が未調整です。  
今後のアップデートにて順次改行位置を調整し、視認性の向上を図ります。

<img width="932" height="278" alt="スクリーンショット 2026-07-24 234610" src="https://github.com/user-attachments/assets/baabab80-e72c-4f32-8a15-123c1ee89ef1" />
<img width="485" height="465" alt="スクリーンショット 2026-07-24 234735" src="https://github.com/user-attachments/assets/a344a40a-2305-466a-9589-0f93795d9394" />

## インストール

1. `RoEHUD`フォルダをWindowerの`addons`フォルダへ配置します。
2. WindowerからFINAL FANTASY XIを起動します。
3. 次のコマンドでアドオンを読み込みます。

```text
//lua l RoEHUD
```

更新後に再読み込みする場合：

```text
//lua r RoEHUD
```

## 基本操作

次のコマンドでメニューを開閉できます。

```text
//rh menu
```

詳しい操作方法、設定、HUD配置、効果音については、ゲーム内メニューの
**Manual**を開いて確認してください。

日本語と英語に対応しています。言語は**Config**または`//rh lang`で
切り替えられます。

## ライセンス

RoEHUDのオリジナルコードはMIT Licenseで公開されています。詳しくは
[`LICENSE`](LICENSE)を参照してください。

第三者のソフトウェアおよびデータベース資料には、それぞれ別のライセンスが
適用されます。詳しくは
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)を参照してください。

RoEHUDはFINAL FANTASY XI用の非公式サードパーティ製アドオンです。

## ピザ代を支援する

RoEHUDは、好奇心と根気、そして時々ピザによって開発されています。

このアドオンが冒険に少しでも役立ったなら、次のピザ代を任意で支援できます。

[開発者を太らせる](https://ko-fi.com/maomaoh)

RoEHUDは今後もすべての方が無料で利用できます。寄付によって機能が解放
されることはありませんが、開発者のやる気は上がります。

さあ、開発者を太らせましょう。
