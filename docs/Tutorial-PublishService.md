# Tutorial: Publish a Service Fabric NuGet package

This tutorial walks you through the steps of publishing a Service Fabric NuGet package.

## Modify you NuGet.config file

When you publish your NuGet package, the **NuGet.config** file under the script's folder is used. You can optionally specify a **NuGetPath** parameter that points to a folder that contains both NuGet.exe and NuGet.config. The default config file doesn't have NuGet API keys. In order to publish, you need to enter your API keys into the config file.

1. Sign in to your nuget.org account.
2. Click on your name at upper-right corner and select **API Keys**.
3. Create a new API key, or copy an existing API key.
4. Use the following command to set the API key into NuGet.config in encrypted format:
```powershell
.\nuget.exe setApiKey <your api key> -Source https://www.nuget.org -ConfigFile <your NuGet.config file>
```

## Publish the NuGet package

1. Launch PowerShell.
2. Use the following command to publish your package:
```powershell
Publish-ServiceFabricNuGetPackage <path to your NuGet Package>
```
3.  If you want to use **NuGet.config** from a different folder other than the script folder, use command:
```powershell
Publish-ServiceFabricNuGetPackage <path to your NuGet Package> <path to NuGet.exe and NuGet.config>
```

> **Note** New-ServiceFabricNuGetPackage supports publishing the NuGet package directly. Simply Add a **-Publish** switch
```powershell
New-ServiceFabricNuGetPackage -InputPath <path to your Service Fabric application>\pkg\Debug\MyCoolServicePkg d:\temp -Publish
```
