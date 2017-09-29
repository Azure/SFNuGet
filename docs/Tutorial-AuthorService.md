# Tutorial: Create and reuse a Service Fabric NuGet package

This tutorial walks you through the steps of creating and sharing a stateless Service Fabric service.

## Create the Service

1. Launch Visual Studio 2015/2017.
2. Create a new **Service Fabric Application** with a new **Stateless Service** named **MyCoolService**.
3. Build the solution.
4. Package your Service Fabric application by right-clicking on the application project and selecting the **Package** menu.

## Create the NuGet package

1. Launch PowerShell.
2. Create a serice NuGet package (writing to *d:\temp* folder):
```powershell
New-ServiceFabricNuGetPackage -InputPath <path to your Service Fabric application>\pkg\Debug\MyCoolServicePkg d:\temp
```
3. Now, you can find the **MyCoolService.1.0.0.nupkg** package under the *d:\temp* folder.

The NuGet package is now ready to be published and shared with your customers.

## Use the NuGet package

To simulate the experience of your service users, you’ll create a new Service Fabric application and add the above NuGet package to the new application.

1. Create a new **Service Fabric Application** with a new **Stateless Service** named **TempService**.

> **Note** The *TempService* service isn't needed. Service Fabric tooling doesn't allow creating an empty application, so we need to add a dummy service. You can remove the service after you've created the application.

2. In **Solution Explorer**, right-click on the solution node and select the **Manage Nuget Packages for Solution** menu.
3. Browse to the **MyCoolService** package. Check the *application* project, and then click on the **Install** button, as shown in the following figure:
![Manage NuGet packages](imgs\use-nuget.png)

4. Now your application is configured with the **MyCoolService** service! Simply publish your application.

Once the application is deployed, you can observe how **MyCoolService** has been deployed along your own services:
![SF Explorer](imgs\sf-explorer.png)