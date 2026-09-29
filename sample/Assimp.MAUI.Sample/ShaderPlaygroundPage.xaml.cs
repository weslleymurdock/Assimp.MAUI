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

    private async void OnNavigated(object? sender, WebNavigatedEventArgs e)
    {
        if (e.Result != WebNavigationResult.Success)
        {
            ConsoleLabel.Text = $"Console: WebView navigation failed ({e.Result}).";
            return;
        }

        ShaderView.Navigated -= OnNavigated;
        await LoadPlaygroundAsync();
    }

    private async Task LoadPlaygroundAsync()
    {
        var html = await LoadAssetAsync("shader-playground.html");
        ShaderView.Source = new HtmlWebViewSource { Html = html };
        ShaderView.Navigated += OnPlaygroundReady;
    }

    private async void OnPlaygroundReady(object? sender, WebNavigatedEventArgs e)
    {
        if (e.Result != WebNavigationResult.Success)
            return;

        ShaderView.Navigated -= OnPlaygroundReady;
        _shaders.Clear();

        foreach (var name in new[]
        {
            "Shaders/FlatColor.frag.glsl",
            "Shaders/Normal.frag.glsl",
            "Shaders/RimLight.frag.glsl"
        })
        {
            var key = Path.GetFileName(name);
            _shaders[key] = await LoadAssetAsync(name);
        }

        ShaderPicker.ItemsSource = _shaders.Keys.ToList();
        if (ShaderPicker.Items.Count > 0)
            ShaderPicker.SelectedIndex = 0;

        await SendSceneAsync();
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
        if (!_ready)
            return;

        var result = await ShaderView.EvaluateJavaScriptAsync("compileCurrentShader()");
        ConsoleLabel.Text = $"Console: {result}";
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
        await ShaderView.EvaluateJavaScriptAsync($"setMeshData({JsonSerializer.Serialize(json)})");
    }

    private async Task SendShaderAsync(string name)
    {
        var shader = _shaders[name];
        await ShaderView.EvaluateJavaScriptAsync($"setFragmentShader({JsonSerializer.Serialize(shader)})");
        await CompileAndReportAsync();
    }

    private async Task CompileAndReportAsync()
    {
        var result = await ShaderView.EvaluateJavaScriptAsync("compileCurrentShader()");
        ConsoleLabel.Text = $"Console: {result}";
    }

    private static async Task<string> LoadAssetAsync(string name)
    {
        await using var stream = await FileSystem.OpenAppPackageFileAsync(name);
        using var reader = new StreamReader(stream);
        return await reader.ReadToEndAsync();
    }
}
