@echo off
setlocal EnableExtensions
chcp 936 >nul
cd /d "%~dp0"
title CMP 40HX 一键解锁（算力 + Gen2 + ReBAR）
rem ============================================================================
rem 一键解锁40HX.bat —— 本包**唯一入口**（2026-10-14：原 一键安装.cmd 已并进这里）
rem   双击它 = 先只读体检 → 打印推荐项 + 要先去改的设置项 → 再问你要做哪个
rem   也可带参直跑（跳过菜单）：一键解锁40HX.bat 1（或 2 / 3 / f / r / u，末尾可加 force）
rem   实现脚本：同目录 一键解锁40HX.ps1（本 .bat 只负责提权、参数透传与结果文案）
rem ============================================================================

rem ---- 前置检查：单行 + 末尾标号，避免括号块在「目录名含 ) 或 &」时炸掉 ----
if not exist "%~dp0一键解锁40HX.ps1" goto nops1

rem 已提权的那一份带 elevated 标记：先把标记吃掉，后面参数解析才能拿到用户原本的参数
if /i "%~1"=="elevated" shift
rem fltmc 不依赖 Server 服务（net session 在精简系统上会把管理员误判成非管理员，多弹一次 UAC）
fltmc >nul 2>&1
if errorlevel 1 net session >nul 2>&1
if errorlevel 1 goto elevate
goto run

:elevate
echo ============================================================
echo   CMP 40HX 一键解锁（算力 + Gen2 + ReBAR 8 GiB 可选）
echo ============================================================
echo   [*] 正在申请管理员权限：会弹 UAC，然后在新的窗口里继续（先体检、再给推荐、最后问你）
rem 2026-10-12（参考 Cyridd/cmpunlocker FORK_CHANGES #2）：提权命令不把路径嵌进命令串——路径含单引号会截断；
rem   改走环境变量 HXSELF：由**未提权**的 powershell 展开成字面量路径再交给 ShellExecuteEx（真机 UAC 通过）。
set "HXSELF=%~f0"
powershell -NoProfile -Command "Start-Process -FilePath $env:HXSELF -ArgumentList elevated %* -Verb RunAs"
exit /b 0

:run
set "ARG="
if /i "%~1"=="1" set "ARG=-Choice 1"
if /i "%~1"=="2" set "ARG=-Choice 2"
if /i "%~1"=="3" set "ARG=-Choice 3"
if /i "%~1"=="f" set "ARG=-Choice force"
if /i "%~1"=="force" set "ARG=-Choice force"
if /i "%~1"=="r" set "ARG=-Choice check"
if /i "%~1"=="check" set "ARG=-Choice check"
if /i "%~1"=="u" set "ARG=-Choice undo"
if /i "%~1"=="undo" set "ARG=-Choice undo"
if /i "%~1"=="force" set "ARG=%ARG% -Force"
if /i "%~2"=="force" set "ARG=%ARG% -Force"
echo ============================================================
echo   一键解锁 40HX —— 先只读体检（不碰硬件），再给推荐与菜单
echo ============================================================
echo   [*] 开始（首次约 1 分钟；中途请别关窗口）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0一键解锁40HX.ps1" %ARG%
set "RC=%ERRORLEVEL%"
echo.
echo 退出码 = %RC%   (0 = 步骤全部成功)
if "%RC%"=="0" goto ok
if "%RC%"=="6" goto userquit
if "%RC%"=="-196608" goto nops1
if "%RC%"=="196608" goto nops1
goto runfail

