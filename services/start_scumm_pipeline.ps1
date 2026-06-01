# SCUMM-L Pipeline Starter (NSSM-compatible)
# Starts Bonsai FLUX on :8000 and image_service on :8010
# All output goes to stdout so NSSM sees I/O activity and doesn't pause

Write-Output "=== SCUMM-L Image Pipeline ==="

# Start Bonsai on port 8000
Write-Output "[1/2] Starting Bonsai FLUX on port 8000..."
$bonsaiProc = Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c", "D:\bonsai-image-demo\start_bonsai.bat" `
    -WindowStyle Minimized `
    -PassThru
Write-Output "  Bonsai PID: $($bonsaiProc.Id)"

# Wait for Bonsai to be ready (first load takes ~60-90s for JIT compile)
Write-Output "  Waiting for Bonsai to start..."
$bonsaiReady = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $null = Invoke-WebRequest -Uri http://localhost:8000/backends -TimeoutSec 2 -UseBasicParsing
        $bonsaiReady = $true
        break
    } catch {
        Start-Sleep -Seconds 3
        Write-Output "." -NoNewline
    }
}
Write-Output ""
if ($bonsaiReady) {
    Write-Output "  Bonsai ready on :8000"
} else {
    Write-Output "  WARNING: Bonsai not responding yet (may still be loading)"
}

# Start image_service on port 8010
Write-Output "[2/2] Starting image_service on port 8010..."
$env:PYTHONPATH = "D:\scumm-l-image-service"
$imgProc = Start-Process -FilePath "python.exe" `
    -ArgumentList "-m", "uvicorn", "image_service:app", "--host", "0.0.0.0", "--port", "8010" `
    -WorkingDirectory "D:\scumm-l-image-service" `
    -WindowStyle Minimized `
    -PassThru
Write-Output "  image_service PID: $($imgProc.Id)"

# Wait for image_service
Start-Sleep -Seconds 4
try {
    $health = (Invoke-WebRequest -Uri http://localhost:8010/health -TimeoutSec 5 -UseBasicParsing).Content
    Write-Output "  image_service ready: $health"
} catch {
    Write-Output "  WARNING: image_service not responding"
}

Write-Output ""
Write-Output "=== Pipeline Running ==="
Write-Output "  Bonsai:       http://localhost:8000"
Write-Output "  image_service: http://localhost:8010"
Write-Output "  Godot endpoint: http://100.84.161.63:8010"

# Keep alive — write heartbeat to stdout so NSSM doesn't pause the service
try {
    while ($true) {
        Start-Sleep -Seconds 30
        Write-Output "[$(Get-Date -Format 'HH:mm:ss')] Pipeline alive - Bonsai PID:$($bonsaiProc.Id) image_service PID:$($imgProc.Id)"
    }
} finally {
    Write-Output "Shutting down..."
    Stop-Process -Id $bonsaiProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $imgProc.Id -Force -ErrorAction SilentlyContinue
    Write-Output "Stopped."
}
