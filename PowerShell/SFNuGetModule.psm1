# Copyright (c) Microsoft Corporation. All rights reserved.
#is Licensed under the MIT license.

function New-ServiceFabricNuGetPackage {
    param(
        [string] $InputPath,
        [string] $OutPath,
        [switch] $Publish=$false
    )
    
    #chek if path exists
    if (!$InputPath -Or !(Test-Path $InputPath)) {
        Write-Host "Input path is null or not found."
        Exit 1
    }
    
    #check if output parameter is null
    if (!$OutPath) {
        Write-Host "Output path is null."
        Exit 1
    }

    #create or clean output folder
    if (!(Test-Path $OutPath)) {
        New-Item -ItemType Directory $OutPath -Force | Out-Null
    } else {
        Remove-Item $OutPath -Recurse
    }

    #copy files
    Robocopy $InputPath $OutPath /S /NS /NC /NFL /NDL /NP /NJH /NJS    
    Robocopy .\tools $OutPath\tools /S /NS /NC /NFL /NDL /NP /NJH /NJS
    Copy-Item .\NuGet.exe $OutPath
    Copy-Item .\NuGet.config $OutPath

    if (isAppPackagePath $InputPath) {
        $folders = Get-ChildItem $OutPath | ?{$_.PSIsContainer}
        $first = $true
        Foreach($folder in $folders) {
            $svcFolder = Join-Path $InputPath $folder
            if (isServicePackagePath $svcFolder) {
                updateSpecFieForService $svcFolder $svcFolder\ServiceManifest.xml $OutPath\Package.nuspec $folder $first
                $first = $false
            }
        }
        packageService $OutPath
    } elseif (isServicePackagePath $InputPath) {
        updateSpecFieForService $OutPath $InputPath\ServiceManifest.xml $OutPath\Package.nuspec $null $true
        packageService $OutPath
    }   else {
        Write-Host "Please point to either a Service Application package folder or a Service package folder."
        $global:ExitCode = 1
    }
    if ($Publish -and $global:ExitCode -eq 0) {
        publish $OutPath
    }
}

