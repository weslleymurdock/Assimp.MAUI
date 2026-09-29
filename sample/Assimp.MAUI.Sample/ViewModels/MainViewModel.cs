using Assimp.Maui;
using Assimp.MAUI.Sample.Renderers;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Assimp.MAUI.Sample.ViewModels;

public sealed partial class MainViewModel: ViewModelBase, IDisposable
{
    private readonly SceneRenderer _renderer;
    private IDispatcherTimer? _timer;
    private Scene? _scene;
    private bool _autoRotate;
    private PointF _lastPoint;
    private bool disposedValue;
    internal GraphicsView SceneView { get; set; } = default!;
    public SceneRenderer Renderer => _renderer;

    [ObservableProperty]
    public partial string FileLabel { get; set; } = "No scene loaded";
    [ObservableProperty]
    public partial string StatsLabel { get; set; } = "Assimp scene: —";
    [ObservableProperty]
    public partial string AutoRotateButtonLabel { get; set; } = "Auto rotate";
    public MainViewModel(SceneRenderer renderer)
    {
        _renderer = renderer;

        _autoRotate = false;

        var dispatcher = Dispatcher.GetForCurrentThread();
        if (dispatcher != null)
        {
            _timer = dispatcher.CreateTimer();
            _timer.Interval = TimeSpan.FromMilliseconds(6);
            _timer.Tick += (_, _) =>
            {
                if (!_autoRotate)
                    return;

                _renderer.Rotate(4.20f, 0);
                SceneView.Invalidate();
            };
        }
        else
        { 
            _timer = null;
        }
    }
    #region Methods
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

            FileLabel = file.FileName;
            StatsLabel =
                $"Scene: {_renderer.MeshCount} mesh(es), {_renderer.VertexCount:N0} vertices, {_renderer.FaceCount:N0} faces";
            SceneView.Invalidate();
        }
        finally
        {
            scene?.Dispose();
            try { System.IO.File.Delete(localPath); } catch { }
        }
    }

    #endregion

    #region Commands
    [RelayCommand]
    private async Task OpenFile()
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
            await Shell.Current.CurrentPage.DisplayAlertAsync("Unable to load scene", ex.Message, "OK");
        }
    }
    [RelayCommand]
    private async Task AddTexture()
    {
        try
        {
            var file = await FilePicker.Default.PickAsync(new PickOptions
            {
                PickerTitle = "Choose an texture for the loaded3D asset"
            });

            if (file is null)
                return;

            // TODO: Load the texture file and apply it to the scene
        }
        catch (Exception ex)
        {
            await Shell.Current.CurrentPage.DisplayAlertAsync("Unable to load texture", ex.Message, "OK");
        }
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
        SceneView.Invalidate();
    }
    #endregion

    #region Events
    internal void OnStartInteraction(object? sender, TouchEventArgs e)
    {
        if (e.Touches.Length > 0)
            _lastPoint = e.Touches[0];
    }
    internal void OnDragInteraction(object? sender, TouchEventArgs e)
    {
        if (e.Touches.Length == 0)
            return;

        var point = e.Touches[0];
        _renderer.Rotate(point.X - _lastPoint.X, point.Y - _lastPoint.Y);
        _lastPoint = point;
        SceneView.Invalidate();
    }
    internal void OnEndInteraction(object? sender, TouchEventArgs e) => _lastPoint = default;

    #endregion

    #region Disposing
    private void Dispose(bool disposing)
    {
        if (!disposedValue)
        {
            if (disposing)
            {
                _timer?.Stop();
                _scene?.Dispose();
                _scene = null;
            }
            disposedValue = true;
        }
    }
    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);
    }
    #endregion
}
