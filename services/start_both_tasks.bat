@echo off
REM Create and run both scheduled tasks for SCUMM-L image pipeline

schtasks /Delete /TN Bonsai-8000 /F 2>nul
schtasks /Create /TN "Bonsai-8000" /TR "cmd /c D:\Bonsai-Image-Demo\start_bonsai.bat" /SC ONCE /SD 2099-01-01 /ST 00:00 /RL HIGHEST /F
schtasks /Run /TN "Bonsai-8000"
echo Bonsai-8000: started

schtasks /Delete /TN SCUMM-L-ImageService /F 2>nul
schtasks /Create /TN "SCUMM-L-ImageService" /TR "cmd /c set PYTHONPATH=D:\scumm-l-image-service && cd /d D:\scumm-l-image-service && python -m uvicorn image_service:app --host 0.0.0.0 --port 8010" /SC ONCE /SD 2099-01-01 /ST 00:00 /RL HIGHEST /F
schtasks /Run /TN "SCUMM-L-ImageService"
echo SCUMM-L-ImageService: started
