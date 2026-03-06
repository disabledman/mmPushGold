#nullable enable
using System.Linq;
using Godot;

namespace mmPushGold;

public partial class Game : Node3D
{
    [Export] public PackedScene CoinScene { get; set; } = null!;
    [Export] public Node3D ShootOrigin { get; set; } = null!;
    [Export] public Node3D UpperLayer { get; set; } = null!;
    [Export] public CatchZone CatchZoneNode { get; set; } = null!;
    [Export] public Label CoinsLabel { get; set; } = null!;
    [Export] public Control PauseMenu { get; set; } = null!;
    [Export] public Control GameOverOverlay { get; set; } = null!;
    [Export] public Label GameOverStats { get; set; } = null!;
    [Export] public Button ShootButton { get; set; } = null!;
    [Export] public Button PauseButton { get; set; } = null!;

    private int _coinsRemaining;
    private int _coinsCollected;
    private double _gameStartTime;
    private bool _gameOver;
    private bool _paused;
    private Tween? _upperLayerTween;
    private Node3D _coinsContainer = null!;
    private Camera3D? _camera;
    private Vector3 _lastAimPosition;  // 每幀更新，供發射時使用

    // 上層：深 300 單位，伸出到 50% 位置（下層一半），縮回到 10% 位置（近後板）
    private const float UpperLayerDepth = 3f;           // 上層深度（300 單位 = 3）
    private const float BackBoardZ = -2.5f;            // 後板 Z
    private const float LowerLayerHalfZ = -0.5f;       // 下層一半位置
    private const float UpperLayerRetractedZ = BackBoardZ + UpperLayerDepth * 0.1f - UpperLayerDepth * 0.5f;  // 10% 伸出：前緣在後板+10%
    private const float UpperLayerExtendedZ = LowerLayerHalfZ - UpperLayerDepth * 0.5f;  // 50%：前緣到下層一半

    // 掉出畫面外的 Y 閾值，低於此值則回收（僅未接住的金幣會掉到此處）
    private const float CoinRecycleThresholdY = -2f;

    // 下層平台範圍（用於散佈初始金幣）
    private const float LowerLayerMinX = -5.5f;
    private const float LowerLayerMaxX = 5.5f;
    private const float LowerLayerMinZ = -2.3f;
    private const float LowerLayerMaxZ = 1.3f;
    private const float LowerLayerTopY = 0.65f;
    private const int InitialCoinsOnLower = 1000;

    public override void _Ready()
    {
        // 使用 GetNode 確保節點正確取得
        _coinsContainer = GetNode<Node3D>("CoinsContainer");
        if (CoinScene == null) CoinScene = GD.Load<PackedScene>("res://scenes/Coin.tscn");
        if (ShootOrigin == null) ShootOrigin = GetNode<Node3D>("GameArea/ShootOrigin");
        if (UpperLayer == null) UpperLayer = GetNode<Node3D>("GameArea/UpperLayer");
        if (CatchZoneNode == null) CatchZoneNode = GetNode<CatchZone>("CatchZone");
        if (CoinsLabel == null) CoinsLabel = GetNode<Label>("UI/CoinsLabel");
        if (PauseMenu == null) PauseMenu = GetNode<Control>("UI/PauseMenu");
        if (GameOverOverlay == null) GameOverOverlay = GetNode<Control>("UI/GameOverOverlay");
        if (GameOverStats == null) GameOverStats = GetNode<Label>("UI/GameOverOverlay/VBox/GameOverStats");
        if (ShootButton == null) ShootButton = GetNode<Button>("UI/ShootButton");
        if (PauseButton == null) PauseButton = GetNode<Button>("UI/PauseButton");

        // 設定接幣區的攝影機（用於滑鼠轉 3D 座標）
        _camera = GetNodeOrNull<Camera3D>("Camera3D");
        if (_camera != null) CatchZoneNode.GameCamera = _camera;

        // 攝影機對準接幣前緣（視角稍高）
        if (_camera != null) _camera.LookAt(new Vector3(0f, 1.5f, 1.2f), Vector3.Up);

        _coinsRemaining = GameManager.InitialCoins;
        _coinsCollected = 0;
        _gameStartTime = Time.GetTicksMsec() / 1000.0;
        _gameOver = false;
        _paused = false;

        UpdateCoinsLabel();
        PauseMenu.Visible = false;
        GameOverOverlay.Visible = false;

        CatchZoneNode.CoinCaught += OnCoinCaught;
        ShootButton.Pressed += OnShootPressed;
        PauseButton.Pressed += OnPauseButtonPressed;

        GetNode<Button>("UI/PauseMenu/VBox/ResumeButton").Pressed += OnResumePressed;
        GetNode<Button>("UI/PauseMenu/VBox/MainMenuButton").Pressed += OnPauseMainMenuPressed;

        _lastAimPosition = ShootOrigin.GlobalPosition;
        SpawnInitialCoinsOnLowerLayer();
        StartUpperLayerAnimation();
    }

    private void SpawnInitialCoinsOnLowerLayer()
    {
        var rng = new RandomNumberGenerator();
        rng.Randomize();

        for (var i = 0; i < InitialCoinsOnLower; i++)
        {
            var coin = CoinScene.Instantiate<Coin>();
            var x = rng.RandfRange(LowerLayerMinX, LowerLayerMaxX);
            var z = rng.RandfRange(LowerLayerMinZ, LowerLayerMaxZ);
            coin.GlobalPosition = new Vector3(x, LowerLayerTopY, z);
            coin.LinearVelocity = Vector3.Zero;
            coin.AngularVelocity = Vector3.Zero;
            coin.Rotation = new Vector3(rng.RandfRange(-0.1f, 0.1f), rng.RandfRange(0, Mathf.Tau), rng.RandfRange(-0.1f, 0.1f));
            _coinsContainer.AddChild(coin);
        }
    }

