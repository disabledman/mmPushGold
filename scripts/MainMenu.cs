using Godot;

namespace mmPushGold;

public partial class MainMenu : Control
{
    private Button _startButton = null!;
    private Button _quitButton = null!;

    public override void _Ready()
    {
        _startButton = GetNode<Button>("VBoxContainer/StartButton");
        _quitButton = GetNode<Button>("VBoxContainer/QuitButton");

        _startButton.Pressed += OnStartPressed;
        _quitButton.Pressed += OnQuitPressed;
    }

    private void OnStartPressed()
    {
        GetTree().ChangeSceneToFile("res://scenes/Game.tscn");
    }

    private void OnQuitPressed()
    {
        GetTree().Quit();
    }
}
