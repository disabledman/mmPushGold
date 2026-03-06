using Godot;

namespace mmPushGold;

public partial class Coin : RigidBody3D
{
    private const float CoinRadius = 0.15f;
    private const float CoinHeight = 0.06f;  // 扁平圓柱

    public static float Diameter => CoinRadius * 2;

    public override void _Ready()
    {
        LockRotation = false;
        GravityScale = 1f;
        CollisionLayer = 1; // coins layer
        CollisionMask = 0xFFFFFFFF; // collide with everything
    }
}
