#if !IOS && !MACCATALYST
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
        var localPath = Path.Combine(Microsoft.Maui.Storage.FileSystem.CacheDirectory, $"{Guid.CreateVersion7():N}_{file.FileName}");

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
                       PostProcessSteps.Process_GenSmoothNormals));

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

            FileLabel.Text = file.FileName;
            StatsLabel.Text =
                $"Scene: {_renderer.MeshCount} mesh(es), {_renderer.VertexCount:N0} vertices, {_renderer.FaceCount:N0} faces";
            SceneView.Invalidate();
        }
        finally
        {
            scene?.Dispose();
            try { System.IO.File.Delete(localPath); } catch { }
        }
    }

    private void OnResetClicked(object? sender, EventArgs e)
    {
        _renderer.ResetCamera();
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

    protected override void OnDisappearing()
    {
        _timer?.Stop();
        _scene?.Dispose();
        _scene = null;
        base.OnDisappearing();
    }
}
#endif