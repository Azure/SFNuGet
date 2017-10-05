@{
    ModuleVersion = '1.0'
    Author = 'Microsoft'
    RootModule = 'SFNuGetModule.psm1'
    FunctionsToExport =@('New-ServiceFabricNuGetPackage', 'Publish-ServiceFabricNuGetPackage')
    FileList = @('NuGet.exe', 'NuGet.config')
}