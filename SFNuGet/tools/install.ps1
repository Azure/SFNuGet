# Copyright (c) Microsoft Corporation.  All rights reserved.

# Runs every time a package is installed in a project

param($installPath, $toolsPath, $package, $project)

# $installPath is the path to the folder where the package is installed.
# $toolsPath is the path to the tools directory in the folder where the package is installed.
# $package is a reference to the package object.
# $project is a reference to the project the package was installed to.

function getProjectDirectory($project)
{
	$projectFullName = $project.FullName
	$fileInfo = new-object -typename System.IO.FileInfo -ArgumentList $projectFullName
	return $fileInfo.DirectoryName
}

function listProjectItems($items, [int]$level)
{
	Foreach($item in $items)
	{
		Write-Host "Item " $item.Name "[" $level "]"
		if ($item.ProjectItems)
		{
			listProjectItems $item.ProjectItems ($level + 1)
		}
	}
}

function updateSpecFile([string]$specFile, [string]$srvManifest, $project)
{
	$manifest = [xml](Get-Content $srvManifest)
	$name = $manifest.DocumentElement.Attributes["Name"].Value
	if ($name.EndsWith("Pkg")){$name = $name.Substring(0, $name.Length-3)}
	$version = $manifest.DocumentElement.Attributes["Version"].Value
	$content = Get-Content($specFile)
	$content = $content.Replace("`$serviceName",$name)
	$content = $content.Replace("`$serviceVersion",$version)
	$content = $content.Replace("`$assemblyTitle",(&{If($project.Properties["Title"].Value) {$project.Properties["Title"].Value} Else {"Title"}}))
	$content = $content.Replace("`$assemblyCompany",(&{If($project.Properties["Company"].Value) {$project.Properties["Company"].Value} Else {"Company"}}))
	$content = $content.Replace("`$assemblyDescription",(&{If($project.Properties["Description"].Value) {$project.Properties["Description"].Value} Else {"Description"}}))
	$content = $content.Replace("`$copyRight",(&{If($project.Properties["Copyright"].Value) {$project.Properties["Copyright"].Value} Else {"Copyright"}}))
	#Foreach($prop in $project.Properties)
	#{
	#	Write-Host "Property " $prop.Name "=" $prop.Value
	#}
	#listProjectItems $project.ProjectItems 0
	$content | Out-File $specFile
}
function moveProjectFile($srcCollection, $srcName, $srcFile, $destFile)
{
	Move-Item $srcFile $destFile -Force
	$project.ProjectItems.AddFromFile($destFile)
	$project.ProjectItems.Item($srcCollection).ProjectItems.Item($srcName).Delete()
}

$projectDirectory = getProjectDirectory($project)

$srcSpecFile = "$projectDirectory\content\Package.xml"
$srvManifest = "$projectDirectory\PackageRoot\ServiceManifest.xml"

updateSpecFile $srcSpecFile $srvManifest $project

$destSpecFile = "$projectDirectory\Package.nuspec"

moveProjectFile "content" "Package.xml" $srcSpecFile $destSpecFile

$project.Save()


