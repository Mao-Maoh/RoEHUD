return {
    order = {'basic', 'detail', 'objectives', 'items', 'layout', 'config', 'mouse', 'commands', 'sound'},
    pages = {
        basic = {
            title = {ja='基本操作', en='Basic Controls'},
            ja={'目標にマウスを重ねると選択表示になります。','左クリックで詳細HUDを開きます。','右クリックで目標の破棄操作を行います。','メニュー内では右クリックで前画面へ戻ります。'},
            en={'Hover an objective to highlight it.','Left-click to open its details.','Right-click to cancel an objective.','Right-click in menus to go back.'},
        },
        detail = {
            title = {ja='詳細HUD', en='Detail HUD'},
            ja={'目標の説明、進行度、報酬を表示します。','未受領なら「目標を受領する」を選べます。','受領中なら「目標を破棄する」を選べます。','進行中の破棄には確認画面が表示されます。'},
            en={'Shows description, progress, and rewards.','Use Accept Objective when it is inactive.','Use Cancel Objective when it is active.','A confirmation appears if progress is nonzero.'},
        },
        objectives = {
            title = {ja='目標一覧とオススメ', en='Objectives and Recommendations'},
            ja={'目標一覧はカテゴリから順に選択します。','オススメはエリア、ジョブ、曜日などで抽出します。','条件付き目標はチャレンジオススメへ分離されます。','メインとサポの両方に一致しても1件だけ表示します。','該当目標がない種類はメニューに表示されません。','エリア移動時にも対象があれば画面が開きます。','「戻る」または右クリックで前画面へ戻ります。'},
            en={'Browse objectives by category and subcategory.','Recommendations can use zone, jobs, day, and more.','Conditional objectives are separated as Challenges.','A main/support double match is listed only once.','Types with no matching objectives are hidden.','The zone page opens after moving only when matches exist.','Use Back or right-click to return.'},
        },
        items = {
            title = {ja='アイテム説明', en='Item Details'},
            ja={'緑色のアイテム名へマウスを重ねます。','対象の名前だけがホバー色に変わります。','アイテム画像、説明、装備情報を表示します。','家具の場合は収納や属性なども表示します。'},
            en={'Hover a green item name.','Only the hovered name changes color.','The item image, description, and equipment data appear.','Furniture also shows storage and elemental data.'},
        },
        layout = {
            title = {ja='HUD配置', en='HUD Layout'},
            ja={'Configから「HUD配置を編集」を選びます。','各HUDをマウスでドラッグします。','「HUD配置を保存」で現在位置を保存します。','「取消」は編集前、「初期化」は既定位置へ戻します。'},
            en={'Choose Edit HUD Layout in Config.','Drag each HUD with the mouse.','Choose Save HUD Layout to store the positions.','Cancel restores prior positions; Reset restores defaults.'},
        },
        config = {
            title = {ja='言語とフォント', en='Language and Font'},
            ja={'LanguageでJAとENを切り替えます。','Font Sizeの[-1]と[+1]で全HUDを変更します。','フォントサイズの範囲は8～20です。','変更内容はsettings.luaへ保存されます。'},
            en={'Language switches between JA and EN.','Font Size [-1] and [+1] changes every HUD.','The available font size range is 8 to 20.','Changes are saved to settings.lua.'},
        },
        mouse = {
            title = {ja='マウス補正', en='Mouse Correction'},
            ja={'右下ほど判定がずれる場合はマウス倍率を変更します。','150%補正で悪化する場合は、逆倍率の67%を試します。','一定量のずれはX補正とY補正で5ずつ調整します。','座標デバッグでは補正前後の座標をチャットへ表示します。','初期化すると倍率100%、X/Y補正0へ戻ります。'},
            en={'Change Mouse Scale when the error grows toward the lower-right.','If 150% makes it worse, try the inverse scale of 67%.','Use X/Y Offset to adjust a constant error in steps of 5.','Coordinate Debug prints raw and corrected positions to chat.','Reset returns to 100% scale and zero X/Y offsets.'},
        },
        commands = {
            title = {ja='チャットコマンド', en='Chat Commands'},
            ja={'//rh menu : メニューを開閉','//rh lang : JA/EN切替','//rh mouse 0.6667 : マウス倍率を67%に設定','//rh mouse reset : マウス補正を初期化','//rh debug : マウスデバッグ切替','//rh sound complete : 効果音テスト','//lua r RoEHUD : アドオン再読み込み'},
            en={'//rh menu : Toggle menu','//rh lang : Toggle JA/EN','//rh mouse 0.6667 : Set mouse scale to 67%','//rh mouse reset : Reset mouse correction','//rh debug : Toggle mouse debug','//rh sound complete : Test sound','//lua r RoEHUD : Reload the addon'},
        },
        sound = {
            title = {ja='効果音と進行度', en='Sound and Progress'},
            ja={'Configの「効果音」でON/OFFを切り替えます。','sounds/complete.wav：目標達成時およびHUDからの受領確認時に再生されます。','sounds/repeat.wav：繰り返し可能な目標の達成時に再生されます。','sounds/full.wav：目標達成時に持ち物が満杯の場合に再生されます。','音声ファイルがなくてもアドオン本体は動作します。','必要数と進行度が同じ場合は満杯色になります。','必要数を超えた場合は不正値色になります。'},
            en={'Toggle Sound ON/OFF in Config.','sounds/complete.wav: Played when an objective is completed or accepted from the HUD.','sounds/repeat.wav: Played when a repeatable objective is completed.','sounds/full.wav: Played when an objective is completed while the inventory is full.','The addon continues to work when these sound files are absent.','Equal current/required progress uses the full color.','Progress above the requirement uses the invalid color.'},
        },
    },
}
