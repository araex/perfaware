param (
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+$')]
    [string]$Seed,
    
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+$')]
    [string]$NumberOfPairs
)
if (-not [uint32]::TryParse($Seed, [ref]$null)) {
    Write-Error "The seed must be an unsigned integer."
    exit 1
}
if (-not [uint32]::TryParse($NumberOfPairs, [ref]$null)) {
    Write-Error "The number of pairs must be an unsigned integer."
    exit 1
}

$exePath = Join-Path $PSScriptRoot "zig-out\bin\generate_haversine_pairs.exe"

if (-not (Test-Path $exePath)) {
    Write-Error "Executable not found at: $exePath"
    exit 1
}

# Start measuring time
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Execute the command and let output flow to console
& $exePath $Seed $NumberOfPairs

# Stop measuring time
$stopwatch.Stop()

# Display the execution time in milliseconds
Write-Host "`nExecution time: $($stopwatch.Elapsed.TotalMilliseconds) ms" -ForegroundColor Cyan
