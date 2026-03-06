# 推金幣遊戲 (mmPushGold)

單機休閒推金幣遊戲，使用 Godot 4.6 C# Mono 開發，**3D 版本**，支援 Windows 及 Android。

## 需求

- Godot 4.6 Mono 編輯器（需 .NET 版本）
- .NET 8.0 SDK

## 建置與執行

1. 使用 Godot 4.6 Mono 開啟專案資料夾
2. 或使用命令列建置後以 Godot 執行：

```bash
dotnet build
# 使用 Godot 4.6 Mono 執行：開啟 Godot 編輯器，點擊執行
```

3. 從 Godot 編輯器按 F5 或點擊播放按鈕執行遊戲

## 操作方式

### Windows
- **發射金幣**：滑鼠左鍵點擊
- **接幣區移動**：滑鼠左右移動或鍵盤 A/D、方向鍵

### Android
- **發射金幣**：點擊發射按鈕
- **接幣區移動**：觸控滑動

## 專案結構

```
mmPushGold/
├── project.godot      # Godot 專案設定
├── mmPushGold.csproj  # C# 專案檔
├── scenes/
│   ├── Logo.tscn      # Logo 畫面
│   ├── MainMenu.tscn  # 主選單
│   ├── Game.tscn      # 遊戲主畫面
│   ├── Coin.tscn      # 金幣
│   └── CatchZone.tscn # 接幣區
├── scripts/
│   ├── GameManager.cs # 全域常數
│   ├── Logo.cs
│   ├── MainMenu.cs
│   ├── Game.cs
│   ├── Coin.cs
│   └── CatchZone.cs
└── sdd.md             # 軟體設計文件
```

## 遊戲規則

- 每局起始 100 枚可發射金幣
- 金幣射至上層，隨上層伸縮推擠掉落至下層
- 接幣區接住金幣可增加可發射數 +1
- 可發射金幣歸零時遊戲結束
