# Copyright (c) Microsoft Corporation. All rights reserved.
#is Licensed under the MIT license.

function New-ServiceFabricNuGetPackage {
    <#
        .SYNOPSIS
            Package one or more Service Fabric services into a reusable NuGet package.
    
        .DESCRIPTION
            This function packages one or more Service Fabric services into a reusable NuGet package. Your customers will be able to include your services into their Service Fabric applications by simply adding a reference to your NuGet package. You can use this function against a folder of a Service Fabric service package, or a folder of a Service Fabric application package.
    
        .PARAMETER InputPath
            A folder of a Service Fabric service package or a Service Fabric application package.
    
        .PARAMETER OutPath
            The output path where the generated NuGet package is saved.
    
        .PARAMETER Publish
            To publish the NuGet package once built.
    
        .EXAMPLE
            New-ServiceFabricNuGetPackage /path/to/service/package /output/folder -publish
    
        .NOTES
            Revision History:
                10/09/2017 : Haishi Bai - Created.
    #>
    [cmdletbinding()]
    param(
        [parameter(mandatory=$true)][string] $InputPath,
        [parameter(mandatory=$true)][string] $OutPath,
        [parameter(mandatory=$false)][switch] $Publish=$false
    )

    $ErrorActionPreference = "stop"
    
    #chek if InputPath exists
    if (!(Test-Path $InputPath)) {
        Write-error "Input path is not found."
    }

    #create output folder if doesn't exists
    if (!(Test-Path $OutPath)) {
        New-Item -ItemType Directory $OutPath -Force | Out-Null
    }

    #create a temp folder and load files to it
    $WorkingFolder = New-TemporaryDirectory

    #copy files
    Robocopy $InputPath $WorkingFolder /S /NS /NC /NFL /NDL /NP /NJH /NJS    
    Robocopy "$(Get-ScriptDirectory)\tools" $WorkingFolder\tools /S /NS /NC /NFL /NDL /NP /NJH /NJS
    Copy-Item "$(Get-ScriptDirectory)\NuGet.exe" $WorkingFolder
    Copy-Item "$(Get-ScriptDirectory)\NuGet.config" $WorkingFolder
    
    if (Test-AppPackagePath $InputPath) {
        #This is an application package folder, package all services under the folder
        $folders = Get-ChildItem $WorkingFolder | ?{$_.PSIsContainer}
        $first = $true
        Foreach($folder in $folders) {
            $svcFolder = Join-Path $InputPath $folder
            if (Test-ServicePackagePath $svcFolder) {
                Update-ServicePackageFiles $svcFolder $svcFolder\ServiceManifest.xml $WorkingFolder\Package.nuspec $folder $first
                $first = $false
            }
        }
        New-ServicePackage $WorkingFolder $OutPath
    } elseif (Test-ServicePackagePath $InputPath) {
        #This is a service package folder, package the single service
        Update-ServicePackageFiles $WorkingFolder $InputPath\ServiceManifest.xml $WorkingFolder\Package.nuspec $null $true
        New-ServicePackage $WorkingFolder $OutPath
    }   else {
        Remove-TemporaryDirectory $WorkingFolder
        Write-Host "Please point to either a Service Application package folder or a Service package folder."
        $global:ExitCode = 1
    }
    
    if ($Publish -and $global:ExitCode -eq 0) {
        Publish-ServicePackage (Join-Path $OutPath (Get-ChildItem $OutPath *.nupkg | Select-Object -First 1).Name) $WorkingFolder
    }
    
    Remove-TemporaryDirectory $WorkingFolder
}

