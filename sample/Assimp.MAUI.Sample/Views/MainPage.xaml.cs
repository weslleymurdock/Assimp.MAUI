using Assimp.Maui;
using Assimp.MAUI.Sample.ViewModels;

namespace Assimp.MAUI.Sample.Views;

public partial class MainPage : ContentPage
{
 
    public MainPage(MainViewModel vm)
    {
        InitializeComponent();
        vm.SceneView = SceneView;
        BindingContext = vm;
    }

    private void OnStartInteraction(object? sender, TouchEventArgs e)
    {
        if (this.BindingContext is MainViewModel vm && vm is not null)
        {
            vm.OnStartInteraction(sender, e);
        }
    }

    private void OnDragInteraction(object? sender, TouchEventArgs e)
    {
        if (this.BindingContext is MainViewModel vm && vm is not null)
        {
            vm.OnDragInteraction(sender, e);
        }
    }

    private void OnEndInteraction(object? sender, TouchEventArgs e)
    {
        if (this.BindingContext is MainViewModel vm && vm is not null)
        {
            vm.OnEndInteraction(sender, e);
        }
    }

    protected override void OnDisappearing()
    {
        if (this.BindingContext is MainViewModel vm && vm is not null)
        {
            vm.Dispose();
        }
        base.OnDisappearing();
    }
}