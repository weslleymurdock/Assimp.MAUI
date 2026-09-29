using System.Text.Json;

namespace Assimp.MAUI.Sample;

public partial class ShaderPlaygroundPage : ContentPage
{
    private readonly SceneRenderer _renderer;
    private readonly Dictionary<string, string> _shaders = [];
    private bool _ready;

    public ShaderPlaygroundPage(SceneRenderer renderer)
    {
        _renderer = renderer;
        InitializeComponent();
        ShaderView.Navigated += OnNavigated;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();

        if (_ready)
            return;

        var html = await LoadAssetAsync("shader-playground.html");
        ShaderView.Source = new HtmlWebViewSource { Html = html };
    }

    private async void OnNavigated(object? sender, WebNavigatedEventArgs e)
    {
        if (e.Result != WebNavigationResult.Success || _ready)
            return;

        ShaderView.Navigated -= OnNavigated;
        _shaders.Clear();

        foreach (var name in new[]
        {
            "Shaders/FlatColor.frag.glsl",
            "Shaders/Normal.frag.glsl",
            "Shaders/RimLight.frag.glsl"
        })
        {
            _shaders[Path.GetFileName(name)] = await LoadAssetAsync(name);
        }

        ShaderPicker.ItemsSource = _shaders.Keys.ToList();
        await SendSceneAsync();

        if (ShaderPicker.Items.Count > 0)
            ShaderPicker.SelectedIndex = 0;

        _ready = true;
    }

    private async void OnShaderSelected(object? sender, EventArgs e)
    {
        if (!_ready || ShaderPicker.SelectedItem is not string name)
            return;

        await SendShaderAsync(name);
    }

    private async void OnCompileClicked(object? sender, EventArgs e)
    {
        await CompileAndReportAsync();
    }

    private async void OnResetShaderClicked(object? sender, EventArgs e)
    {
        if (!_ready || ShaderPicker.SelectedItem is not string name)
            return;

        await SendShaderAsync(name);
    }

    private async Task SendSceneAsync()
    {
        var geometry = _renderer.ExportShaderMeshes();
        var json = JsonSerializer.Serialize(geometry);
        await ShaderView.EvaluateJavaScriptAsync(
            $"setMeshData({JsonSerializer.Serialize(json)})");
    }

    private async Task SendShaderAsync(string name)
    {
        await ShaderView.EvaluateJavaScriptAsync(
            $"setFragmentShader({JsonSerializer.Serialize(_shaders[name])})");
        await CompileAndReportAsync();
    }

    private async Task CompileAndReportAsync()
    {
        if (!_ready && ShaderView.Source is null)
            return;

        try
        {
            var result = await ShaderView.EvaluateJavaScriptAsync("compileCurrentShader()");
            ConsoleLabel.Text = $"Console: {result}";
        }
        catch (Exception ex)
        {
            ConsoleLabel.Text = $"Console: {ex.Message}";
        }
    }

    private static async Task<string> LoadAssetAsync(string name)
    {
        await using var stream = await FileSystem.OpenAppPackageFileAsync(name);
        using var reader = new StreamReader(stream);
        return await reader.ReadToEndAsync();
    }
}
