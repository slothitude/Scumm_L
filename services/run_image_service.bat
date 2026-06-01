@echo off
cd /d D:\scumm-l-image-service
set PYTHONPATH=D:\scumm-l-image-service
"C:\Program Files\Python311\python.exe" -m uvicorn image_service:app --host 0.0.0.0 --port 8010
