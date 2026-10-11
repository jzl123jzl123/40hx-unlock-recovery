@echo off
chcp 936 >nul
setlocal EnableDelayedExpansion
REM === 40HX VBIOS 采集 + 硬件指纹（2026-10-11，全程只读，不刷机）===
net session >nul 2>&1
if errorlevel 1 (
  echo 需要管理员权限，正在提权（弹窗请点"是"）...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
set STAMP=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%
set STAMP=!STAMP: =0!
set W=C:\Temp\40hx-vbios-!STAMP!
mkdir "!W!" 2>nul
for /f %%H in ('powershell -NoProfile -Command "(Get-FileHash '%~dp0nvflash64.exe' -Algorithm SHA256).Hash.ToLower()"') do set NVH=%%H
if /i not "!NVH!"=="c0620a7be0ffdad3782d9ddf238d1a19c31b587cbcfee7036819c8a50e2d89cd" (
  echo [X] nvflash64.exe 已被改动（SHA256 不符）—— 请重新解压采集包再跑
  pause & exit /b 1
)
copy /y "%~dp0nvflash64.exe" "!W!\nvflash64.exe" >nul
cd /d "!W!"
echo 采集目录: !W!
echo.

echo [1/8] nvflash 版本与显卡识别...
nvflash64 --version > 01-nvflash-version.txt 2>&1
nvflash64 --list > 02-nvflash-list.txt 2>&1
type 02-nvflash-list.txt

echo [2/8] 备份 VBIOS（只读操作，不写入显卡）...
nvflash64 --save 40HX-vbios.rom > 03-nvflash-save.txt 2>&1
type 03-nvflash-save.txt
if exist 40HX-vbios.rom (
  certutil -hashfile 40HX-vbios.rom SHA256 > 04-rom-sha256.txt 2>&1
  echo VBIOS 已备份: !W!\40HX-vbios.rom
) else (
  echo [!!] nvflash 没能读出 VBIOS —— 继续采其它信息，把结果发回来分析
)

echo [3/8] nvidia-smi 完整参数...
C:\Windows\System32\nvidia-smi.exe -q > 05-nvidia-smi-q.txt 2>&1
C:\Windows\System32\nvidia-smi.exe --query-gpu=name,vbios_version,driver_version,pci.bus_id,pci.device_id,pci.sub_device_id,uuid,serial,board_id,gpu_part_number,inforom_version,inforom_image_version,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max --format=csv > 06-nvidia-smi-quick.txt 2>&1

echo [4/8] 显卡寄存器快照（守卫体检，只读）...
set GTOOL=C:\ProgramData\CMP40HXGen2\windows\40hx-retrain-inpout.ps1
if exist "!GTOOL!" (
  copy /y "C:\ProgramData\CMP40HXGen2\windows\logs\retrain-last.log" "!W!\retrain-last.log.keep" >nul 2>&1
  powershell -NoProfile -ExecutionPolicy Bypass -File "!GTOOL!" > 07-guard-registers.txt 2>&1
  copy /y "!W!\retrain-last.log.keep" "C:\ProgramData\CMP40HXGen2\windows\logs\retrain-last.log" >nul 2>&1
) else (
  echo 没找到 Gen2 工具，跳过 > 07-guard-registers.txt
)

echo [5/8] ESP 上的解锁固件日志...
mountvol Y: /s >nul 2>&1
if exist Y:\40hx_log.txt ( copy /y Y:\40hx_log.txt 08-esp-40hx_log.txt >nul ) else ( echo ESP 上没有 40hx_log.txt > 08-esp-40hx_log.txt )
if exist Y:\EFI\40HX ( dir Y:\EFI\40HX > 08b-esp-efi-listing.txt 2>&1 ) else ( echo 无 EFI\40HX 目录 > 08b-esp-efi-listing.txt )
mountvol Y: /d >nul 2>&1

echo [6/8] 固件启动项...
bcdedit /enum firmware > 09-bootentries.txt 2>&1

echo [7/8] 主板 / BIOS / 设备状态...
powershell -NoProfile -Command "Get-CimInstance Win32_ComputerSystemProduct | Select-Object Vendor,Name,Version,IdentifyingNumber | Format-List; Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer,Product,Version,SerialNumber | Format-List; Get-CimInstance Win32_BIOS | Select-Object Manufacturer,SMBIOSBIOSVersion,ReleaseDate,SerialNumber | Format-List; Get-CimInstance Win32_Processor | Select-Object Name | Format-List; Get-CimInstance Win32_PnPEntity -Filter \"Class='Display'\" | Select-Object Name,Status,PNPDeviceID | Format-List; Confirm-SecureBootUEFI 2>&1 | Out-String" > 10-machine.txt 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" /v EnableGpuFirmware /s > 11-gsp-registry.txt 2>&1

echo [8/8] 打包...
set ZIP=%USERPROFILE%\Desktop\40HX-VBIOS采集-%COMPUTERNAME%-!STAMP!.zip
powershell -NoProfile -Command "Compress-Archive -Path '!W!\*' -DestinationPath '!ZIP!' -Force"
echo.
echo ============================================================
echo  采集完成: !ZIP!
echo  请把这个 zip 发回给卖家（里面有 VBIOS 备份和全部硬件参数）。
echo  原始文件也留在 !W! （不删）。
echo ============================================================
if not defined NO_PAUSE pause