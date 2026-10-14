# 验证REBAR.ps1 — ReBAR EFI 试跑开机后的全量核对（只读 + OpenCL 基准）
# 由一次性任务计划「REBAR Verify (one-shot)」在登录后 2 分钟自动触发（也可手动管理员跑）
#   r8：名字里不能有 40HX —— Gen2 PostBind 每次开机会 /disable 名字命中 "40HX ThrottleStop 40HXUnlock" 的任务，
#   老名字「40HX ReBAR Verify」就是这么被静默禁用的（2026-10-12 本机实测，postbind.log 有实锤）。
# 输出：本目录 验证报告-latest.txt（另存一份带时间戳）；跑完自删任务
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rep = Join-Path $here ('验证报告-' + $stamp + '.txt')
$out = New-Object System.Collections.ArrayList
# 2026-10-12 r7 修复：原来每行只进内存列表（Tee-Object + Out-Null），运行时屏幕一个字都不打 →
#   看着像卡死（本机实测：用户以为窗口没反应）。现在同时打屏 + 进报告。
function W($s) { Write-Host ([string]$s); [void]$out.Add([string]$s) }
function Save { $out | Out-File -Encoding utf8 $rep; $out | Out-File -Encoding utf8 (Join-Path $here '验证报告-latest.txt') }

W ('=== 40HX ReBAR EFI 试跑验证报告  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ===')
W ''

