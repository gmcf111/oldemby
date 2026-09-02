param(
    [string]$iPadIP = "192.168.1.x",
    [string]$iPadUser = "root",
    [string]$iPadPassword = "",
    [string]$BuildType = "release"
)

$ErrorActionPreference = "Stop"
$BuildDir = $PSScriptRoot
$TempDir = Join-Path $BuildDir "temp"

# 清理临时目录
if (Test-Path $TempDir) {
    Remove-Item -Recurse -Force $TempDir
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

Write-Host "=== OldEmby iPad 2 部署脚本 ===" -ForegroundColor Cyan
Write-Host ""

# 步骤 1: 触发 GitHub Actions 构建
Write-Host "[1/5] 触发 GitHub Actions 构建..." -ForegroundColor Yellow
$run = gh workflow run build.yml -f build_type=$BuildType --json databaseId,conclusion -r "gmcf111/oldemby" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "触发构建失败: $run" -ForegroundColor Red
    exit 1
}

# 获取刚触发的运行 ID
Start-Sleep -Seconds 3
$runId = gh run list --workflow build.yml --limit 1 --json databaseId -r "gmcf111/oldemby" | ConvertFrom-Json | Select-Object -First 1 -ExpandProperty databaseId

if (-not $runId) {
    Write-Host "无法获取构建运行 ID" -ForegroundColor Red
    exit 1
}

Write-Host "  构建已触发，Run ID: $runId" -ForegroundColor Green

# 步骤 2: 等待构建完成
Write-Host "[2/5] 等待构建完成（最多 15 分钟）..." -ForegroundColor Yellow
$timeout = 900
$elapsed = 0
$interval = 15

while ($elapsed -lt $timeout) {
    $status = gh run view $runId --json status,conclusion -r "gmcf111/oldemby" 2>&1 | ConvertFrom-Json

    if ($status.status -eq "completed") {
        if ($status.conclusion -eq "success") {
            Write-Host "  构建成功!" -ForegroundColor Green
            break
        } else {
            Write-Host "  构建失败: $($status.conclusion)" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "  等待中... ($elapsed/$timeout 秒)" -ForegroundColor Gray
    Start-Sleep -Seconds $interval
    $elapsed += $interval
}

if ($elapsed -ge $timeout) {
    Write-Host "  构建超时" -ForegroundColor Red
    exit 1
}

# 步骤 3: 下载构建产物
Write-Host "[3/5] 下载构建产物..." -ForegroundColor Yellow
$artifactDir = Join-Path $TempDir "artifact"
New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null

$downloadResult = gh run download $runId -D $artifactDir -r "gmcf111/oldemby" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "下载失败: $downloadResult" -ForegroundColor Red
    exit 1
}

# 查找 IPA 文件
$ipaFile = Get-ChildItem -Path $artifactDir -Filter "*.ipa" -Recurse | Select-Object -First 1

if (-not $ipaFile) {
    Write-Host "  未找到 IPA 文件" -ForegroundColor Red
    exit 1
}

Write-Host "  找到 IPA: $($ipaFile.Name)" -ForegroundColor Green

# 复制 IPA 到 Build 目录
$ipaDest = Join-Path $BuildDir $ipaFile.Name
Copy-Item $ipaFile.FullName $ipaDest -Force
Write-Host "  IPA 已保存到: $ipaDest" -ForegroundColor Green

# 步骤 4: 通过 SSH 传输到 iPad
Write-Host "[4/5] 传输到 iPad 2..." -ForegroundColor Yellow

if ($iPadIP -eq "192.168.1.x") {
    Write-Host "  错误: 请先配置 iPad IP 地址" -ForegroundColor Red
    Write-Host "  使用方法: .\deploy.ps1 -iPadIP '192.168.1.100'" -ForegroundColor Yellow
    exit 1
}

# 使用 scp 传输文件
$remotePath = "$iPadUser@$iPadIP`:/tmp/"
Write-Host "  传输到 $remotePath ..."

if ($iPadPassword) {
    # 使用 sshpass (需要安装) 或 plink
    Write-Host "  注意: 建议配置 SSH 密钥认证" -ForegroundColor Yellow
    Write-Host "  尝试使用 scp 传输..." -ForegroundColor Gray
}

scp $ipaFile.FullName $remotePath
if ($LASTEXITCODE -ne 0) {
    Write-Host "  传输失败" -ForegroundColor Red
    exit 1
}

Write-Host "  文件已传输" -ForegroundColor Green

# 步骤 5: 在 iPad 上安装
Write-Host "[5/5] 在 iPad 上安装..." -ForegroundColor Yellow
$installCmd = "dpkg -i /tmp/$($ipaFile.Name)"
ssh "$iPadUser@$iPadIP" $installCmd
if ($LASTEXITCODE -ne 0) {
    Write-Host "  安装失败" -ForegroundColor Red
    exit 1
}

Write-Host "  安装完成!" -ForegroundColor Green

# 清理临时文件
Write-Host ""
Write-Host "清理临时文件..." -ForegroundColor Gray
Remove-Item -Recurse -Force $TempDir
ssh "$iPadUser@$iPadIP" "rm /tmp/$($ipaFile.Name)"
Remove-Item $ipaDest -Force

Write-Host ""
Write-Host "=== 部署完成! ===" -ForegroundColor Green
Write-Host "OldEmby 已成功安装到您的 iPad 2" -ForegroundColor Cyan
