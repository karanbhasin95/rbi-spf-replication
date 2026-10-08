$ErrorActionPreference = "Stop"
$ReproRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$MasterDo = Join-Path $ReproRoot "code\master.do"
$BaselineData = Join-Path $ReproRoot "data\baseline_data.dta"
$TableResults = Join-Path $ReproRoot "results\tables"
$FigureResults = Join-Path $ReproRoot "results\figures"
$CompletionMarker = Join-Path $ReproRoot ".replication_build_complete.tmp"
$RuntimeArtifacts = @(
    $CompletionMarker,
    (Join-Path $ReproRoot ".figure07_runtime.irf"),
    (Join-Path $ReproRoot ".figure08_runtime.irf"),
    (Join-Path $ReproRoot ".appendix_figure_d2_runtime.irf"),
    (Join-Path $ReproRoot "master.log")
)

if (-not (Test-Path -LiteralPath $BaselineData)) {
    throw "Required Stata input not found: $BaselineData"
}

$StataCandidates = @(
    "C:\Program Files\StataNow19\StataMP-64.exe",
    "C:\Program Files\Stata19\StataMP-64.exe"
)
$StataExe = $StataCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $StataExe) { throw "Stata MP 19 was not found. Update run_all.ps1 with its location." }

Push-Location $ReproRoot
try {
    # Keep results publication-facing: remove prior generated outputs before
    # rebuilding, while retaining the static descriptive Table 6.
    if (Test-Path -LiteralPath $TableResults) {
        Get-ChildItem -LiteralPath $TableResults -File |
            Where-Object { $_.Name -ne "table06.csv" } |
            Remove-Item -Force
    }
    if (Test-Path -LiteralPath $FigureResults) {
        Get-ChildItem -LiteralPath $FigureResults -File | Remove-Item -Force
    }
    foreach ($RuntimeArtifact in $RuntimeArtifacts) {
        if (Test-Path -LiteralPath $RuntimeArtifact) {
            Remove-Item -LiteralPath $RuntimeArtifact -Force
        }
    }

    $StataProcess = Start-Process -FilePath $StataExe -ArgumentList @("/e", "do", "`"$MasterDo`"") -WindowStyle Hidden -Wait -PassThru
    if ($StataProcess.ExitCode -ne 0) { throw "Stata build failed with exit code $($StataProcess.ExitCode)." }
    if (-not (Test-Path -LiteralPath $CompletionMarker)) {
        throw "Stata stopped before completing every table and figure."
    }
}
finally {
    foreach ($RuntimeArtifact in $RuntimeArtifacts) {
        if (Test-Path -LiteralPath $RuntimeArtifact) {
            try { Remove-Item -LiteralPath $RuntimeArtifact -Force }
            catch { Write-Verbose "A temporary Stata artifact is still in use: $RuntimeArtifact" }
        }
    }
    Pop-Location
}

Write-Host "Stata replication build completed: $ReproRoot\results"
