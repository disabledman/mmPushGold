using Godot;

namespace mmPushGold;

public partial class Logo : Control
{
    private Timer _timer = null!;

    public override void _Ready()
    {
        _timer = GetNode<Timer>("Timer");
        _timer.Timeout += OnTimerTimeout;
        _timer.Start(GameManager.LogoDisplaySeconds);

        // Click/tap to skip
        MouseFilter = Control.MouseFilterEnum.Stop;
        GuiInput += OnGuiInput;
    }

    private void OnGuiInput(InputEvent ev)
    {
        if (ev is InputEventMouseButton mb && mb.Pressed && mb.ButtonIndex == MouseButton.Left)
        {
            GoToMainMenu();
        }
        if (ev is InputEventScreenTouch st && st.Pressed)
        {
            GoToMainMenu();
        }
    }

    private void OnTimerTimeout()
    {
        GoToMainMenu();
    }

    private void GoToMainMenu()
    {
        _timer.Stop();
        GetTree().ChangeSceneToFile("res://scenes/MainMenu.tscn");
    }
}
