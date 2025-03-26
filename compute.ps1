param (
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$InputFile,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile
)

$exePath = Join-Path $PSScriptRoot "zig-out\bin\compute_haversine.exe"

if (-not (Test-Path $exePath)) {
    Write-Error "Executable not found at: $exePath"
    exit 1
}

# Start measuring time
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Execute the command with appropriate arguments
if ($OutputFile) {
    # If output file is specified, pass both arguments
    & $exePath $InputFile $OutputFile
} else {
    # If only input file is specified
    & $exePath $InputFile
}

# Stop measuring time
$stopwatch.Stop()

# Display the execution time in milliseconds
Write-Host "`nExecution time: $($stopwatch.Elapsed.TotalMilliseconds) ms" -ForegroundColor Cyan
