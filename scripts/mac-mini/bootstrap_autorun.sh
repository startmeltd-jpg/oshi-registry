#!/usr/bin/env bash
# ============================================================
# OSHI Jr. ブートストラップスクリプト v1.0
# ============================================================
# 用途: 自動実行システムを一発でセットアップし、
#       fix_zshrc / install_arp / install_mirofish を
#       ゆーだが何もしなくても自動実行する仕組みを構築する
#
# OSHI Jr.がこのスクリプトを1回だけ実行すれば完了。
# ゆーだはターミナルに触れない。
#
# 実行方法（OSHI Jr.が実行）:
#   curl -fsSL https://raw.githubusercontent.com/startmeltd-jpg/oshi-core/main/scripts/mac-mini/bootstrap_autorun.sh | bash
#
# 作成: OSHI (2026-03-10)
# ============================================================

set -euo pipefail

GITHUB_RAW="https://raw.githubusercontent.com/startmeltd-jpg/oshi-core/main/scripts/mac-mini"
OSHI_JR_DIR="/Users/nagatayuudai/oshi_jr"
SCRIPTS_DIR="$OSHI_JR_DIR/scripts/mac-mini"
LOG_DIR="$OSHI_JR_DIR/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$SCRIPTS_DIR" "$LOG_DIR"

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  OSHI Jr. ブートストラップ開始${NC}"
echo -e "${BLUE}  ゆーだの作業ゼロ原則 — 全自動セットアップ${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# Step 1: 自動実行トリガースクリプトをダウンロード
echo -e "${CYAN}[1/3] 自動実行システムをダウンロード中...${NC}"
curl -fsSL "$GITHUB_RAW/oshi_jr_autorun.sh" -o "$SCRIPTS_DIR/oshi_jr_autorun.sh"
chmod +x "$SCRIPTS_DIR/oshi_jr_autorun.sh"
echo -e "${GREEN}  ダウンロード完了: oshi_jr_autorun.sh${NC}"

# Step 2: 3スクリプトをダウンロード
echo -e "${CYAN}[2/3] 実行スクリプトをダウンロード中...${NC}"
for script in fix_zshrc.sh install_arp.sh install_mirofish.sh; do
    curl -fsSL "$GITHUB_RAW/$script" -o "$SCRIPTS_DIR/$script"
    chmod +x "$SCRIPTS_DIR/$script"
    echo -e "${GREEN}  ダウンロード完了: $script${NC}"
done

# Step 3: 自動実行システムをインストール（LaunchAgent + キュー追加）
echo -e "${CYAN}[3/3] 自動実行システムをインストール中...${NC}"
bash "$SCRIPTS_DIR/oshi_jr_autorun.sh" --install

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  ブートストラップ完了！${NC}"
echo -e "${GREEN}  fix_zshrc / install_arp / install_mirofish は${NC}"
echo -e "${GREEN}  次の5分以内に自動実行されます。${NC}"
echo -e "${GREEN}  ゆーだは何もしなくて大丈夫です。${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "ログ確認: ls $LOG_DIR/"
echo "状態確認: launchctl list | grep oshi"
echo ""
