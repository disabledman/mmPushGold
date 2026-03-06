#nullable enable
using System;
using Godot;

namespace mmPushGold;

public partial class CatchZone : Area3D
{
    [Export] public float MoveSpeed { get; set; } = 8f;
    [Export] public float LeftBound { get; set; } = -4f;
    [Export] public float RightBound { get; set; } = 4f;

    public event Action<Coin>? CoinCaught;

    [Export] public Camera3D? GameCamera { get; set; }

    public override void _Ready()
    {
        BodyEntered += OnBodyEntered;
        CollisionLayer = 2; // catch_zone
        CollisionMask = 1;  // coins
    }

    public override void _Process(double delta)
    {
        if (GameCamera == null) return;

        // 將滑鼠螢幕位置轉為 3D 世界座標（與接幣區同平面 Y）
        var viewport = GetViewport();
        var mousePos = viewport.GetMousePosition();
        var from = GameCamera.ProjectRayOrigin(mousePos);
        var to = from + GameCamera.ProjectRayNormal(mousePos) * 100f;
        var plane = new Plane(Vector3.Up, Position.Y);
        var intersect = plane.IntersectsRay(from, to - from);
        if (intersect.HasValue)
        {
            var worldPos = intersect.Value;
            Position = new Vector3(Mathf.Clamp(worldPos.X, LeftBound, RightBound), Position.Y, Position.Z);
            return;
        }

        // 鍵盤備用
        var moveDir = 0f;
        if (Input.IsKeyPressed(Key.Left) || Input.IsKeyPressed(Key.A))
            moveDir = -1;
        if (Input.IsKeyPressed(Key.Right) || Input.IsKeyPressed(Key.D))
            moveDir = 1;

        if (moveDir != 0)
        {
            var newX = Position.X + moveDir * MoveSpeed * (float)delta;
            Position = new Vector3(Mathf.Clamp(newX, LeftBound, RightBound), Position.Y, Position.Z);
        }
    }

    public void SetTouchPosition(Vector3 worldPos)
    {
        Position = new Vector3(Mathf.Clamp(worldPos.X, LeftBound, RightBound), Position.Y, Position.Z);
    }

    private void OnBodyEntered(Node3D body)
    {
        if (body is Coin coin)
        {
            CoinCaught?.Invoke(coin);
        }
    }
}
