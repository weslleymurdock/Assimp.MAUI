using Assimp.MAUI.Sample.Renderers;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System.Text.Json;

namespace Assimp.MAUI.Sample.ViewModels;

public sealed partial class ShaderPlaygroundViewModel : ViewModelBase
{
    private static readonly string[] ShaderAssetNames =
    [
        "Shaders/FlatColor.frag.glsl",
        "Shaders/Normal.frag.glsl",
        "Shaders/RimLight.frag.glsl"
    ];

    private readonly SceneRenderer _renderer;
    private readonly Dictionary<string, string> _shaders = [];
    private WebView? _shaderView;
    private bool _ready;

    public ShaderPlaygroundViewModel(SceneRenderer renderer)
    {
        _renderer = renderer;
    }

    [ObservableProperty]
    public partial string PageTitle { get; set; } = "Shader Playground";

    [ObservableProperty]
    public partial string PageDescription { get; set; } =
        "Edit GLSL, compile it in WebGL, and preview it on the imported mesh.";

    [ObservableProperty]
    public partial string ShaderPickerTitle { get; set; } = "Shader example";

    [ObservableProperty]
    public partial string ConsoleLabel { get; set; } = "Console: ready";

    [ObservableProperty]
    public partial string CompileButtonLabel { get; set; } = "Compile";

    [ObservableProperty]
    public partial string ResetShaderButtonLabel { get; set; } = "Reset shader";

    [ObservableProperty]
    public partial List<string> ShaderNames { get; set; } = [];

    [ObservableProperty]
    public partial string? SelectedShader { get; set; }

    internal void AttachWebView(WebView shaderView)
    {
        _shaderView = shaderView;
    }

    internal async Task OnAppearingAsync()
    {
        if (_shaderView is null || _ready)
            return;

        var html = await LoadAssetAsync("shader-playground.html");
        _shaderView.Source = new HtmlWebViewSource { Html = html };
    }

    internal async Task OnNavigatedAsync(WebNavigationResult result)
    {
        if (result != WebNavigationResult.Success || _shaderView is null || _ready)
            return;

        _shaders.Clear();

        foreach (var name in ShaderAssetNames)
            _shaders[Path.GetFileName(name)] = await LoadAssetAsync(name);

        ShaderNames = [.. _shaders.Keys];
        await SendSceneAsync();

        _ready = true;
        SelectedShader = ShaderNames.FirstOrDefault();
    }

    partial void OnSelectedShaderChanged(string? value)
    {
        if (!_ready || string.IsNullOrWhiteSpace(value))
            return;

        _ = SendShaderAsync(value);
    }

    [RelayCommand]
    private async Task Compile()
    {
        await CompileAndReportAsync();
    }

    [RelayCommand]
    private async Task ResetShader()
    {
        if (!_ready || string.IsNullOrWhiteSpace(SelectedShader))
            return;

        await SendShaderAsync(SelectedShader);
    }

    private async Task SendSceneAsync()
    {
        if (_shaderView is null)
            return;

        var geometry = _renderer.ExportShaderMeshes();
        var json = JsonSerializer.Serialize(geometry);
        await _shaderView.EvaluateJavaScriptAsync(
            $"setMeshData({JsonSerializer.Serialize(json)})");
    }

    private async Task SendShaderAsync(string name)
    {
        if (_shaderView is null || !_shaders.TryGetValue(name, out var shader))
            return;

        await _shaderView.EvaluateJavaScriptAsync(
            $"setFragmentShader({JsonSerializer.Serialize(shader)})");

        await CompileAndReportAsync();
    }

    private async Task CompileAndReportAsync()
    {
        if (_shaderView is null || !_ready)
            return;

        try
        {
            var result = await _shaderView.EvaluateJavaScriptAsync("compileCurrentShader()");
            ConsoleLabel = $"Console: {result}";
        }
        catch (Exception ex)
        {
            ConsoleLabel = $"Console: {ex.Message}";
        }
    }

    private static async Task<string> LoadAssetAsync(string name)
    {
        await using var stream = await FileSystem.OpenAppPackageFileAsync(name);
        using var reader = new StreamReader(stream);
        return await reader.ReadToEndAsync();
    }
}
