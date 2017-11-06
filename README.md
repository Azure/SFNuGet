# What's SFNuGet?

SFNuGet allows you to package and share your Microsoft Azure Service Fabric services as NuGet packages. Once your service is packaged as a NuGet package, your customers can include your service into their Service Fabric applications by simply adding a reference to your service’s NuGet package.

To package your Service Fabric service as a reusable NuGet package, use the **New-ServiceFabricNuGetPackage** method in this module.

> **NOTE** Previous versions of SFNuGet were packaged as NuGet packages, which are obsolete now.


# Getting Started
SFNuGet is a PowerShell module that helps you to build NuGet packages. After importing the module, you can use SFNuGet to package and publish NuGet packages for your Microsoft Azure Service Fabric services.

## Import SFNuGet Module
1. Clone the repository
2. Open PowerShell. 
3. Import the SFNuGet module:
```powershell
Import-Module /path/to/SFNuGetModule.psd1
```
## Package a Service Fabric as a NuGet package
To package a Service Fabric service, use the **New-ServiceFabricNuGetPackage** method on your service package folder. This folder usually is under the pkg\\Debug\\&lt;service name&gt;Pkg folder after your package your Service Fabric application.
```powershell
New-ServiceFabricNuGetPackage -InputPath <path to your Service Fabric package folder> <path to output folder>
```


## Tutorials

* [Create and reuse a Service Fabric NuGet package](docs/Tutorial-AuthorService.md)
* [Publish a Service Fabric NuGet package](docs/Tutorial-PublishService.md)

## Customize you NuGet packages
The PowerShell module uses a **Package.xml** file as the template to generate NuGet package specification. When it builds your NuGet packages, it automatically reads service metadata and assembly metadata to replace placeholders (marked with '$' sign) in this file, such as $serviceName and $assemblyCompany. If you prefer, you can update this file to use customized information instead of auto-detected information. Especially, you probably want to update the **licenseUrl** to match with your licensing model.

# Updates

## September 29, 2017

* SFNuGet NuGet package is now obsolete. SFNuGet will be delivered as a PowerShell module going forward.

## September 18, 2017

*  Updated for Visual Studio 2017 and Service Fabric SDK 2.6.220.9494.

# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
