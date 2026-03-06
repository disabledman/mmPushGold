using Godot;

namespace mmPushGold;

public partial class GameManager : Node
{
    public static GameManager Instance { get; private set; }

    public const int InitialCoins = 100;
    public const float UpperLayerCycleSeconds = 4f;
    public const float LogoDisplaySeconds = 2f;
    public const float GameOverDelaySeconds = 5f;

    public override void _Ready()
    {
        Instance = this;
    }

    public override void _ExitTree()
    {
        Instance = null;
    }
}
