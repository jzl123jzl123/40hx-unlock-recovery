@echo off
rem 40HX ReBAR 一次性试跑（主线包内；BootNext 只生效一次，不动启动顺序）
rem 默认=部署+BootNext 试跑+注册开机验证任务； undo=撤掉
cd /d "%~dp0"
if not exist "%~dp0试跑REBAR.ps1" goto nops1
if "%1"=="elevated" goto elevated
net session >nul 2>&1
if "%errorlevel%"=="0" goto elevated
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated %*' -Verb RunAs"
exit /b 0
:elevated
set "ARG="
if /i "%1"=="undo" set "ARG=-Action undo"
if /i "%2"=="undo" set "ARG=-Action undo"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0试跑REBAR.ps1" %ARG%
set "RC=%ERRORLEVEL%"
echo.
echo 退出码: %RC%（0=正常；7=EFI/启动项已部署但"登录后自动验证任务"没注册成功 —— 试跑照旧，报告手动跑）
if exist "%~dp0试跑REBAR-上次退出码.txt" type "%~dp0试跑REBAR-上次退出码.txt"
if not "%NO_PAUSE%"=="1" pause
exit /b %RC%
:nops1
echo  [注意] 没找到 试跑REBAR.ps1（压缩包里直接运行？被杀软隔离？只拷了 cmd？）
echo 当前目录（可截图发回）：
echo      "%~dp0"
if not "%NO_PAUSE%"=="1" pause >nul
exit /b 1
