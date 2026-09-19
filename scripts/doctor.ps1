#requires -Version 5.1
<#
.SYNOPSIS
    doctor.ps1 - Health check for a local LLM rig (Ollama + NVIDIA on Windows).

.DESCRIPTION
    Verifies, in order:
      1. Ollama binary present + version
      2. Ollama server reachable on 127.0.0.1:11434 (auto-starts `ollama serve` if needed)
      3. NVIDIA GPU visible to nvidia-smi, with free VRAM headroom
      4. Python available (for bench.py / refusal-probe.py)
      5. Pulled models (ollama list) and their on-disk footprint
      6. Currently loaded models (/api/ps) and VRAM placement

    Prints a PASS / WARN / FAIL report. Exit code 0 = everything healthy,
    1 = at least one FAIL, 2 = only warnings (environment usable but degraded).
#>
[CmdletBinding()]
param(
    [switch]$SkipGpuCheck,
    [int]$ApiTimeoutSec = 5
)

$ErrorActionPreference = 'Stop'
$OLLAMA_API  = 'http://127.0.0.1:11434'
$results     = [System.Collections.Generic.List[object]]::new()
$exitCode    = 0

function Write-Check {
    param(
        [string]$Name,
        [ValidateSet('PASS', 'WARN', 'FAIL', 'INFO')][string]$Status,
        [string]$Detail = ''
    )
    $color = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Cyan' }[$Status]
    Write-Host ("[{0}] {1}" -f $Status, $Name) -ForegroundColor $color -NoNewline
    if ($Detail) { Write-Host (" - {0}" -f $Detail) -ForegroundColor Gray }
    else { Write-Host '' }
    $script:results.Add([pscustomobject]@{ check = $Name; status = $Status; detail = $Detail })
    if ($Status -eq 'FAIL') { $script:exitCode = 1 }
    elseif ($Status -eq 'WARN' -and $script:exitCode -lt 2) { $script:exitCode = 2 }
}

Write-Host '===== Local LLM Rig: doctor.ps1 =====' -ForegroundColor Magenta

# --- 1. Ollama binary -----------------------------------------------------
$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollama) {
    $ver = (& $ollama.Source --version 2>$null | Select-Object -First 1)
    Write-Check 'Ollama binary' 'PASS' "found: $($ollama.Source) [$ver]"
} else {
    $known = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
    if (Test-Path $known) {
        $ver = (& $known --version 2>$null | Select-Object -First 1)
        Write-Check 'Ollama binary' 'PASS' "found: $known [$ver]"
        $ollama = [pscustomobject]@{ Source = $known }
    } else {
        Write-Check 'Ollama binary' 'FAIL' 'ollama.exe not on PATH or at default install location'
    }
}

# --- 2. Ollama server -----------------------------------------------------
$serverOk = $false
try {
    $v = Invoke-RestMethod -Uri "$OLLAMA_API/api/version" -TimeoutSec $ApiTimeoutSec
    Write-Check 'Ollama server' 'PASS' "reachable at $OLLAMA_API (api version $($v.version))"
    $serverOk = $true
} catch {
    if ($ollama) {
        Write-Host '  -- Ollama server not responding; attempting to start it...' -ForegroundColor Gray
        try {
            Start-Process -FilePath $ollama.Source -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
            Start-Sleep -Seconds 4
            $v = Invoke-RestMethod -Uri "$OLLAMA_API/api/version" -TimeoutSec $ApiTimeoutSec
            Write-Check 'Ollama server' 'PASS' "auto-started, api version $($v.version)"
            $serverOk = $true
        } catch {
            Write-Check 'Ollama server' 'FAIL' 'could not reach API (is port 11434 blocked?)'
        }
    } else {
        Write-Check 'Ollama server' 'FAIL' 'ollama binary missing - cannot start server'
    }
}

