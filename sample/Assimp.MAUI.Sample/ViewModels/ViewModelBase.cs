using CommunityToolkit.Mvvm.ComponentModel;

namespace Assimp.MAUI.Sample.ViewModels;

public partial class ViewModelBase : ObservableObject
{
    [ObservableProperty] public partial bool IsBusy { get; set; } = false;
    [ObservableProperty] public partial string Title { get; set; } = string.Empty;
}
