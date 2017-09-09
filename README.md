# What's SFNuGet?

SFNuGet allows you to package and share your Microsoft Azure Service Fabric services as NuGet packages. Once your service is packaged as a NuGet package, your customers can include your service into their Service Fabric applications by simply adding a reference to your service’s NuGet package.

To package your Service Fabric service as a reusable NuGet package, add a reference to SFNuGet and rebuild your solution - that's all you need to do! 

# Getting Started
SFNuGet is a NuGet package that helps you to build NuGet packages. The source code in this repository builds the SFNuGet NuGet package itself. To author a Service Fabric package, you need to add a SFNuGet reference to your Service Fabric application. The final consumer of your service package doesn't need a SFNuGet reference.

## Build SFNuGet
1. Clone the repository
2. Open **ReusableSFServices.sln** and rebuild the solution. 
3. You'll find the newly built **SFNuGet._\<version\>_.nupkg** under the **SFNuGet** folder.

## Tutorials

* [Create a Service Fabric NuGet package](docs\Tutorial-AuthorService.md)
* [Consume a Service Fabric NuGet package]


# Updates

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
