# Claude Desktop 中文一键安装/卸载启动器
# 封装 javaht/claude-desktop-zh-cn（已审查版本 75dbacd，见 payload\）：
# 先以当前用户身份把安装文件复制到本地临时目录（避免 U 盘/网络路径在管理员下不可见），
# 再申请管理员权限，非交互地执行简体中文安装或卸载。
param(
    [ValidateSet("install", "uninstall")]
    [string]$Action = "install",
    [switch]$Elevated,
    [string]$StagedScript = "",
    [string]$OriginalUserSid = "",
    [string]$OriginalUserProfile = "",
    [string]$OriginalAppData = "",
    [string]$OriginalLocalAppData = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$actionLabel = if ($Action -eq "install") { "安装" } else { "卸载" }

function Wait-Exit {
    param([int]$Code)
    Write-Host ""
    [void](Read-Host "按回车关闭此窗口")
    exit $Code
}

if (-not $Elevated) {
    Write-Host "=== Claude Desktop 简体中文一键$actionLabel ===" -ForegroundColor Cyan

    $payload = Join-Path $PSScriptRoot "payload"
    if (-not (Test-Path -LiteralPath (Join-Path $payload "scripts\install_windows.ps1"))) {
        Write-Host "安装包不完整：缺少 payload\scripts\install_windows.ps1，请重新解压整个文件夹。" -ForegroundColor Red
        Wait-Exit 1
    }

    $claude = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Claude*" -or $_.Publisher -like "*Anthropic*" })
    $unpackaged = Test-Path (Join-Path $env:LOCALAPPDATA "AnthropicClaude")
    if ($claude.Count -eq 0 -and -not $unpackaged) {
        Write-Host "没有检测到 Claude Desktop，请先从 https://claude.ai/download 安装并至少打开一次。" -ForegroundColor Red
        Wait-Exit 1
    }
    if ($claude.Count -gt 0) {
        Write-Host "检测到 Claude Desktop $($claude[0].Version)" -ForegroundColor DarkGray
    }

    $stage = Join-Path $env:TEMP "ClaudeZhCnOneClick"
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
    Copy-Item -LiteralPath $payload -Destination $stage -Recurse -Force
    $staged = Join-Path $stage "scripts\install_windows.ps1"
    # 管理员下 U 盘/网络映射盘可能不可见，所以提权后运行的是临时目录里的启动器副本
    $stagedLauncher = Join-Path $stage "launcher.ps1"
    Copy-Item -LiteralPath $PSCommandPath -Destination $stagedLauncher -Force

    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $quote = { param($v) '"' + ([string]$v).Replace('"', '\"') + '"' }
    $argList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", (& $quote $stagedLauncher),
        "-Action", $Action,
        "-Elevated",
        "-StagedScript", (& $quote $staged),
        "-OriginalUserSid", (& $quote $sid),
        "-OriginalUserProfile", (& $quote $env:USERPROFILE),
        "-OriginalAppData", (& $quote $env:APPDATA),
        "-OriginalLocalAppData", (& $quote $env:LOCALAPPDATA)
    ) -join " "

    Write-Host "正在申请管理员权限，请在弹窗中点「是」..." -ForegroundColor Yellow
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs -WorkingDirectory $stage
    }
    catch {
        Write-Host "没有获得管理员权限（可能点了「否」），什么都没有改动。" -ForegroundColor Red
        Wait-Exit 1
    }
    Write-Host "已在新的管理员窗口中继续，本窗口 5 秒后自动关闭。" -ForegroundColor Green
    Start-Sleep -Seconds 5
    exit 0
}

# 以下在管理员窗口中运行
Write-Host "=== Claude Desktop 简体中文一键$actionLabel（管理员）===" -ForegroundColor Cyan
Write-Host "Claude 会被关闭，完成后自动重新打开。" -ForegroundColor DarkGray
Write-Host ""

$params = @{
    Action               = $Action
    Language             = "zh-CN"
    OriginalUserSid      = $OriginalUserSid
    OriginalUserProfile  = $OriginalUserProfile
    OriginalAppData      = $OriginalAppData
    OriginalLocalAppData = $OriginalLocalAppData
}

$exitCode = 0
try {
    & $StagedScript @params
    $exitCode = $LASTEXITCODE
}
catch {
    Write-Host "[错误] $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "$actionLabel完成。" -ForegroundColor Green
    if ($Action -eq "install") {
        Write-Host "如果界面还是英文：左下角账号菜单 → Language → 简体中文。" -ForegroundColor Green
    }
}
else {
    Write-Host "$actionLabel没有成功。日志：$(Join-Path (Split-Path -Parent (Split-Path -Parent $StagedScript)) 'install-windows.log')" -ForegroundColor Red
    if ($Action -eq "install") {
        Write-Host "可以运行「一键卸载中文.bat」恢复原版。" -ForegroundColor Yellow
    }
}
Wait-Exit $exitCode