    public override void _Process(double delta)
    {
        if (_gameOver || _paused) return;
        RecycleCoinsFallenOutOfView();
        UpdateLastAimPosition();
    }

    private void UpdateLastAimPosition()
    {
        _lastAimPosition = GetMouseWorldPositionOnShootPlane();
    }

    private void RecycleCoinsFallenOutOfView()
    {
        foreach (var coin in _coinsContainer.GetChildren().OfType<Coin>().ToList())
        {
            if (coin.GlobalPosition.Y < CoinRecycleThresholdY)
                coin.QueueFree();
        }
    }

    public override void _Input(InputEvent ev)
    {
        if (_gameOver || _paused) return;

        if (ev is InputEventMouseButton mb && mb.Pressed && mb.ButtonIndex == MouseButton.Left)
        {
            if (!ShootButton.GetGlobalRect().HasPoint(mb.GlobalPosition))
            {
                TryShoot();
            }
        }
    }

    private void StartUpperLayerAnimation()
    {
        var cycleTime = GameManager.UpperLayerCycleSeconds / 2;
        AnimateUpperLayer(true, cycleTime);
    }

    private void AnimateUpperLayer(bool extendTowardPlayer, float duration)
    {
        _upperLayerTween?.Kill();
        _upperLayerTween = CreateTween();

        var targetZ = extendTowardPlayer ? UpperLayerExtendedZ : UpperLayerRetractedZ;
        _upperLayerTween.TweenProperty(UpperLayer, "position:z", targetZ, duration)
            .SetEase(Tween.EaseType.InOut)
            .SetTrans(Tween.TransitionType.Sine);
        _upperLayerTween.TweenCallback(Callable.From(() => AnimateUpperLayer(!extendTowardPlayer, duration)));
    }

    private void TryShoot()
    {
        if (_coinsRemaining <= 0 || _gameOver || _paused) return;

        var spawnPos = _lastAimPosition;
        var coin = CoinScene.Instantiate<Coin>();
        coin.GlobalPosition = spawnPos;
        coin.LinearVelocity = new Vector3(0, -3f, 0f);  // 向下射至上層平台
        _coinsContainer.AddChild(coin);

        _coinsRemaining--;
        UpdateCoinsLabel();

        if (_coinsRemaining <= 0)
        {
            CallDeferred(MethodName.CheckGameOverAfterCoinsSettled);
        }
    }

    private Vector3 GetMouseWorldPositionOnShootPlane()
    {
        var shootOrigin = ShootOrigin.GlobalPosition;
        if (_camera == null) return shootOrigin;

        var viewport = GetViewport();
        var mousePos = viewport.GetMousePosition();
        var from = _camera.ProjectRayOrigin(mousePos);
        var dir = _camera.ProjectRayNormal(mousePos);
        // 使用上層平台高度平面，確保射線能正確相交
        var plane = new Plane(Vector3.Up, 0.7f);
        var intersect = plane.IntersectsRay(from, dir);
        if (intersect.HasValue)
        {
            var worldPos = intersect.Value;
            return new Vector3(
                Mathf.Clamp(worldPos.X, LowerLayerMinX, LowerLayerMaxX),
                shootOrigin.Y,
                shootOrigin.Z  // Z 固定於後板處
            );
        }
        return shootOrigin;
    }

    private void OnShootPressed()
    {
        TryShoot();
    }

    private async void CheckGameOverAfterCoinsSettled()
    {
        await ToSignal(GetTree().CreateTimer(2.0), SceneTreeTimer.SignalName.Timeout);
        if (_gameOver) return;
        if (_coinsRemaining > 0) return;

        var coins = _coinsContainer.GetChildren().OfType<Coin>().ToList();
        var anyMoving = coins.Any(c => GodotObject.IsInstanceValid(c) && c.LinearVelocity.Length() > 10);
        if (anyMoving)
        {
            CheckGameOverAfterCoinsSettled();
            return;
        }

        ShowGameOver();
    }

    private void OnCoinCaught(Coin coin)
    {
        if (_gameOver) return;

        _coinsCollected++;
        _coinsRemaining++;
        coin.QueueFree();
        UpdateCoinsLabel();
    }

    private void UpdateCoinsLabel()
    {
        CoinsLabel.Text = $"剩餘: {_coinsRemaining}";
    }

    private void ShowGameOver()
    {
        _gameOver = true;
        var elapsed = Time.GetTicksMsec() / 1000.0 - _gameStartTime;
        GameOverStats.Text = $"收集金幣: {_coinsCollected}\n存活時間: {elapsed:F1} 秒";
        GameOverOverlay.Visible = true;

        GetTree().CreateTimer(GameManager.GameOverDelaySeconds).Timeout += () =>
        {
            GetTree().ChangeSceneToFile("res://scenes/MainMenu.tscn");
        };
    }

    private void OnResumePressed()
    {
        _paused = false;
        GetTree().Paused = false;
        PauseMenu.Visible = false;
    }

    private void OnPauseMainMenuPressed()
    {
        GetTree().Paused = false;
        GetTree().ChangeSceneToFile("res://scenes/MainMenu.tscn");
    }

    private void OnPauseButtonPressed()
    {
        if (_gameOver) return;
        _paused = true;
        GetTree().Paused = true;
        PauseMenu.Visible = true;
    }
}
