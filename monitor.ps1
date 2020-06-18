param(
    [parameter(mandatory=$false)][string[]]$FILE_EXTENSIONS = @("*"),
    [parameter(mandatory=$true)][string]$SEARCH_LOCATION,
    [parameter(mandatory=$false)][String]$SEARCH_DEPTH = "*",
    [parameter(mandatory=$true)][string]$LOG_LOCATION,
    [parameter(mandatory=$false)][Int]$MONITORING_FREQUENCY = 10
)
Import-Module -Name .\DuplicateFileLocator\DuplicateFileLocator.psd1

New-DuplicateCheck  -FILE_EXTENSIONS $FILE_EXTENSIONS `
                    -SEARCH_LOCATION $SEARCH_LOCATION `
                    -SEARCH_DEPTH $SEARCH_DEPTH `
                    -LOG_LOCATION $LOG_LOCATION `
                    -MONITORING_FREQUENCY $MONITORING_FREQUENCY
