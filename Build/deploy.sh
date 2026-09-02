#!/bin/bash
# OldEmby iPad 2 自动部署脚本
# 用法: ./deploy.sh [选项]
# 选项:
#   -i IP        iPad IP 地址 (必填)
#   -u USER      SSH 用户名 (默认: root)
#   -p PASSWORD  SSH 密码 (可选，建议用密钥)
#   -t TYPE      构建类型: release 或 debug (默认: release)

set -e

# 默认值
IPAD_IP=""
IPAD_USER="root"
IPAD_PASS=""
BUILD_TYPE="release"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_DIR="$BUILD_DIR/temp"
REPO="gmcf111/oldemby"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 解析参数
while getopts "i:u:p:t:" opt; do
    case $opt in
        i) IPAD_IP="$OPTARG" ;;
        u) IPAD_USER="$OPTARG" ;;
        p) IPAD_PASS="$OPTARG" ;;
        t) BUILD_TYPE="$OPTARG" ;;
        *) echo "用法: $0 [-i IP] [-u USER] [-p PASSWORD] [-t TYPE]"; exit 1 ;;
    esac
done

# 验证必填参数
if [ -z "$IPAD_IP" ]; then
    echo -e "${RED}错误: 请提供 iPad IP 地址${NC}"
    echo "用法: $0 -i 192.168.1.100"
    exit 1
fi

# 清理并创建临时目录
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo -e "${CYAN}=== OldEmby iPad 2 部署脚本 ===${NC}"
echo ""

# 步骤 1: 触发 GitHub Actions 构建
echo -e "${YELLOW}[1/5] 触发 GitHub Actions 构建...${NC}"
gh workflow run build.yml -f build_type=$BUILD_TYPE -r "$REPO"
sleep 3

# 获取刚触发的运行 ID
RUN_ID=$(gh run list --workflow build.yml --limit 1 --json databaseId -r "$REPO" | jq -r '.[0].databaseId')

if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
    echo -e "${RED}无法获取构建运行 ID${NC}"
    exit 1
fi

echo -e "${GREEN}  构建已触发，Run ID: $RUN_ID${NC}"

# 步骤 2: 等待构建完成
echo -e "${YELLOW}[2/5] 等待构建完成（最多 15 分钟）...${NC}"
gh run watch $RUN_ID -r "$REPO"

# 步骤 3: 下载构建产物
echo -e "${YELLOW}[3/5] 下载构建产物...${NC}"
ARTIFACT_DIR="$TEMP_DIR/artifact"
mkdir -p "$ARTIFACT_DIR"
gh run download $RUN_ID -D "$ARTIFACT_DIR" -r "$REPO"

# 查找 IPA 文件
IPA_FILE=$(find "$ARTIFACT_DIR" -name "*.ipa" | head -1)

if [ -z "$IPA_FILE" ]; then
    echo -e "${RED}  未找到 IPA 文件${NC}"
    exit 1
fi

IPA_NAME=$(basename "$IPA_FILE")
echo -e "${GREEN}  找到 IPA: $IPA_NAME${NC}"

# 复制 IPA 到 Build 目录
cp "$IPA_FILE" "$BUILD_DIR/"
echo -e "${GREEN}  IPA 已保存到: $BUILD_DIR/$IPA_NAME${NC}"

# 步骤 4: 通过 SSH 传输到 iPad
echo -e "${YELLOW}[4/5] 传输到 iPad 2 ($IPAD_IP)...${NC}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if [ -n "$IPAD_PASS" ]; then
    # 使用 sshpass (需要安装: brew install sshpass)
    sshpass -p "$IPAD_PASS" scp $SSH_OPTS "$IPA_FILE" "${IPAD_USER}@${IPAD_IP}:/tmp/"
else
    scp $SSH_OPTS "$IPA_FILE" "${IPAD_USER}@${IPAD_IP}:/tmp/"
fi

echo -e "${GREEN}  文件已传输${NC}"

# 步骤 5: 在 iPad 上安装
echo -e "${YELLOW}[5/5] 在 iPad 上安装...${NC}"

if [ -n "$IPAD_PASS" ]; then
    sshpass -p "$IPAD_PASS" ssh $SSH_OPTS "${IPAD_USER}@${IPAD_IP}" "dpkg -i /tmp/$IPA_NAME"
else
    ssh $SSH_OPTS "${IPAD_USER}@${IPAD_IP}" "dpkg -i /tmp/$IPA_NAME"
fi

echo -e "${GREEN}  安装完成!${NC}"

# 清理临时文件
echo ""
echo -e "${GRAY}清理临时文件...${NC}"
rm -rf "$TEMP_DIR"

if [ -n "$IPAD_PASS" ]; then
    sshpass -p "$IPAD_PASS" ssh $SSH_OPTS "${IPAD_USER}@${IPAD_IP}" "rm /tmp/$IPA_NAME"
else
    ssh $SSH_OPTS "${IPAD_USER}@${IPAD_IP}" "rm /tmp/$IPA_NAME"
fi

rm -f "$BUILD_DIR/$IPA_NAME"

echo ""
echo -e "${GREEN}=== 部署完成! ===${NC}"
echo -e "${CYAN}OldEmby 已成功安装到您的 iPad 2${NC}"
