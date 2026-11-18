using Assimp.MAUI.Sample.ViewModels;

namespace Assimp.MAUI.Sample.Views;

public partial class MainPage : ContentPage
{
    private readonly MainViewModel _viewModel;

    public MainPage(MainViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        _viewModel.SceneView = SceneView;
        BindingContext = _viewModel;
    }

    protected override void OnDisappearing()
    {
        _viewModel.Dispose();
        base.OnDisappearing();
    }
}
