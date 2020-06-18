#region PublicFunctions

function New-DuplicateCheck() {
    # Initial param block
    param(
        [parameter(mandatory=$false)][string[]]$FILE_EXTENSIONS = @("*"),
        [parameter(mandatory=$true)][string]$SEARCH_LOCATION,
        [parameter(mandatory=$false)][String]$SEARCH_DEPTH = "*",
        [parameter(mandatory=$true)][string]$LOG_LOCATION,
        [parameter(mandatory=$false)][Int]$MONITORING_FREQUENCY = 10
    )

    #region ParamValidation
    #### SEARCH_LOCATION VALIDATION ####
    $SearchLocationTest = Test-Path -Path $SEARCH_LOCATION 
    # If the directory we've been asked to search does not exist then throw an exception
    if ($SearchLocationTest -eq $false) {
        throw [System.IO.DirectoryNotFoundException]::new("Could not find directory provided for SEARCH_LOCATION: $SEARCH_LOCATION")
    }
    #### SEARCH_DEPTH VALIDATION ####
    [Int]$SearchDepthCheck = $null
    # If we're unable to cast to an INT and SEARCH_DEPTH is not the default value of * then throw an exception
    if (([Int32]::TryParse($SEARCH_DEPTH, [ref]$SearchDepthCheck) -eq $false) -and $SEARCH_DEPTH -ne "*") {
        throw [System.FormatException]::new("Could not convert provided SEARCH_DEPTH to an INT: $SEARCH_DEPTH")
        # If we can cast to an INT but this value is less than 0 then also throw an exception
    } elseif ($SEARCH_DEPTH -eq "*") {
        # do nothing
    } elseif ([Int32]::Parse($SEARCH_DEPTH) -lt 0) {
        throw [System.FormatException]::new("Negative value provided for SEARCH_DEPTH: $SEARCH_DEPTH. Please provide null or positive value")
    } 

    #### MONITORING_FREQUENCY VALIDATION ####
    # If we've been provided with an int less than or equal to 0 then throw an exception
    if ($MONITORING_FREQUENCY -le 0) {
        throw [System.IndexOutOfRangeException]::new("Negative value provided for monitoring frequency: $MONITORING_FREQUENCY. Please provide a positive value")
    }
    #endregion ParamValidation
    
    # Job to check for duplicate files
    $DuplicationCheck = Start-Job -Name DuplicateFileLocator -ScriptBlock {
        param(
            $p1,$p2,$p3,$p4
        )
        function Get-DuplicateFiles() {
            param(
                [parameter(mandatory=$true)][string[]]$FILE_EXTENSIONS,
                [parameter(mandatory=$true)][string]$SEARCH_LOCATION,
                [parameter(mandatory=$false)][String]$SEARCH_DEPTH,
                [parameter(mandatory=$true)][string]$LOG_LOCATION
            )

            Write-Progress  -Status "Started job"-Completed -Activity "Processing"
            # Get current date
            $CurrentDate = Get-Date
            # Create new log structure and store for future reference
            $GeneratedLogLocation = New-LogStructure -LOG_LOCATION $LOG_LOCATION -CurrentDate $CurrentDate
            # Generate random int for log file but store as string
            $RandomString = (Get-Random -Maximum 10000).ToString()
        
            # Generate extension array for fiter statement
            $ExtensionArray = New-Object System.Collections.ArrayList
            foreach ($Extension in $FILE_EXTENSIONS) {
                $ExtensionArray.Add([string]::Format("*.{0}",$Extension))
            }
            
            # Generate list of files to check
            Write-Progress  -Status "Scanning $SEARCH_LOCATION at depth $SEARCH_DEPTH"-Completed -Activity "Processing"
            $Files = $null
            if ($SEARCH_DEPTH -ne "*") {
                # Enumerate each required extension and get files
                # Used as -depth seems to not work when you use include but not with filter
                foreach ($Extension in $ExtensionArray) {

                    $Files += Get-ChildItem -Depth ([Int]$SEARCH_DEPTH) -Path $SEARCH_LOCATION -filter $Extension -ErrorAction SilentlyContinue | Get-FileHash | Select-Object Path, Hash

                }
                
            } else {
                # Using recurse without depth will enumerate all subitems
                foreach ($Extension in $ExtensionArray) {

                    $Files += Get-ChildItem -Path $SEARCH_LOCATION -filter $Extension -Recurse -ErrorAction SilentlyContinue | Get-FileHash | Select-Object Path, Hash

                }
            }

            $TotalFiles = $Files.count
            # Start processing
            $FilesProcessed = 0
            $DuplicateFiles = @()
            foreach ($File in $Files) {
                # Update process
                Write-Progress  -Status "Processing file $FilesProcessed\$TotalFiles "-Completed -Activity "Processing"
                # Update log
                $LogMessage = "File: " + $File.Path + " # "
                $Owner = (Get-Acl $File.Path -ErrorAction SilentlyContinue | Select-Object Owner).Owner
                $LogMessage += "Owner: $Owner" + " # "
                $LogMessage += "Hash: " + $File.Hash + "# "
                # Check for duplication
                $DuplicateIndex = $Files.Hash.IndexOf($File.Hash)
                # If we found the same hash but it's not for the same file then output to log
                if (($DuplicateIndex -ne -1) -and ($DuplicateIndex -ne $Files.IndexOf($File))) {
                    $LogMessage += ("Possible Duplicate: " + $Files[$DuplicateIndex].Path)
                } else { # Else output that no duplication has been found
                    $LogMessage += "Same hash: no duplication found"
                }


                Update-LogFile -GeneratedLogLocation $GeneratedLogLocation -Message $LogMessage -RandomInt $RandomString
                $FilesProcessed += 1
                Write-Progress  -Status ([string]::Format("{0}\{1} files processed", $FilesProcessed, $TotalFiles)) -Completed `
                -Activity "Processing"
            }

            # Textual report
            Write-Progress  -Status "Creating reports" -Completed -Activity "Processing"
            New-Reports -LogPath $GeneratedLogLocation -RandomInt $RandomString `
            -SEARCH_LOCATION $SEARCH_LOCATION -FILE_EXTENSIONS $FILE_EXTENSIONS `
            -SEARCH_DEPTH $SEARCH_DEPTH
        }

        function New-LogStructure() {
            param(
                [parameter(mandatory=$true)][string]$LOG_LOCATION,
                [parameter(mandatory=$true)][DateTime]$CurrentDate
            )
            # Create new Folders
            New-LogFolder -FolderPath $([string]::Format("{0}\{1}",$LOG_LOCATION, (Get-FriendlyFormat -OriginalValue $CurrentDate.Year)))
            New-LogFolder -FolderPath $([string]::Format("{0}\{1}\{2}",$LOG_LOCATION, (Get-FriendlyFormat -OriginalValue $CurrentDate.Year),
            (Get-FriendlyFormat -OriginalValue $CurrentDate.Month)))
            New-LogFolder -FolderPath $([string]::Format("{0}\{1}\{2}\{3}",$LOG_LOCATION, (Get-FriendlyFormat -OriginalValue $CurrentDate.Year),
            (Get-FriendlyFormat -OriginalValue $CurrentDate.Month),(Get-FriendlyFormat -OriginalValue $CurrentDate.Day)))
        
            # Return log structure for future reference
            return [string]::Format("{0}\{1}\{2}\{3}",$LOG_LOCATION, (Get-FriendlyFormat -OriginalValue $CurrentDate.Year),
            (Get-FriendlyFormat -OriginalValue $CurrentDate.Month),(Get-FriendlyFormat -OriginalValue $CurrentDate.Day))
        
        }
        function New-LogFolder() {
            param(
                [parameter(mandatory=$True)][string]$FolderPath
            )
        
            $Check = Test-Path -Path $FolderPath
            if ($Check -eq $false) {
                New-Item -Path $FolderPath -ItemType Directory | Out-Null
            }
        }
        
        Function Get-FriendlyFormat() {
          
            param(
            [parameter(mandatory=$true)][string]$OriginalValue
            )
        
            [Int]$Placeholder = $null
            if ([Int32]::TryParse($OriginalValue, [ref]$Placeholder) -eq $True) {
                $ValueINT = [Int32]::Parse($OriginalValue)
                If ($ValueINT -lt 10) {
                    return [string]::Format("0{0}",$OriginalValue)
                    } else {
                        return $OriginalValue
                    }
                } else {
                    return $OriginalValue
                    }
        }

        function New-LogFile() {
            param(
                [parameter(mandatory=$true)][string]$GeneratedLogLocation,
                [parameter(mandatory=$true)][string]$RandomInt
            )
                $FilePath = [string]::Format("{0}\log-$RandomInt.txt",$GeneratedLogLocation)
                $Check = Test-Path -Path $FilePath
                if ($Check -eq $false) {
                    New-Item -Path $FilePath -ItemType File | Out-Null
                }
                return $FilePath
            
        }

        function Update-LogFile() {
            param(
                [parameter(mandatory=$true)][string]$Message,
                [parameter(mandatory=$true)][string]$GeneratedLogLocation,
                [parameter(mandatory=$true)][string]$RandomInt
            )

            $Date = Get-Date
            # Format Date 
            $LogDate = [string]::Format("{0}{1}{2}{1}{3}{1}{4}{1}{5}{1}{6}", (Get-FriendlyFormat -OriginalValue $Date.Day), ":", (Get-FriendlyFormat -OriginalValue $Date.Month), 
            (Get-FriendlyFormat -OriginalValue $Date.Year), (Get-FriendlyFormat -OriginalValue $Date.Hour), (Get-FriendlyFormat -OriginalValue $Date.Minute), (Get-FriendlyFormat -OriginalValue $Date.Second))
            # Update log
            $LogPath = [string]::Format("{0}\log-$RandomInt.txt",$GeneratedLogLocation)
            $Update = $LogDate + " # " + $Message
            $Update | Add-Content -Path $LogPath
        }

        function New-Reports() {
            param(
                [parameter(mandatory=$true)][string]$LogPath,
                [parameter(mandatory=$true)][string]$RandomInt,
                [parameter(mandatory=$true)][string]$SEARCH_LOCATION,
                [parameter(mandatory=$true)][string[]]$FILE_EXTENSIONS,
                [parameter(mandatory=$true)][string]$SEARCH_DEPTH
            )
            # Feed into textual and html reports
            New-TextualReport -LogPath $LogPath -RandomInt $RandomInt `
            -SEARCH_LOCATION $SEARCH_LOCATION -FILE_EXTENSIONS $FILE_EXTENSIONS -SEARCH_DEPTH $SEARCH_DEPTH
            New-HTMLReport -LogPath $LogPath -RandomInt $RandomInt `
            -SEARCH_LOCATION $SEARCH_LOCATION -FILE_EXTENSIONS $FILE_EXTENSIONS -SEARCH_DEPTH $SEARCH_DEPTH
        }
        function New-HTMLReport() {
            param (
                [parameter(mandatory=$true)][string]$LogPath,
                [parameter(mandatory=$true)][string]$RandomInt,
                [parameter(mandatory=$true)][string]$SEARCH_LOCATION,
                [parameter(mandatory=$true)][string[]]$FILE_EXTENSIONS,
                [parameter(mandatory=$true)][string]$SEARCH_DEPTH
            )
            # Get log contents
            $FilePath = [string]::Format("{0}\log-$RandomInt.txt",$LogPath)
            $LogContent = Get-Content $FilePath | Select-String "Possible Duplicate*"
            # Get total duplicate files, report path and empty hash
            $TotalFiles = $LogContent.count
            $TimeNow = Get-Date
            $ReportPath = [string]::Format("{0}\report-$RandomInt.html",$LogPath)
            $Properties = @()
            # Enumerate through duplicate files to create new object and add to hash
            foreach ($Line in $LogContent) {
                $FilteredContent = ($Line | Out-String).Split("#").Trim()
                $File = $FilteredContent[1].Replace("File: ","").trim()
                $PossibleDuplication = $FilteredContent[4].Replace("Possible Duplicate: ","").trim()
                $Object = [PSCustomObject]@{
                    File = $File
                    Duplicate = $PossibleDuplication
                }
                $Properties += $Object
            }
            # Create object of all duplicate items in format acceptable to ConvertTo-HTML
            # Out HTML
            $Properties | ConvertTo-Html -Title ("Duplicate File Locator") `
            -Body ("<h1>Duplicate File Locator report for $SEARCH_LOCATION at depth $SEARCH_DEPTH</h1><h2>$TotalFiles possible duplicates found</h2><h3>File extensions searched: $FILE_EXTENSIONS</h3><h4>Report generated $TimeNow</h4>") `
            | Out-File $ReportPath

            
        }
        function New-TextualReport() {
            param(
                [parameter(mandatory=$true)][string]$LogPath,
                [parameter(mandatory=$true)][string]$RandomInt,
                [parameter(mandatory=$true)][string]$SEARCH_LOCATION,
                [parameter(mandatory=$true)][string[]]$FILE_EXTENSIONS,
                [parameter(mandatory=$true)][string]$SEARCH_DEPTH
            )
            # Get log contents
            $FilePath = [string]::Format("{0}\log-$RandomInt.txt",$LogPath)
            $LogContent = Get-Content $FilePath | Select-String "Possible Duplicate*"
            # Report vars
            $ReportPath = [string]::Format("{0}\report-$RandomInt.txt",$LogPath)
            $TotalFiles = $LogContent.count
            $TimeNow = Get-Date
            # Report 'header'
            ("#" * 50) | Add-Content $ReportPath
            "#     Duplicate File Locator report for $SEARCH_LOCATION at depth $SEARCH_DEPTH" | Add-Content $ReportPath
            "#     $TotalFiles possible duplicates found" | Add-Content $ReportPath
            "#     File extensions searched: $FILE_EXTENSIONS" | Add-Content $ReportPath
            "#     Report generated $TimeNow" | Add-Content $ReportPath
            ("#" * 50) | Add-Content $ReportPath
            # Report duplicate files
            $Count = 1
            foreach ($Line in $LogContent) {
                $FilteredContent = ($Line | Out-String).Split("#").Trim()
                $File = $FilteredContent[1].Replace("File: ","").trim()
                $PossibleDuplication = $FilteredContent[4].Replace("Possible Duplicate: ","").trim().Replace("Possible Duplicate:","").Trim()
                "$Count -- $File is possibly a duplicate of $PossibleDuplication" | Add-Content $ReportPath
                $Count += 1
            }
            # Report 'footer'
            ("#" * 50) | Add-Content $ReportPath

            
        }

        Get-DuplicateFiles -FILE_EXTENSIONS $p1 -SEARCH_LOCATION $p2 -SEARCH_DEPTH $p3 -LOG_LOCATION $p4
    } -ArgumentList $FILE_EXTENSIONS, $SEARCH_LOCATION, $SEARCH_DEPTH, $LOG_LOCATION

    # Work out drive
    $Drive = $SEARCH_LOCATION.Substring(0,2)
    # Loop to wait for when job has finished processing
    while ($DuplicationCheck.State -eq "Running") {
        Start-Sleep -Seconds $MONITORING_FREQUENCY
        $FilesProcessed = $DuplicationCheck.ChildJobs[0].Progress[-1]
        # Check for files progressed
        $FileMessage = ""
        if (($FilesProcessed -eq $null) -or ($FilesProcessed.Activity -ne "Processing")) {
            $FileMessage = "Scanning $LOG_LOCATION directory at depth of $SEARCH_DEPTH"
        } else {
            $FileMessage = $FilesProcessed.StatusDescription
        }

        Add-MonitoringUpdate -FileProgress $FileMessage -DriveToCheck $Drive
    }
    
    
}

#endRegion

#region PrivateFunctions
function Add-MonitoringUpdate() {
    param (
        [parameter(mandatory=$true)][string[]]$FileProgress,
        [parameter(mandatory=$true)][string]$DriveToCheck
    )
    $Date = Get-Date
    # Format Date 
    $LogDate = [string]::Format("{0}{1}{2}{1}{3}{1}{4}{1}{5}{1}{6}", (Get-FriendlyFormat -OriginalValue $Date.Day), ":", (Get-FriendlyFormat -OriginalValue $Date.Month), 
    (Get-FriendlyFormat -OriginalValue $Date.Year), (Get-FriendlyFormat -OriginalValue $Date.Hour), (Get-FriendlyFormat -OriginalValue $Date.Minute), (Get-FriendlyFormat -OriginalValue $Date.Second))
    # CPU
    $CPUUsage = [Math]::Round((Get-Counter '\Processor(*)\% Processor Time' | Select-Object -expand CounterSamples | Where-Object {$_.InstanceName -eq '_total'}).cookedValue)
    # RAM
    $OSCim = Get-Ciminstance Win32_OperatingSystem
    $RAMFree = [math]::Round(($OSCim.FreePhysicalMemory/$OSCim.TotalVisibleMemorySize)*100)
    # Disk
    $Disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID = '$DriveToCheck'"
    # Space returned in bytes, get GB and round to 2 decimal places
    $SpaceString = [string]::Format("{0}/{1}GB $DriveToCheck free space",
    [math]::Round((((($Disk.FreeSpace) / 1024) / 1024) / 1024),2),
    [math]::Round((((($Disk.Size) / 1024) / 1024) / 1024),2))
    # Output
    Write-Output -InputObject ([string]::Format("{0} # CPU Usage: {2}% # RAM Usage: {3}% # {4} # {1}",`
    $LogDate,$FileProgress[-1],$CPUUsage, $RAMFree,$SpaceString))
}

Function Get-FriendlyFormat() {
  
    param(
    [parameter(mandatory=$true)][string]$OriginalValue
    )

    [Int]$Placeholder = $null
    if ([Int32]::TryParse($OriginalValue, [ref]$Placeholder) -eq $True) {
        $ValueINT = [Int32]::Parse($OriginalValue)
        If ($ValueINT -lt 10) {
            return [string]::Format("0{0}",$OriginalValue)
            } else {
                return $OriginalValue
            }
        } else {
            return $OriginalValue
            }
}

#endregion PrivateFunctions

Export-ModuleMember -Function New-DuplicateCheck