function publish {
    param([string] $outputPath)

	Write-Log " "
	Write-Log "Publishing package..." -ForegroundColor Green

	# Get nuget config
	[xml]$nugetConfig = Get-Content $outputPath\NuGet.Config
	
	$nugetConfig.configuration.packageSources.add | ForEach-Object {
		$url = $_.value

		Write-Log "Repository Url: $url"
		Write-Log " "

		Get-ChildItem $outputPath *.nupkg | Where-Object { $_.Name.EndsWith(".symbols.nupkg") -eq $false } | ForEach-Object { 

			# Try to push package
			$task = Create-Process $outputPath\NuGet.exe ("push " + $outputPath + "\" + $_.Name + " -Source " + $url)
			$task.Start() | Out-Null
			$task.WaitForExit()
			
			$output = ($task.StandardOutput.ReadToEnd() -Split '[\r\n]') |? { $_ }
			$error = ($task.StandardError.ReadToEnd() -Split '[\r\n]') |? { $_ }
			Write-Log $output
			Write-Log $error Error
		   
			if ($task.ExitCode -gt 0) {
				handlePublishError -ErrorMessage $error
				#Write-Log ("HandlePublishError() Exit Code: " + $global:ExitCode)
			}
			else {
				$global:ExitCode = 0
			}                
		}
	}
}

function handlePublishError {
	param([string] $ErrorMessage)

	# Run NuGet Setup
	$encodedMessage = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ErrorMessage))
	$setupTask = Start-Process PowerShell.exe "-ExecutionPolicy Unrestricted -File .\NuGetSetup.ps1 -Url $url -Base64EncodedMessage $encodedMessage" -Wait -PassThru

	#Write-Log ("NuGet Setup Task Exit Code: " + $setupTask.ExitCode)

	if ($setupTask.ExitCode -eq 0) {
		# Try to push package again
		$publishTask = Create-Process .\NuGet.exe ("push " + $_.Name + " -Source " + $url)
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

function updateSpecFieForService ([string]$path, [string]$svcManifestFile, [string]$specFile, [string]$svcFolder, [bool]$first) { 
    $manifest = [xml](Get-Content $svcManifestFile)
    $name = $manifest.DocumentElement.Attributes["Name"].Value
    if ($name.EndsWith("Pkg")) {$name = $name.Substring(0, $name.Length-3)}
    
    if ($first) {
        if (Test-Path $path\Code) {
            $execFile = Get-ChildItem $path\Code *.exe | Select-Object -First 1
            updateSpecFile .\Package.xml $svcManifestFile $path\Code\$execFile $specFile $svcFolder
        } else {
            updateSpecFileForContainer .\Package.xml $svcManifestFile $specFile $svcFolder
        }
    }
    $specXml = [xml](Get-Content $specFile)
    
    appendFileElement $specXml (&{If($svcFolder) {"$svcFolder\Code\**\*.*"} Else {"Code\**\*.*"}}) ($name + "Pkg\Code")
    appendFileElement $specXml (&{If($svcFolder) {"$svcFolder\Config\**\*.*"} Else {"Config\**\*.*"}}) ($name + "Pkg\Config")
    appendFileElement $specXml (&{If($svcFolder) {"$svcFolder\ServiceManifest.xml"} Else {".\ServiceManifest.xml"}}) ($name + "Pkg\ServiceManifest.xml")    

    $specXml.Save($specFile)
}

function Publish-ServiceFabricNuGetPackage {
    param(
        [string] $OutPath
    )
    publish $OutPath
}

function Create-Process() {
	param([string] $fileName, [string] $arguments)

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


function updateSpecFileForContainer([string]$specFile, [string]$srvManifest, [string] $targetSpecFile, [string]$svcFolder)
{
    $manifest = [xml](Get-Content $srvManifest)
    $name = $manifest.DocumentElement.Attributes["Name"].Value
	if ($name.EndsWith("Pkg")) {$name = $name.Substring(0, $name.Length-3)}
    $version = $manifest.DocumentElement.Attributes["Version"].Value

    $container = ($manifest.ServiceManifest.CodePackage.EntryPoint.ContainerHost)
    if ($container){
        $contentXml = [xml] (Get-Content $specFile)
        replaceString $contentXml "`$serviceName" $name        
        replaceString $contentXml "`$serviceNamePkg" $name + "Pkg"
        replaceString $contentXml "`$serviceVersion" $version
        replaceString $contentXml "`$assemblyTitle" (&{If($container.ImageName) {$container.ImageName} Else {"Container"}})
        replaceString $contentXml "`$assemblyCompany" "Company"        
        replaceString $contentXml "`$assemblyDescription" "Unknown"
        replaceString $contentXml "`$copyRight" "Unknown"	
        #$codeNode = $contentXml | Select-Xml -Xpath "//files/file[@src='Code\**\*.*']" | Select-Object -Exp Node
        #$codeNode.ParentNode.RemoveChild($codeNode)
        $contentXml.Save($targetSpecFile)
    }    
}

function appendFileElement([xml]$xmlDoc,[string]$src,[string]$target) {
    $element = $xmlDoc.CreateElement("file")
    appendAttribute $xmlDoc $element "src" $src
    appendAttribute $xmlDoc $element "target" $target
    $xmlDoc.package.files.AppendChild($element)
}

function appendAttribute($xml, $element, [string]$name, [string]$value) {
    $attribute = $xml.CreateAttribute($name)
    $attribute.Value = $value
    $element.Attributes.Append($attribute)
}

function replaceString([xml]$xmlDoc, [string]$searchPattern, [string]$newString) {
    $nodes = $xmlDoc | Select-Xml -Xpath "//*/text()[contains(.,'$searchpattern')]" | Select-Object -Exp Node
    Foreach($node in $nodes) {     
        $node.ParentNode.'#text' = $node.ParentNode.'#text'.Replace($searchPattern, $newString)
    }
    $nodes = $xmlDoc | Select-Xml -Xpath "//*/@*[contains(.,'`$serviceNamePkg')]" | Select-Object -Exp Node
    Foreach($node in $nodes) {     
        $node.Value = $node.Value.Replace($searchPattern, $newString)
    }
}
function updateSpecFile([string]$specFile, [string]$srvManifest, $executable, [string] $targetSpecFile, [string]$svcFolder)
{
	$manifest = [xml](Get-Content $srvManifest)
	$name = $manifest.DocumentElement.Attributes["Name"].Value
	if ($name.EndsWith("Pkg")){$name = $name.Substring(0, $name.Length-3)}
    $version = $manifest.DocumentElement.Attributes["Version"].Value
    $assembly = [System.Reflection.Assembly]::LoadFrom($executable)

    $contentXml = [xml] (Get-Content $specFile)
	
    replaceString $contentXml "`$serviceName" $name
    replaceString $contentXml "`$serviceNamePkg" $name + "Pkg"
	replaceString $contentXml "`$serviceVersion" $version
    replaceString $contentXml "`$assemblyTitle" $assembly.GetCustomAttributes([System.Reflection.AssemblyTitleAttribute], $false).Title
    
    $company = $assembly.GetCustomAttributes([System.Reflection.AssemblyCompanyAttribute], $false).Company
    replaceString $contentXml "`$assemblyCompany" (&{If($company) {$company} Else {"Company"}})
    
    $description = $assembly.GetCustomAttributes([System.Reflection.AssemblyDescriptionAttribute], $false).Description    
	replaceString $contentXml "`$assemblyDescription" (&{If($description) {$description} Else {"Description"}})
    replaceString $contentXml "`$copyRight" $assembly.GetCustomAttributes([System.Reflection.AssemblyCopyrightAttribute], $false).Copyright	

	$contentXml.Save($targetSpecFile)
}
function isServicePackagePath([string] $path)
{    
    return Test-Path (Join-Path $path "ServiceManifest.xml")   
}

function isAppPackagePath([string] $path)
{
    return Test-Path (Join-Path $path "ApplicationManifest.xml")
}
function packageService([string] $path)
{    
    #make nuget.exe writable
    Set-ItemProperty NuGet.exe -Name IsReadOnly -Value $false

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
    Write-Log (Invoke-Command {"$path\NuGet.exe update -Self"} -ErrorAction Stop)

    Write-Log " "
    Write-Log "Creating package..." -ForegroundColor Green
    
    # Create symbols package if any .pdb files are located in the lib folder
    If ((Get-ChildItem *.pdb -Path .\lib -Recurse).Count -gt 0) {
	    $packageTask = createProcess $path\NuGet.exe ("pack $path\Package.nuspec -Symbol -Verbosity Detailed -OutputDirectory $path")
        runProcessWaitForMessage -process $packageTask -message "Successfully created package"
        $global:ExitCode = $packageTask.ExitCode
    }
    Else {
	    $packageTask = createProcess $path\NuGet.exe ("pack $path\Package.nuspec -Verbosity Detailed -OutputDirectory $path")
	    runProcessWaitForMessage -process $packageTask -message "Successfully created package"
        $global:ExitCode = $packageTask.ExitCode
    }    
}

function createProcess([string] $fileName, [string] $arguments)
{
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

function runProcessWaitForMessage{
    param($process, [string] $message)
    
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