using Microsoft.Maui.Graphics.Platform;
using System.Globalization;
using Assimp.Maui;

namespace Assimp.MAUI.Sample;

public partial class MainPage : ContentPage
{
    private readonly SceneRenderer _renderer = new();
    private PointF _lastPoint;
    private bool _autoRotate;
    private IDispatcherTimer? _timer;
    private Scene? _scene;

    public SceneRenderer Renderer => _renderer;

    public MainPage()
    {
        InitializeComponent();
        BindingContext = this;
        _timer = Dispatcher.CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(16);
        _timer.Tick += (_, _) =>
        {
            if (!_autoRotate)
                return;
            _renderer.Rotate(0.7f, 0);
            SceneView.Invalidate();
        };
    }

    private async void OnOpenFileClicked(object? sender, EventArgs e)
    {
        try
        {
            var file = await FilePicker.Default.PickAsync(new PickOptions
            {
                PickerTitle = "Choose an Assimp-supported 3D asset"
            });
            if (file is null)
                return;

            await LoadSceneAsync(file);
        }
        catch (Exception ex)
        {
            await DisplayAlertAsync("Unable to load scene", ex.Message, "OK");
        }
    }

    private async Task LoadSceneAsync(FileResult file)
    {
        var localPath = Path.Combine(FileSystem.CacheDirectory, $"{Guid.CreateVersion7():N}_{file.FileName}");
        await using (var source = await file.OpenReadAsync())
        await using (var destination = File.Create(localPath))
            await source.CopyToAsync(destination);

        Scene? imported = null;
        try
        {
            imported = Maui.Assimp.ImportFile(
                localPath,
                (uint)(PostProcessSteps.Process_Triangulate |
                       PostProcessSteps.Process_JoinIdenticalVertices |
                       PostProcessSteps.Process_GenSmoothNormals |
                       PostProcessSteps.Process_CalcTangentSpace));

            if (imported is null || !imported.HasMeshes())
            {
                var error = Maui.Assimp.GetErrorString();
                throw new InvalidOperationException(
                    string.IsNullOrWhiteSpace(error) ? "Assimp returned no mesh." : error);
            }

            _renderer.SetScene(imported);
            _renderer.ResetCamera();
            _scene?.Dispose();
            _scene = imported;
            imported = null;

            MaterialPicker.ItemsSource = Enumerable.Range(0, _renderer.MaterialCount)
                .Select(index => $"Material {index}")
                .ToList();
            if (MaterialPicker.Items.Count > 0)
                MaterialPicker.SelectedIndex = 0;

            FileLabel.Text = file.FileName;
            StatsLabel.Text =
                $"Scene: {_renderer.MeshCount} mesh(es) • {_renderer.VertexCount:N0} vertices • {_renderer.FaceCount:N0} faces • {_renderer.MaterialCount} material(s)";
            TextureLabel.Text = _renderer.TextureDescription;
            SceneView.Invalidate();
        }
        finally
        {
            imported?.Dispose();
            try { File.Delete(localPath); } catch { }
        }
    }

    private async void OnTextureClicked(object? sender, EventArgs e)
    {
        try
        {
            var file = await FilePicker.Default.PickAsync(new PickOptions
            {
                PickerTitle = "Choose a texture",
                FileTypes = FilePickerFileType.Images
            });
            if (file is null)
                return;

            await using var stream = await file.OpenReadAsync();
            var image = PlatformImage.FromStream(stream);
            _renderer.SetTexture(image, file.FileName);
            TextureLabel.Text = _renderer.TextureDescription;
            SceneView.Invalidate();
        }
        catch (Exception ex)
        {
            await DisplayAlertAsync("Unable to load texture", ex.Message, "OK");
        }
    }

    private async void OnApplyMaterialClicked(object? sender, EventArgs e)
    {
        if (MaterialPicker.SelectedIndex < 0)
            return;

        if (!TryParseColor(ColorEntry.Text, out var color))
        {
            await DisplayAlertAsync("Invalid color", "Use #RRGGBB or #AARRGGBB.", "OK");
            return;
        }

        _renderer.SetMaterial(
            (uint)MaterialPicker.SelectedIndex,
            color,
            (float)RoughnessSlider.Value);

        SceneView.Invalidate();
    }

    private void OnResetClicked(object? sender, EventArgs e)
    {
        _renderer.ResetCamera();
        SceneView.Invalidate();
    }

    private void OnLightingClicked(object? sender, EventArgs e)
    {
        _renderer.ToggleLighting();
        SceneView.Invalidate();
    }

    private void OnTextureToggleClicked(object? sender, EventArgs e)
    {
        _renderer.ToggleTexture();
        SceneView.Invalidate();
    }

    private void OnWireframeClicked(object? sender, EventArgs e)
    {
        _renderer.ToggleWireframe();
        SceneView.Invalidate();
    }

    private void OnAutoRotateClicked(object? sender, EventArgs e)
    {
        _autoRotate = !_autoRotate;
        AutoRotateButton.Text = _autoRotate ? "Stop rotate" : "Auto rotate";
        if (_autoRotate)
            _timer?.Start();
        else
            _timer?.Stop();
    }

    private async void OnShaderPlaygroundClicked(object? sender, EventArgs e)
    {
        if (_scene is null)
        {
            await DisplayAlertAsync("Shader Playground", "Load a 3D object first so the playground can preview it.", "OK");
            return;
        }

        await Navigation.PushAsync(new ShaderPlaygroundPage(_renderer));
    }

    private void OnStartInteraction(object? sender, TouchEventArgs e)
    {
        if (e.Touches.Length > 0)
            _lastPoint = e.Touches[0];
    }

    private void OnDragInteraction(object? sender, TouchEventArgs e)
    {
        if (e.Touches.Length == 0)
            return;

        var point = e.Touches[0];
        _renderer.Rotate(point.X - _lastPoint.X, point.Y - _lastPoint.Y);
        _lastPoint = point;
        SceneView.Invalidate();
    }

    private void OnEndInteraction(object? sender, TouchEventArgs e) => _lastPoint = default;

    private static bool TryParseColor(string? value, out Color color)
    {
        color = Colors.CornflowerBlue;
        if (string.IsNullOrWhiteSpace(value))
            return false;

        var text = value.Trim().TrimStart('#');
        if (text.Length is not (6 or 8))
            return false;

        if (!uint.TryParse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var argb))
            return false;

        if (text.Length == 6)
            argb |= 0xFF000000;

        color = Color.FromRgba(
            (byte)(argb >> 16),
            (byte)(argb >> 8),
            (byte)argb,
            (byte)(argb >> 24));
        return true;
    }

    protected override void OnDisappearing()
    {
        _timer?.Stop();
        base.OnDisappearing();
    }
}