function  New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = (Join-Path $parent ("SFNuGet\" + [System.Guid]::NewGuid()))
    New-Item -ItemType Directory -Path $name | Out-Null
    return $name
}

function Remove-TemporaryDirectory{
    param(
        [string] $path
    )
    Remove-Item $path -Force -Recurse | Out-Null
} 

function Publish-ServicePackage {
    param(
        [string] $NuGetPackage,
        [string] $NuGetPath
    )

	Write-Log " "
	Write-Log "Publishing package..." -ForegroundColor Green

    $currentPath = Get-ScriptDirectory

    # Get nuget config
    if ($NuGetPath) {
        [xml]$nugetConfig = Get-Content $NuGetPath\NuGet.Config
    } else {
        [xml]$nugetConfig = Get-Content $currentPath\NuGet.Config
    }
	
	$nugetConfig.configuration.packageSources.add | ForEach-Object {
		$url = $_.value

		Write-Log "Repository Url: $url"
		Write-Log " "

        # Try to push package
        if ($NuGetPath) {
            $task = New-ProcessStartInfo $NuGetPath\NuGet.exe ("push " + $NuGetPackage + " -Source " + $url)
        } else {
            $task = New-ProcessStartInfo $currentPath\NuGet.exe ("push " + $NuGetPackage + " -Source " + $url)
        }
		$task.Start() | Out-Null
		$task.WaitForExit()
			
		$output = ($task.StandardOutput.ReadToEnd() -Split '[\r\n]') |? { $_ }
		$error = ($task.StandardError.ReadToEnd() -Split '[\r\n]') |? { $_ }
		Write-Log $output
		Write-Log $error Error
		   
		if ($task.ExitCode -gt 0) {
			Resolve-PublishError -ErrorMessage $error
		}
		else {
			$global:ExitCode = 0
		}                
	}
}

function Get-ScriptDirectory
{
    Split-Path $script:MyInvocation.MyCommand.Path
}

function Resolve-PublishError {
	param (
        [string] $ErrorMessage
    )

	# Run NuGet Setup
	$encodedMessage = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ErrorMessage))
	$setupTask = Start-Process PowerShell.exe "-ExecutionPolicy Unrestricted -File .\NuGetSetup.ps1 -Url $url -Base64EncodedMessage $encodedMessage" -Wait -PassThru

	if ($setupTask.ExitCode -eq 0) {
		# Try to push package again
		$publishTask = Start-Process .\NuGet.exe ("push " + $_.Name + " -Source " + $url)
		$publishTask.Start() | Out-Null
		$publishTask.WaitForExit()
			
		$output = ($publishTask.StandardOutput.ReadToEnd() -Split '[\r\n]') |? {$_}
		$error = (($publishTask.StandardError.ReadToEnd() -Split '[\r\n]') |? {$_}) 
		Write-Log $output
		Write-Log $error Error

		if ($publishTask.ExitCode -eq 0) {
			$global:ExitCode = 0
		}
	}
	elseif ($setupTask.ExitCode -eq 2) {
		$global:ExitCode = 2
	}
	else {
		$global:ExitCode = 0
	}
}

function Update-ServicePackageFiles {
    param (
        [string]$path, 
        [string]$svcManifestFile, 
        [string]$specFile, 
        [string]$svcFolder, 
        [bool]$first
    ) 

    $manifest = [xml](Get-Content $svcManifestFile)
    $name = $manifest.DocumentElement.Attributes["Name"].Value
    if ($name.EndsWith("Pkg")) {$name = $name.Substring(0, $name.Length-3)}
    if ($first) {
        $executable = ($manifest.ServiceManifest.CodePackage.EntryPoint.ExeHost)
        if ($executable) {            
            $execFile = Get-ChildItem ([IO.Path]::Combine($path,$manifest.ServiceManifest.CodePackage.Name,$executable.Program))
            Write-Host $execFile
            Update-SpecFile .\Package.xml $svcManifestFile $execFile $specFile $svcFolder
        } else {
            Update-SpecFileForContainer .\Package.xml $svcManifestFile $specFile $svcFolder
        }
    }
    $specXml = [xml](Get-Content $specFile)
    
    Add-FileElement $specXml (&{If($svcFolder) {"$svcFolder\Code\**\*.*"} Else {"Code\**\*.*"}}) ($name + "Pkg\Code")
    Add-FileElement $specXml (&{If($svcFolder) {"$svcFolder\Config\**\*.*"} Else {"Config\**\*.*"}}) ($name + "Pkg\Config")
    Add-FileElement $specXml (&{If($svcFolder) {"$svcFolder\ServiceManifest.xml"} Else {".\ServiceManifest.xml"}}) ($name + "Pkg\ServiceManifest.xml")    
    
    $overridePath = [IO.Path]::Combine($path, $svcFolder, "ApplicationManifest.overrides.xml")
    if ([IO.File]::Exists($overridePath)) {
        Add-FileElement $specXml (&{If($svcFolder) {"$svcFolder\ApplicationManifest.overrides.xml"} Else {".\ApplicationManifest.overrides.xml"}}) ($name + "Pkg\ApplicationManifest.overrides.xml")        
    }

    $specXml.Save($specFile)
}