# ---- [1] ESP 上的 40hx_log.txt（本次开机 EFI 日志） ----
W '== [1] EFI 日志（ESP:\40hx_log.txt） =='
$espLetter = $null
foreach ($dl in @('Y','X','W','V','U','T','S')) {
  if (-not (Test-Path ($dl + ':\'))) { mountvol ($dl + ':') /S 2>&1 | Out-Null; if (Test-Path ($dl + ':\EFI')) { $espLetter = $dl + ':'; break } }
}
$logAgeMin = -1
if ($espLetter -and (Test-Path ($espLetter + '\40hx_log.txt'))) {
  $fi = Get-Item ($espLetter + '\40hx_log.txt')
  $logAgeMin = [int]((Get-Date) - $fi.LastWriteTime).TotalMinutes
  W ('  日志时间: ' + $fi.LastWriteTime + '（' + $logAgeMin + ' 分钟前；应 <30 才是本次开机新写的）')
  $log = Get-Content ($espLetter + '\40hx_log.txt') -Raw
  # 中②修复：日志不新鲜 = 本次开机 EFI 根本没跑（读到的是旧日志）——全部判定作废
  $script:efiFresh = ($logAgeMin -ge 0 -and $logAgeMin -le 30)
  if ($null -eq $log) { $log = '' }
  if (-not $script:efiFresh) {
    W '  [!!] 日志不是本次开机的 —— ReBAR 版 EFI 没跑（BootNext 没生效/已过期），下面 EFI 相关判定全部无效'
    $log = ''
  }
  if ($script:efiFresh -and $log -ne '') {
  W ('  算力解锁: ' + $(if ($log -match 'UNLOCKED \(SS0=0x88888888') { '[OK] UNLOCKED' } else { '[!!] 未见 UNLOCKED' }))
  W ('  Gen2 预埋: ' + $(if ($log -match '\[efi-b\] prime done') { '[OK] 已执行（' + ([regex]::Match($log, '\[efi-b\] prime done.*')).Value + '）' } elseif ($log -match '\[efi-b\] skipped') { '[--] 跳过（未解锁才会这样）' } else { '[!!] 日志里没有 [efi-b] 行 —— 跑的不是新 EFI？' }))
  if ($log -match '\[rebar\] BAR1 8 GiB active @ (0x[0-9a-f]+)') {
    W ('  ReBAR:    [OK] BAR1 8 GiB active @ ' + $Matches[1])
  } elseif ($log -match '\[rebar\].*revert') {
    W ('  ReBAR:    [--] 触发回滚（' + ([regex]::Match($log, '\[rebar\][^\r\n]*revert[^\r\n]*')).Value + '）—— 未开启但系统安全')
  } elseif ($log -match '\[rebar\] skipped') {
    W ('  ReBAR:    [--] skipped（' + ([regex]::Match($log, '\[rebar\] skipped[^\r\n]*')).Value + '）')
  } else {
    W '  ReBAR:    [!!] 日志里没有 [rebar] 结果行'
  }
  }
  $script:efiLog = $log
} else {
  W '  [!!] ESP 挂载失败或没有 40hx_log.txt'
  $script:efiLog = ''
}
if ($espLetter) { mountvol $espLetter /D 2>&1 | Out-Null }

# ---- [2] BAR1 尺寸（nvidia-smi，GPU-Z 同款口径） ----
W ''
W '== [2] BAR1 尺寸（nvidia-smi -q） =='
$smi = "$env:SystemRoot\System32\nvidia-smi.exe"
$bar1 = $null
if (Test-Path $smi) {
  $q = (& $smi -q 2>&1 | Out-String)
  $m = [regex]::Match($q, '(?s)BAR1 Memory Usage.*?Total\s*:\s*(\d+)\s*MiB')
  if ($m.Success) {
    $bar1 = [int]$m.Groups[1].Value
    W ('  BAR1 Total = ' + $bar1 + ' MiB   ' + $(if ($bar1 -eq 8192) { '[OK] 8 GiB —— ReBAR 已开启' } elseif ($bar1 -eq 64) { '[--] 64 MiB —— 原生（ReBAR 未生效/已回滚）' } else { '[?] 非常见值' }))
  } else { W '  [!!] 没解析到 BAR1 Memory Usage' }
  W ('  ' + ((& $smi --query-gpu=name,driver_version,vbios_version,pcie.link.gen.current,pcie.link.gen.max --format=csv,noheader 2>&1 | Out-String).Trim()))
} else { W '  [!!] nvidia-smi 不存在' }

# ---- [3] 设备管理器状态（Code 43 检查） ----
W ''
W '== [3] 设备状态 =='
try {
  $dev = Get-PnpDevice -ErrorAction Stop | Where-Object { $_.DeviceId -match 'DEV_1F0B' } | Select-Object -First 1
  if ($dev) {
    $code = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue).Data
    W ('  ' + $dev.FriendlyName + '  Status=' + $dev.Status + '  ProblemCode=' + $(if ($null -eq $code) { '0' } else { $code }) + $(if (($null -eq $code) -or $code -eq 0) { '  [OK]' } else { '  [!!] 有问题（43=驱动没起来）' }))
  } else { W '  [!!] 找不到 DEV_1F0B 设备' }
} catch { W ('  [!!] 设备查询失败: ' + $_.Exception.Message) }

# ---- [4] Gen2 落地（开机 PostBind 任务日志） ----
W ''
W '== [4] Gen2（retrain-last.log） =='
$gl = 'C:\ProgramData\CMP40HXGen2\windows\logs\retrain-last.log'
if (Test-Path $gl) {
  $g = Get-Content $gl -Raw
  $fresh = [int]((Get-Date) - (Get-Item $gl).LastWriteTime).TotalMinutes
  W ('  日志时间: ' + (Get-Item $gl).LastWriteTime + '（' + $fresh + ' 分钟前）')
  if ($g -match 'PASS:\s*(already\s+)?physical Gen2 x16') { W '  [OK] 物理 Gen2 x16 在线（预埋生效，无回归）' }
  elseif ($g -match 'EXIT=14|baseline') { W '  [!!] baseline 不匹配 —— Gen2 预埋没生效（回归！）' }
  else { W ('  [?] 未见 PASS 行，末尾摘录: ' + (($g -split "`r?`n" | Select-Object -Last 3) -join ' | ')) }
} else { W '  [--] retrain-last.log 不存在（开机任务还没跑？）' }

# ---- [5] 自家自检包（主项目 40hx-oneclick\状态自检.bat；只读，不加载任何驱动） ----
# 2026-10-12 r7 修复（替换原厂商 OpenCL.exe 那步）：
#   ① 厂商 OpenCL.exe 末行是 "Done. Press Enter to exit."，脚本里直接 & 调用会永久挂起等回车（本机实测）。
#   ② 它的 PCIe 行是 "PCIe   Bandwidth"（多个空格），原正则 'PCIe Bandwidth' 抓不到 → 报告里从来没出现过链路那行。
#   ③ 自检包结尾是 "按任意键退出"，所以 stdin 必须重定向（< nul 等价物：-RedirectStandardInput），否则同样挂住。
#   可用环境变量 U40X_SELFCHECK 覆盖自检包路径；找不到就跳过（告警+继续，不中断报告）。
$scPkg = Join-Path $here '状态自检.bat'   # 2026-10-14 并入主线：自检包与本脚本同目录（原为作者机写死路径）
if ($env:U40X_SELFCHECK) { $scPkg = $env:U40X_SELFCHECK }
W ''
W '== [5] 自家自检包（状态自检.bat） =='
if (-not (Test-Path $scPkg)) {
  W ('  [--] 没找到自检包，跳过: ' + $scPkg)
} else {
  W ('  自检包: ' + $scPkg)
  $scLog = Join-Path $here ('自检包-输出-' + $stamp + '.txt')
  $scIn  = Join-Path $here ('自检包-stdin-' + $stamp + '.txt')
  try { Set-Content -Path $scIn -Value '' -Encoding ascii -ErrorAction Stop } catch { }
  try {
    # r7b（DSH 审查 Q4）：-Wait 没有超时兜底 → 自检包若卡住会把整份报告一起拖死。
    #   改为 -PassThru + WaitForExit(150s)，超时就杀掉并继续出报告（重定向到文件，不会阻塞管道）。
    $sp = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', ('"' + $scPkg + '"')) -NoNewWindow -PassThru `
          -RedirectStandardInput $scIn -RedirectStandardOutput $scLog -RedirectStandardError ($scLog + '.err') -ErrorAction Stop
    if (-not $sp.WaitForExit(150000)) {
      # r7b2（DSH 审查中级项）：Process.Kill() 在 .NET Framework 只杀 cmd.exe 本身，不杀子进程树
      #   （自检包会再起 csc.exe / 带宽测试进程）→ 用 taskkill /T 连树一起杀，Kill 只作兜底。
      try {
        $tk = (& taskkill /T /F /PID $sp.Id 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { W ('  [注意] taskkill 未成功（exit=' + $LASTEXITCODE + '）：' + ($tk -replace "`r?`n", ' | ')) }
      } catch { W ('  [注意] taskkill 调用异常: ' + $_.Exception.Message) }
      try { if (-not $sp.HasExited) { $sp.Kill() } } catch { }
      W '  [!!] 自检包 150 秒没退出（疑似等按键/挂起），已尝试终止（taskkill /T + Kill 兜底）—— 报告继续，看完整输出文件'
    } else {
      W ('  自检包退出码 = ' + $sp.ExitCode)
    }
  } catch { W ('  [!!] 自检包调用失败: ' + $_.Exception.Message) }
  if (Test-Path $scLog) {
    # r7b（DSH 审查低级项）：① stderr 也并进来，别让关键行落在没读的那个文件里；
    #   ② 编码兜底：自检包是 GBK 输出，若哪天改成 UTF-8，按 ANSI 读会全漏 → 先按默认读，
    #      摘不到关键行就按 UTF-8 重读一遍再摘。
    $scl = @(Get-Content $scLog -ErrorAction SilentlyContinue)
    $scErr = $scLog + '.err'
    if (Test-Path $scErr) { $scl += @(Get-Content $scErr -ErrorAction SilentlyContinue) }
    W ('  完整输出: ' + $scLog + '（' + $scl.Count + ' 行，已并入 stderr）')
    $pat = '算力|链路|VERDICT|结论|满血|锁定|Gen2|Gen1|TFLOP|带宽|BIOPs|TIOPs|\[!!\]|\[NG\]'
    $hit = 0
    foreach ($line in $scl) {
      if ($line -match $pat) {
        W ('  ' + $line.Trim()); $hit++
        if ($hit -ge 30) { break }
      }
    }
    if ($hit -eq 0) {
      $scl = @(Get-Content $scLog -Encoding UTF8 -ErrorAction SilentlyContinue)
      foreach ($line in $scl) {
        if ($line -match $pat) { W ('  ' + $line.Trim()); $hit++; if ($hit -ge 30) { break } }
      }
      if ($hit -gt 0) { W '  （上面是按 UTF-8 重读摘到的 —— 说明自检包输出了 UTF-8）' }
    }
    if ($hit -eq 0) { W '  [!!] 没摘到关键行 —— 看完整输出文件（若输出全乱码，是编码不匹配）' }
  } else { W '  [!!] 自检包没有任何输出文件产出' }
}

# ---- 总结 ----
W ''
W '== 结论 =='
$unlockOk = $script:efiLog -match 'UNLOCKED \(SS0=0x88888888'
$primeOk  = $script:efiLog -match '\[efi-b\] prime done'
$rebarOk  = ($bar1 -eq 8192)
$rebarReverted = ($script:efiLog -match '\[rebar\].*revert') -or ($bar1 -eq 64)
if (-not $script:efiFresh -or $script:efiLog -eq '') { W '  [!!] 本次开机 EFI 日志缺失或不新鲜 —— 无法判定（先确认 BootNext 是否真跑了：NVRAM/启动项/冻结哈希门禁）' }
elseif (-not $unlockOk) { W '  [!!] 算力没解锁 —— 先把 ESP 日志发回来分析（但这次只是 BootNext 一次性，下次开机自动恢复原 EFI）' }
elseif (-not $primeOk) { W '  [!!] 解锁成功但 Gen2 预埋没跑 —— 回归！发日志回来' }
elseif ($rebarOk) { W '  [全绿] 算力 + Gen2 预埋 + ReBAR 8 GiB 全部在线。下次正常开机会回到原 EFI（64 MiB）；要长期开启再说' }
elseif ($rebarReverted) { W '  [安全回滚] 算力/Gen2 正常，ReBAR 没开成（EFI 已整体回滚，系统无风险）—— 日志里有原因' }
else { W '  [?] 状态不明 —— 把本报告和 ESP 日志发回来' }
W ''
W ('报告文件: ' + $rep)
Save

# 跑完自删一次性任务（r8：新名字 + 老名字残留）
schtasks /delete /tn 'REBAR Verify (one-shot)' /f 2>&1 | Out-Null
schtasks /delete /tn '40HX ReBAR Verify' /f 2>&1 | Out-Null
