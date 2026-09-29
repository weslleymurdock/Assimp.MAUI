using Assimp.Maui;
using Assimp.MAUI.Sample.Renderers;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Maui.Graphics.Platform;
using System.Collections.ObjectModel;

namespace Assimp.MAUI.Sample.ViewModels;

public sealed partial class MainViewModel : ViewModelBase, IDisposable
{
    private readonly SceneRenderer _renderer;
    private IDispatcherTimer? _timer;
    private Scene? _scene;
    private bool _autoRotate;
    private PointF _lastPoint;
    private bool _hasInteraction;
    private bool _disposed;

    internal GraphicsView SceneView { get; set; } = default!;

    public SceneRenderer Renderer => _renderer;

    [ObservableProperty]
    public partial string PageTitle { get; set; } = "Assimp.MAUI";

    [ObservableProperty]
    public partial string PageDescription { get; set; } = "3D asset, material, texture and shader playground demonstration.";

    [ObservableProperty]
    public partial string ShaderPlaygroundButtonLabel { get; set; } = "Shader Playground";

    [ObservableProperty]
    public partial string OpenFileButtonLabel { get; set; } = "Open 3D";

    [ObservableProperty]
    public partial string TextureButtonLabel { get; set; } = "Texture";

    [ObservableProperty]
    public partial string ResetButtonLabel { get; set; } = "Reset";

    [ObservableProperty]
    public partial string AutoRotateButtonLabel { get; set; } = "Auto rotate";

    [ObservableProperty]
    public partial string MaterialLabel { get; set; } = "Material";

    [ObservableProperty]
    public partial string MaterialPickerTitle { get; set; } = "Imported material";

    [ObservableProperty]
    public partial string ApplyMaterialButtonLabel { get; set; } = "Apply";

    [ObservableProperty]
    public partial string ColorLabel { get; set; } = "Color";

    [ObservableProperty]
    public partial string ColorHex { get; set; } = "#4F8EF7";

    [ObservableProperty]
    public partial string RoughnessLabel { get; set; } = "Roughness";

    [ObservableProperty]
    public partial double Roughness { get; set; } = 0.45;

    [ObservableProperty]
    public partial string LightingButtonLabel { get; set; } = "Lighting";

    [ObservableProperty]
    public partial string TextureToggleButtonLabel { get; set; } = "Texture On/Off";

    [ObservableProperty]
    public partial string WireframeButtonLabel { get; set; } = "Wireframe";

    [ObservableProperty]
    public partial string FileLabel { get; set; } = "No scene loaded";

    [ObservableProperty]
    public partial string StatsLabel { get; set; } = "Scene: —";

    [ObservableProperty]
    public partial string TextureLabel { get; set; } = "No texture";

    [ObservableProperty]
    public partial string InstructionsLabel { get; set; } =
        "Drag the preview to orbit. The shader playground can consume the same Assimp mesh data.";

    [ObservableProperty]
    public partial ObservableCollection<string> MaterialOptions { get; set; } = [];

    [ObservableProperty]
    public partial int SelectedMaterialIndex { get; set; } = -1;

    public MainViewModel(SceneRenderer renderer)
    {
        _renderer = renderer;

        var dispatcher = Dispatcher.GetForCurrentThread();
        if (dispatcher is null)
            return;

        _timer = dispatcher.CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(16);
        _timer.Tick += OnAutoRotateTick;
    }

    private void OnAutoRotateTick(object? sender, EventArgs e)
    {
        if (!_autoRotate)
            return;

        _renderer.Rotate(4.2f, 0);
        SceneView?.Invalidate();
    }

    [RelayCommand]
    private async Task OpenFile()
    {
        try
        {
            var file = await FilePicker.Default.PickAsync(new PickOptions
            {
                PickerTitle = "Choose an Assimp-supported 3D asset"
            });

            if (file is not null)
                await LoadSceneAsync(file);
        }
        catch (Exception ex)
        {
            await ShowErrorAsync("Unable to load scene", ex.Message);
        }
    }

    [RelayCommand]
    private async Task AddTexture()
    {
        try
        {
            var file = await FilePicker.Default.PickAsync(new PickOptions
            {
                PickerTitle = "Choose a texture for the loaded 3D asset",
                FileTypes = FilePickerFileType.Images
            });

            if (file is null)
                return;

            await using var stream = await file.OpenReadAsync();
            var image = PlatformImage.FromStream(stream);
            _renderer.SetTexture(image, file.FileName);
            TextureLabel = _renderer.TextureDescription;
            SceneView?.Invalidate();
        }
        catch (Exception ex)
        {
            await ShowErrorAsync("Unable to load texture", ex.Message);
        }
    }

    [RelayCommand]
    private async Task ShaderPlayground()
    {
        if (_scene is null)
        {
            await ShowErrorAsync("Shader Playground", "Load a 3D scene before opening the shader playground.");
            return;
        }

        await Shell.Current.GoToAsync(nameof(Views.ShaderPlaygroundPage));
    }

    [RelayCommand]
    private void AutoRotate()
    {
        _autoRotate = !_autoRotate;
        AutoRotateButtonLabel = _autoRotate ? "Stop rotate" : "Auto rotate";

        if (_autoRotate)
            _timer?.Start();
        else
            _timer?.Stop();
    }