function Publish-ServiceFabricNuGetPackage {
    <#
        .SYNOPSIS
            Public Service Fabric NuGet package to a NuGet source.
    
        .DESCRIPTION
            This function publishes you Servcie Fabric NuGet package to a NuGet source, using configurations specified in the config file.
    
        .PARAMETER NuGetPackage
            The path to your NuGet package.
    
        .PARAMETER NuGetConfig
            The path to NuGet path that contains NuGet.exe and NuGet.config.
    
        .EXAMPLE
            Publish-ServiceFabricNuGetPackage /path/to/service/package /path/to/NuGet
    
        .NOTES
            Revision History:
                10/09/2017 : Haishi Bai - Created.
    #>
    param(
        [string] $NuGetPackage,
        [string] $NuGetConfig
    )

    Publish-ServicePackage $NuGetPackage $NuGetConfig
}

function Start-Process {
	param (
        [string] $fileName, 
        [string] $arguments
    )

	$pinfo = New-Object System.Diagnostics.ProcessStartInfo
	$pinfo.RedirectStandardError = $true
	$pinfo.RedirectStandardOutput = $true
	$pinfo.UseShellExecute = $false
	$pinfo.FileName = $fileName
	$pinfo.Arguments = $arguments

	$p = New-Object System.Diagnostics.Process
	$p.StartInfo = $pinfo
    
	return $p
}


function Update-SpecFileForContainer {
    param (
        [string]$specFile, 
        [string]$srvManifest, 
        [string] $targetSpecFile, 
        [string]$svcFolder
    )

    $manifest = [xml](Get-Content $srvManifest)
    $name = $manifest.DocumentElement.Attributes["Name"].Value
	if ($name.EndsWith("Pkg")) {$name = $name.Substring(0, $name.Length-3)}
    $version = $manifest.DocumentElement.Attributes["Version"].Value

    $container = ($manifest.ServiceManifest.CodePackage.EntryPoint.ContainerHost)
    if ($container) {
        $contentXml = [xml] (Get-Content $specFile)
        Update-String $contentXml "`$serviceName" $name        
        Update-String $contentXml "`$serviceNamePkg" $name + "Pkg"
        Update-String $contentXml "`$serviceVersion" $version
        Update-String $contentXml "`$assemblyTitle" (&{If($container.ImageName) {$container.ImageName} Else {"Container"}})
        Update-String $contentXml "`$assemblyCompany" "Company"        
        Update-String $contentXml "`$assemblyDescription" "Unknown"
        Update-String $contentXml "`$copyRight" "Unknown"	        
        $contentXml.Save($targetSpecFile)
    }    
}

function Add-FileElement {
    param (
        [xml]$xmlDoc,
        [string]$src,
        [string]$target
    )

    $element = $xmlDoc.CreateElement("file")
    Add-Attribute $xmlDoc $element "src" $src
    Add-Attribute $xmlDoc $element "target" $target
    $xmlDoc.package.files.AppendChild($element)
}

function Add-Attribute {
    param (
        $xml, 
        $element, 
        [string]$name, 
        [string]$value
    )

    $attribute = $xml.CreateAttribute($name)
    $attribute.Value = $value
    $element.Attributes.Append($attribute)
}

function Update-String {
    param (
        [xml]$xmlDoc, 
        [string]$searchPattern, 
        [string]$newString
    )
    
    $nodes = $xmlDoc | Select-Xml -Xpath "//*/text()[contains(.,'$searchpattern')]" | Select-Object -Exp Node
    Foreach($node in $nodes) {     
        $node.ParentNode.'#text' = $node.ParentNode.'#text'.Replace($searchPattern, $newString)
    }
    $nodes = $xmlDoc | Select-Xml -Xpath "//*/@*[contains(.,'`$serviceNamePkg')]" | Select-Object -Exp Node
    Foreach($node in $nodes) {     
        $node.Value = $node.Value.Replace($searchPattern, $newString)
    }
}
function Update-SpecFile{
    param (
        [string]$specFile, 
        [string]$srvManifest, 
        $executable, 
        [string] $targetSpecFile, 
        [string]$svcFolder
    )

	$manifest = [xml](Get-Content $srvManifest)
	$name = $manifest.DocumentElement.Attributes["Name"].Value
	if ($name.EndsWith("Pkg")){$name = $name.Substring(0, $name.Length-3)}
    $version = $manifest.DocumentElement.Attributes["Version"].Value
    
    $contentXml = [xml] (Get-Content $specFile)
    
    $isValidAssembly = $TRUE

    Try {
        $assembly = [System.Reflection.Assembly]::LoadFrom($executable)
    }
    Catch {
        Write-Log ("Failed to load service code as a assembly.")
        $isValidAssembly = $FALSE
    }

    Update-String $contentXml "`$serviceName" $name
    Update-String $contentXml "`$serviceNamePkg" $name + "Pkg"
    Update-String $contentXml "`$serviceVersion" $version

    $company = "Company"

    if ($isValidAssembly) {
        Update-String $contentXml "`$assemblyTitle" $assembly.GetCustomAttributes([System.Reflection.AssemblyTitleAttribute], $false).Title
        $company = $assembly.GetCustomAttributes([System.Reflection.AssemblyCompanyAttribute], $false).Company
    }
    
    Update-String $contentXml "`$assemblyCompany" (&{If($company) {$company} Else {"Company"}})
    
    $description = "Description"

    if ($isValidAssembly) {
        Update-String $contentXml "`$copyRight" $assembly.GetCustomAttributes([System.Reflection.AssemblyCopyrightAttribute], $false).Copyright	
        $description = $assembly.GetCustomAttributes([System.Reflection.AssemblyDescriptionAttribute], $false).Description    
    }
	Update-String $contentXml "`$assemblyDescription" (&{If($description) {$description} Else {"Description"}})    

    $contentXml.Save($targetSpecFile)
}
function Test-ServicePackagePath {
    param (
        [string] $path
    )
        
    return Test-Path (Join-Path $path "ServiceManifest.xml")   
}

