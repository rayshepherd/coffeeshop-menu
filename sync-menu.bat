@echo off
cd /d "C:\Users\SambaPOS Server\Documents\files"
powershell -ExecutionPolicy Bypass -File "Export-SambaMenu.ps1"
git add menu.json
git commit -m "Auto-update menu %date% %time%"
git push