    [RelayCommand]
    private void Reset()
    {
        _renderer.ResetCamera();
        SceneView?.Invalidate();
    }

    [RelayCommand]
    private void ApplyMaterial()
    {
        if (SelectedMaterialIndex < 0)
            return;

        if (!TryParseColor(ColorHex, out var color))
            return;

        _renderer.SetMaterial(
            checked((uint)SelectedMaterialIndex),
            color,
            (float)Math.Clamp(Roughness, 0, 1));

        SceneView?.Invalidate();
    }

    [RelayCommand]
    private void Lighting()
    {
        _renderer.ToggleLighting();
        LightingButtonLabel = LightingButtonLabel == "Lighting" ? "Lighting Off" : "Lighting";
        SceneView?.Invalidate();
    }

    [RelayCommand]
    private void TextureToggle()
    {
        _renderer.ToggleTexture();
        TextureToggleButtonLabel =
            TextureToggleButtonLabel == "Texture On/Off" ? "Texture On" : "Texture On/Off";
        SceneView?.Invalidate();
    }

    [RelayCommand]
    private void Wireframe()
    {
        _renderer.ToggleWireframe();
        WireframeButtonLabel = WireframeButtonLabel == "Wireframe" ? "Wireframe On" : "Wireframe";
        SceneView?.Invalidate();
    }

    [RelayCommand]
    private void StartInteraction(TouchEventArgs e)
    {
        if (e.Touches.Length == 0)
            return;

        _lastPoint = e.Touches[0];
        _hasInteraction = true;
    }

    [RelayCommand]
    private void DragInteraction(TouchEventArgs e)
    {
        if (!_hasInteraction || e.Touches.Length == 0)
            return;

        var point = e.Touches[0];
        _renderer.Rotate(point.X - _lastPoint.X, point.Y - _lastPoint.Y);
        _lastPoint = point;
        SceneView?.Invalidate();
    }

    [RelayCommand]
    private void EndInteraction(TouchEventArgs e)
    {
        _hasInteraction = false;
        _lastPoint = default;
    }

    private async Task LoadSceneAsync(FileResult file)
    {
        var localPath = Path.Combine(
            Microsoft.Maui.Storage.FileSystem.CacheDirectory,
            $"{Guid.CreateVersion7():N}_{file.FileName}");

        await using (var source = await file.OpenReadAsync())
        await using (var destination = System.IO.File.Create(localPath))
            await source.CopyToAsync(destination);

        Scene? scene = null;

        try
        {
            scene = Maui.Assimp.ImportFile(
                localPath,
                (uint)(PostProcessSteps.Process_Triangulate |
                       PostProcessSteps.Process_JoinIdenticalVertices |
                       PostProcessSteps.Process_GenSmoothNormals |
                       PostProcessSteps.Process_CalcTangentSpace));

            if (scene is null || !scene.HasMeshes())
            {
                var error = Maui.Assimp.GetErrorString();
                throw new InvalidOperationException(
                    string.IsNullOrWhiteSpace(error)
                        ? "Assimp did not return a scene containing meshes."
                        : error);
            }

            _renderer.SetScene(scene);
            _renderer.ResetCamera();

            _scene?.Dispose();
            _scene = scene;
            scene = null;

            FileLabel = file.FileName;
            StatsLabel =
                $"Scene: {_renderer.MeshCount:N0} mesh(es), {_renderer.VertexCount:N0} vertices, {_renderer.FaceCount:N0} faces";

            MaterialOptions.Clear();
            for (var index = 0; index < _renderer.MaterialCount; index++)
                MaterialOptions.Add($"Material {index}");

            SelectedMaterialIndex = MaterialOptions.Count > 0 ? 0 : -1;
            TextureLabel = _renderer.TextureDescription;
            SceneView?.Invalidate();
        }
        finally
        {
            scene?.Dispose();
            try
            {
                System.IO.File.Delete(localPath);
            }
            catch
            {
                // The cache file is best-effort cleanup only.
            }
        }
    }

    private static bool TryParseColor(string value, out Color color)
    {
        color = Colors.CornflowerBlue;

        if (string.IsNullOrWhiteSpace(value))
            return false;

        var hex = value.Trim().TrimStart('#');
        if (hex.Length == 6 &&
            byte.TryParse(hex[..2], System.Globalization.NumberStyles.HexNumber, null, out var r) &&
            byte.TryParse(hex[2..4], System.Globalization.NumberStyles.HexNumber, null, out var g) &&
            byte.TryParse(hex[4..6], System.Globalization.NumberStyles.HexNumber, null, out var b))
        {
            color = Color.FromRgba(r, g, b, byte.Parse("255", System.Globalization.NumberStyles.Integer));
            return true;
        }

        return false;
    }

    private static Task ShowErrorAsync(string title, string message) =>
        Shell.Current.CurrentPage.DisplayAlertAsync(title, message, "OK");

    public void Dispose()
    {
        if (_disposed)
            return;

        _disposed = true;
        _timer?.Stop();
        _timer = null;
        _scene?.Dispose();
        _scene = null;
        _renderer.SetTexture(null, null);
        GC.SuppressFinalize(this);
    }
}