function Test-AppPackagePath {
    param (
        [string] $path
    )

    return Test-Path (Join-Path $path "ApplicationManifest.xml")
}
function New-ServicePackage {    
    param (
        [string] $workingPath,
        [string] $outputPath
    )

    #make nuget.exe writable
    Set-ItemProperty "$workingPath\NuGet.exe" -Name IsReadOnly -Value $false

    #create nupkg file backup
    if (Test-Path *.nupkg) {
        Set-ItemProperty *.nupkg -Name IsReadOnly -Value $false
    
        Write-Log " "
        Write-Log "Creating backup..." -ForegroundColor Green
    
        Get-ChildItem *.nupkg | ForEach-Object { 
            Move-Item $_.Name ($_.Name + ".bak") -Force
            Write-Log ("Renamed " + $_.Name + " to " + $_.Name + ".bak")
        }
    }

    Write-Log " "
    Write-Log "Updating NuGet..." -ForegroundColor Green
    Write-Log (Invoke-Command {"$workingPath\NuGet.exe update -Self"} -ErrorAction Stop) 

    Write-Log " "
    Write-Log "Creating package..." -ForegroundColor Green
    
    # Create symbols package if any .pdb files are located in the lib folder
    If ((Get-ChildItem *.pdb -Path .\lib -Recurse).Count -gt 0) {
	    $packageTask = New-ProcessStartInfo $workingPath\NuGet.exe ("pack $workingPath\Package.nuspec -Symbol -Verbosity Detailed -OutputDirectory $outputPath")
        Start-ProcessWaitForMessage -process $packageTask -message "Successfully created package"
        $global:ExitCode = $packageTask.ExitCode
    }
    Else {
	    $packageTask = New-ProcessStartInfo $workingPath\NuGet.exe ("pack $workingPath\Package.nuspec -Verbosity Detailed -OutputDirectory $outputPath")
	    Start-ProcessWaitForMessage -process $packageTask -message "Successfully created package"
        $global:ExitCode = $packageTask.ExitCode
    }    
}

function New-ProcessStartInfo {
    param (
        [string] $fileName, 
        [string] $arguments
    )

	$pinfo = New-Object System.Diagnostics.ProcessStartInfo
	$pinfo.RedirectStandardError = $true
	$pinfo.RedirectStandardOutput = $true
	$pinfo.UseShellExecute = $false
	$pinfo.FileName = $fileName
	$pinfo.Arguments = $arguments

	$p = New-Object System.Diagnostics.Process
	$p.StartInfo = $pinfo

	return $p
}

function Start-ProcessWaitForMessage {
    param (
        $process, 
        [string] $message
    )
    
    $global:message = $message
    $global:process = $process

    $OutEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
        $data = $Event.SourceEventArgs.Data
		Write-Log $data
        if ($data.Contains($global:message)) {
            $global:process.Kill()
        }
    }

	$ErrEvent = Register-ObjectEvent -InputObject $Process -EventName ErrorDataReceived -Action {
		Write-Log $Event.SourceEventArgs.Data Error
	}


    $process.Start()
    $process.BeginOutputReadLine()
	$Process.BeginErrorReadLine()

    do
    {
        Write-Host "Waiting for message '$message'" -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    while (!$process.HasExited)

    $OutEvent.Name,  $ErrEvent.Name | ForEach-Object {Unregister-Event -SourceIdentifier $_}
}

