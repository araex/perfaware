$ErrorActionPreference = "Stop"

# Define script directory and ensure we work with full paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Script directory: $scriptDir"

# Change to script directory
Push-Location $scriptDir
try {
    # Define the output library file - we'll use a common name for all ASM files
    $libFile = Join-Path $scriptDir "asm_functions.lib"

    # Check if NASM is in PATH
    try {
        $nasmVersion = nasm -v
        Write-Host "Found NASM: $nasmVersion"
    } catch {
        Write-Error "NASM not found in PATH. Please install NASM and add it to your PATH."
        exit 1
    }

    # Check if lib.exe is in PATH
    try {
        $libCommand = Get-Command lib.exe -ErrorAction Stop
        Write-Host "Found lib.exe at: $($libCommand.Source)"
    } catch {
        Write-Host "lib.exe not found in PATH. Trying to find Visual Studio installation..."
        
        # Try to find Visual Studio installation
        $vsPath = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        
        if ($vsPath) {
            Write-Host "Found Visual Studio at: $vsPath"
            # Initialize VS Developer Command Prompt environment
            $vcvarsallPath = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
            if (Test-Path $vcvarsallPath) {
                Write-Host "Initializing Visual Studio environment..."
                # Create a temporary batch file to capture environment variables
                $tempFile = [System.IO.Path]::GetTempFileName() + ".bat"
                "@echo off`r`ncall `"$vcvarsallPath`" x64 > nul`r`nset" | Out-File -FilePath $tempFile -Encoding ASCII
                
                # Run the batch file and capture environment variables
                $envVars = cmd /c "$tempFile" | Where-Object { $_ -match '=' } | ForEach-Object {
                    $name, $value = $_ -split '=', 2
                    [PSCustomObject]@{Name = $name; Value = $value}
                }
                
                # Set the environment variables in the current PowerShell session
                foreach ($var in $envVars) {
                    [System.Environment]::SetEnvironmentVariable($var.Name, $var.Value, [System.EnvironmentVariableTarget]::Process)
                }
                
                Remove-Item $tempFile
                
                try {
                    $libCommand = Get-Command lib.exe -ErrorAction Stop
                    Write-Host "Found lib.exe at: $($libCommand.Source)"
                } catch {
                    Write-Error "lib.exe still not found after initializing VS environment."
                    exit 1
                }
            } else {
                Write-Error "vcvarsall.bat not found at expected location: $vcvarsallPath"
                exit 1
            }
        } else {
            Write-Error "Visual Studio installation not found. Please ensure Visual Studio with C++ tools is installed."
            exit 1
        }
    }

    # Find all ASM files in the current directory
    $asmFiles = Get-ChildItem -Path $scriptDir -Filter "*.asm" | Select-Object -ExpandProperty FullName
    
    if ($asmFiles.Count -eq 0) {
        Write-Error "No .asm files found in $scriptDir"
        exit 1
    }
    
    Write-Host "Found $($asmFiles.Count) assembly files to process"
    
    # Create a temporary directory for object files
    $objDir = Join-Path $scriptDir "obj_temp"
    if (-not (Test-Path $objDir)) {
        New-Item -Path $objDir -ItemType Directory | Out-Null
    } else {
        # Clean up any existing object files
        Remove-Item -Path (Join-Path $objDir "*.obj") -ErrorAction SilentlyContinue
    }
    
    # Compile each ASM file to an object file
    $objFiles = @()
    foreach ($asmFile in $asmFiles) {
        $asmName = [System.IO.Path]::GetFileNameWithoutExtension($asmFile)
        $objFile = Join-Path $objDir "$asmName.obj"
        $objFiles += $objFile
        
        Write-Host "Assembling $asmFile to $objFile..."
        nasm -f win64 $asmFile -o $objFile
        
        if (-not (Test-Path $objFile)) {
            Write-Error "Failed to create object file: $objFile"
            exit 1
        }
    }
    
    # Create the library file from all object files
    Write-Host "Creating library $libFile from $($objFiles.Count) object files..."
    lib /nologo /out:$libFile $objFiles
    
    if (Test-Path $libFile) {
        Write-Host "Successfully created library: $libFile"
    } else {
        Write-Error "Failed to create library file: $libFile"
        exit 1
    }
    
    # Clean up temporary object files
    if (Test-Path $objDir) {
        Remove-Item -Path $objDir -Recurse -Force
        Write-Host "Cleaned up temporary object files"
    }

    Write-Host "Build completed successfully."
} finally {
    # Return to the original directory
    Pop-Location
}