# --- 3. NVIDIA GPU --------------------------------------------------------
$nv = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if (-not $SkipGpuCheck -and $nv) {
    try {
        $gpu = (& $nv.Source --query-gpu=name,memory.total,memory.used,memory.free,driver_version --format=csv,noheader,nounits -i 0)
        if ($gpu) {
            $parts = ($gpu -split ',' | ForEach-Object { $_.Trim() })
            # name,memTotal(MiB),memUsed(MiB),memFree(MiB),driver
            $freeGB = [math]::Round([double]$parts[3] / 1024.0, 1)
            $totalGB = [math]::Round([double]$parts[1] / 1024.0, 1)
            $usedGB = [math]::Round([double]$parts[2] / 1024.0, 1)
            Write-Check 'NVIDIA GPU' 'PASS' ("{0} | {1} GB VRAM ({2} GB used, {3} GB free) | driver {4}" -f $parts[0], $totalGB, $usedGB, $freeGB, $parts[4])
            if ([double]$parts[3] -lt 512) { Write-Check 'VRAM headroom' 'WARN' 'less than 0.5 GB free VRAM - close GPU apps (Epic launcher, browsers) before running benchmarks' }
            else { Write-Check 'VRAM headroom' 'PASS' "$freeGB GB free" }
        } else {
            Write-Check 'NVIDIA GPU' 'WARN' 'nvidia-smi returned no GPU row - running CPU-only?'
        }
    } catch {
        Write-Check 'NVIDIA GPU' 'WARN' "nvidia-smi query failed: $($_.Exception.Message)"
    }
} elseif (-not $SkipGpuCheck) {
    Write-Check 'NVIDIA GPU' 'WARN' 'nvidia-smi not on PATH - CUDA tooling missing; Ollama may fall back to CPU'
} else {
    Write-Check 'NVIDIA GPU' 'INFO' 'skipped per -SkipGpuCheck'
}

# --- 4. Python ------------------------------------------------------------
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    $pyver = (& $py.Source --version 2>&1 | Select-Object -First 1)
    $ok311 = $pyver -match '3\.(1[1-9]|[2-9][0-9])'
    Write-Check 'Python' $(if ($ok311) { 'PASS' } else { 'WARN' }) "$pyver at $($py.Source)"
} else {
    Write-Check 'Python' 'FAIL' 'python not on PATH - needed for bench.py / refusal-probe.py'
}

# --- 5. Pulled models -----------------------------------------------------
if ($serverOk) {
    try {
        $tags = Invoke-RestMethod -Uri "$OLLAMA_API/api/tags" -TimeoutSec $ApiTimeoutSec
        $n = @($tags.models).Count
        $totalGB = [math]::Round((($tags.models | Measure-Object -Property size -Sum).Sum) / 1GB, 1)
        Write-Check 'Pulled models' 'PASS' "$n models, ~$totalGB GB on disk"
    } catch {
        Write-Check 'Pulled models' 'WARN' "could not query /api/tags: $($_.Exception.Message)"
    }
}

# --- 6. Models on disk ----------------------------------------------------
$modelsDir = Join-Path $env:USERPROFILE '.ollama\models'
if (Test-Path $modelsDir) {
    try {
        $diskBytes = (Get-ChildItem $modelsDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        Write-Check 'Ollama model store' 'PASS' "$modelsDir ($([math]::Round($diskBytes / 1GB, 1)) GB)"
    } catch { Write-Check 'Ollama model store' 'WARN' 'could not measure model directory' }
} else {
    Write-Check 'Ollama model store' 'WARN' "expected model dir not found: $modelsDir (non-standard OLLAMA_MODELS?)"
}

# --- 7. Currently loaded into memory -------------------------------------
if ($serverOk) {
    try {
        $ps = Invoke-RestMethod -Uri "$OLLAMA_API/api/ps" -TimeoutSec $ApiTimeoutSec
        if (@($ps.models).Count -eq 0) {
            Write-Check 'Loaded models' 'INFO' 'none currently resident in memory'
        } else {
            foreach ($m in $ps.models) {
                $vram = [math]::Round($m.size_vram / 1MB, 0)
                $tot  = [math]::Round($m.size / 1MB, 0)
                Write-Check 'Loaded models' 'INFO' ("{0}: {1} MB total, {2} MB VRAM" -f $m.name, $tot, $vram)
            }
        }
    } catch { Write-Check 'Loaded models' 'WARN' "could not query /api/ps" }
}

# --- Summary --------------------------------------------------------------
Write-Host ''
$fails = @($results | Where-Object status -eq 'FAIL').Count
$warns = @($results | Where-Object status -eq 'WARN').Count
$passes = @($results | Where-Object status -eq 'PASS').Count
Write-Host ('===== Summary: {0} PASS / {1} WARN / {2} FAIL =====' -f $passes, $warns, $fails) -ForegroundColor Magenta
if ($fails -gt 0) { Write-Host 'Result: FAIL (fix the FAIL items above before benchmarking)' -ForegroundColor Red }
elseif ($warns -gt 0) { Write-Host 'Result: HEALTHY WITH WARNINGS (usable, but review non-critical items)' -ForegroundColor Yellow }
else { Write-Host 'Result: ALL CLEAR' -ForegroundColor Green }

# Persist report next to this script
$outPath = Join-Path $PSScriptRoot 'doctor-report.json'
$results | ConvertTo-Json | Set-Content -Path $outPath -Encoding UTF8
Write-Host "Report saved to $outPath" -ForegroundColor Gray
exit $exitCode