function Write-Log {
    
        #region Parameters
        
            [cmdletbinding()]
            Param(
                [Parameter(ValueFromPipeline=$true)]
                [array] $Messages,
    
                [Parameter()] [ValidateSet("Error", "Warn", "Info")]
                [string] $Level = "Info",
                
                [Parameter()]
                [Switch] $NoConsoleOut = $false,
                
                [Parameter()]
                [String] $ForegroundColor = 'White',
                
                [Parameter()] [ValidateRange(1,30)]
                [Int16] $Indent = 0,
    
                [Parameter()]
                [IO.FileInfo] $Path = ".\NuGet.log",
                
                [Parameter()]
                [Switch] $Clobber,
                
                [Parameter()]
                [String] $EventLogName,
                
                [Parameter()]
                [String] $EventSource,
                
                [Parameter()]
                [Int32] $EventID = 1
                
            )
            
        #endregion
    
        Begin {}
    
        Process {
            
            $ErrorActionPreference = "Continue"
    
            if ($Messages.Length -gt 0) {
                try {			
                    foreach($m in $Messages) {			
                        if ($NoConsoleOut -eq $false) {
                            switch ($Level) {
                                'Error' { 
                                    Write-Error $m -ErrorAction SilentlyContinue
                                    Write-Host ('{0}{1}' -f (" " * $Indent), $m) -ForegroundColor Red
                                }
                                'Warn' { 
                                    Write-Warning $m 
                                }
                                'Info' { 
                                    Write-Host ('{0}{1}' -f (" " * $Indent), $m) -ForegroundColor $ForegroundColor
                                }
                            }
                        }
    
                        if ($m.Trim().Length -gt 0) {
                            $msg = '{0}{1} [{2}] : {3}' -f (" " * $Indent), (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level.ToUpper(), $m
        
                            if ($Clobber) {
                                $msg | Out-File -FilePath $Path -Force
                            } else {
                                $msg | Out-File -FilePath $Path -Append
                            }
                        }
                
                        if ($EventLogName) {
                
                            if (-not $EventSource) {
                                $EventSource = ([IO.FileInfo] $MyInvocation.ScriptName).Name
                            }
                
                            if(-not [Diagnostics.EventLog]::SourceExists($EventSource)) { 
                                [Diagnostics.EventLog]::CreateEventSource($EventSource, $EventLogName) 
                            } 
    
                            $log = New-Object System.Diagnostics.EventLog  
                            $log.set_log($EventLogName)  
                            $log.set_source($EventSource) 
                    
                            switch ($Level) {
                                "Error" { $log.WriteEntry($Message, 'Error', $EventID) }
                                "Warn"  { $log.WriteEntry($Message, 'Warning', $EventID) }
                                "Info"  { $log.WriteEntry($Message, 'Information', $EventID) }
                            }
                        }
                    }
                } 
                catch {
                    throw "Failed to create log entry in: '$Path'. The error was: '$_'."
                }
            }
        }
    
        End {}
    
        <#
            .SYNOPSIS
                Writes logging information to screen and log file simultaneously.
    
            .DESCRIPTION
                Writes logging information to screen and log file simultaneously. Supports multiple log levels.
    
            .PARAMETER Messages
                The messages to be logged.
    
            .PARAMETER Level
                The type of message to be logged.
                
            .PARAMETER NoConsoleOut
                Specifies to not display the message to the console.
                
            .PARAMETER ConsoleForeground
                Specifies what color the text should be be displayed on the console. Ignored when switch 'NoConsoleOut' is specified.
            
            .PARAMETER Indent
                The number of spaces to indent the line in the log file.
    
            .PARAMETER Path
                The log file path.
            
            .PARAMETER Clobber
                Existing log file is deleted when this is specified.
            
            .PARAMETER EventLogName
                The name of the system event log, e.g. 'Application'.
            
            .PARAMETER EventSource
                The name to appear as the source attribute for the system event log entry. This is ignored unless 'EventLogName' is specified.
            
            .PARAMETER EventID
                The ID to appear as the event ID attribute for the system event log entry. This is ignored unless 'EventLogName' is specified.
    
            .EXAMPLE
                PS C:\> Write-Log -Message "It's all good!" -Path C:\MyLog.log -Clobber -EventLogName 'Application'
    
            .EXAMPLE
                PS C:\> Write-Log -Message "Oops, not so good!" -Level Error -EventID 3 -Indent 2 -EventLogName 'Application' -EventSource "My Script"
    
            .INPUTS
                System.String
    
            .OUTPUTS
                No output.
                
            .NOTES
                Revision History:
                    2011-03-10 : Andy Arismendi - Created.
        #>
    }

Export-ModuleMember -function New-ServiceFabricNuGetPackage, Publish-ServiceFabricNuGetPackage