:ok
echo.
rem 本次做了什么 → 看 ps1 落的 一键解锁40HX-上次退出码.txt 里的 state=
rem   判不出来（文件缺失 / 没有 exit=0 行）一律按"装过"处理 -> 宁可多提示一次【完全关机】，也不能把装过的当只读放过
set "SF=%~dp0一键解锁40HX-上次退出码.txt"
set "ST="
if not exist "%SF%" goto ok-install
for /f "tokens=2 delims= " %%s in ('findstr /b /c:"exit=0" "%SF%" 2^>nul') do set "ST=%%s"
if not defined ST goto ok-install
echo %ST%| findstr /i /c:"state=check-only" >nul 2>&1
if not errorlevel 1 goto ok-readonly
echo %ST%| findstr /i /c:"user-go-bios" >nul 2>&1
if not errorlevel 1 goto ok-readonly
echo %ST%| findstr /i /c:"user-abort" >nul 2>&1
if not errorlevel 1 goto ok-readonly
echo %ST%| findstr /i /c:"state=undo" >nul 2>&1
if not errorlevel 1 goto ok-undo
goto ok-install

:ok-install
echo ============================================================
echo   安装类选项做完后：请【完全关机】再开机（必须，不是重启）
echo   算力解锁靠每次开机的解锁固件生效；重启清不掉显卡残留状态，
echo   残留状态不对 = 开机黑屏一段时间 + 设备管理器 代码 43。
echo   做法：开始菜单-关机，最好拔电 10 秒再开机；开机后双击 状态自检.bat 看结论。
echo   上面若列了"重启前请先处理"的事项，请先处理再重启；回滚见 文档\使用说明-详细.md。
echo ============================================================
echo.
goto runend
:ok-readonly
echo ============================================================
echo   本次没有任何改动（只体检 / 你先去 BIOS 改设置项 / 在告警处选择了放弃）
echo   —— 直接关窗口即可；改完或想好了回来重跑本入口，它会重新体检、再给推荐。
echo ============================================================
echo.
goto runend
:ok-undo
echo ============================================================
echo   本次做的是撤销：已切回主线 EFI，并删掉 ReBAR 启动项与文件。
echo   按上面提示重启一次即可（这次重启不需要"完全关机"）。
echo ============================================================
echo.
goto runend
:userquit
echo.
echo ============================================================
echo   已按你的选择退出（批次预检：锁死批次）—— 没有安装 EFI/启动项/开机任务，
echo   开机时不会有任何本包动作，机器保持原样可用。详见上方说明。
echo ============================================================
echo.
goto runend
:runfail
echo.
echo [X] 没有全部成功（退出码 %RC%）—— 别急着关机，先看上面 [失败] 行
echo     把本窗口截图和 logs 目录里最新的文件发给技术；自查：打开 排查指引.md 按退出码/日志原话索引
echo.
goto runend

:runend
if exist "%~dp0一键解锁40HX-上次退出码.txt" type "%~dp0一键解锁40HX-上次退出码.txt"
echo.
if not "%NO_PAUSE%"=="1" pause
exit /b %RC%

:nops1
echo ============================================================
echo   [注意] 没能开始：PowerShell 没有读到 一键解锁40HX.ps1
echo.
echo   退出码 -196608 就是十六进制 0xFFFD0000 —— 这是 PowerShell 自己
echo   "脚本没能跑起来"的错误码，不是安装脚本报的错。也就是说下面这些
echo   一件都还没做：没改注册表、没写驱动、没动启动项、没改引导。
echo.
echo   常见原因，按可能性排序：
echo     1. 直接从压缩包里双击运行 —— 请先把 zip 完整解压到一个文件夹再运行
echo     2. 杀软把 一键解锁40HX.ps1 删了或隔离了（请到隔离区恢复，并把本目录加进信任区）
echo     3. 只把 一键解锁40HX.bat 拷了出来 —— 请整包拷贝
echo     4. 包放在映射的网络盘或共享目录上，提权后读不到 —— 请拷到本机硬盘
echo.
echo   正确解压后，本目录里应当能看到：
echo     一键解锁40HX.bat   一键解锁40HX.ps1   Install-40HXUnlock.ps1   payload   文档
echo   当前目录（可截图发回）
echo      "%~dp0"
echo.
echo   详细处置见 文档\给客户-安装退出码196608-怎么办.txt
echo ============================================================
if not "%NO_PAUSE%"=="1" pause >nul
exit /b 1
