using Assimp.MAUI.Sample.ViewModels;

namespace Assimp.MAUI.Sample.Views;

public partial class ShaderPlaygroundPage : ContentPage
{
    private readonly ShaderPlaygroundViewModel _viewModel;

    public ShaderPlaygroundPage(ShaderPlaygroundViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        _viewModel.AttachWebView(ShaderView);
        BindingContext = _viewModel;
        ShaderView.Navigated += OnNavigated;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await _viewModel.OnAppearingAsync();
    }

    private async void OnNavigated(object? sender, WebNavigatedEventArgs e)
    {
        await _viewModel.OnNavigatedAsync(e.Result);
    }
}
