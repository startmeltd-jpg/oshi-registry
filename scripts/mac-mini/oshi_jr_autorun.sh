#!/usr/bin/env bash
# ============================================================
# OSHI Jr. 自動実行トリガー v1.0
# ============================================================
# 用途: ゆーだがターミナルを触らずに3スクリプトを自動実行する
# 仕組み:
#   1. このスクリプト自体をcronまたはpm2で管理
#   2. ~/oshi_jr/pending_tasks/ にトリガーファイルが存在すれば実行
#   3. 実行済みのトリガーはdoneフォルダに移動（再実行防止）
#
# インストール方法（OSHI Jr.が一度だけ実行）:
#   bash oshi_jr_autorun.sh --install
#
# 手動トリガー追加（Manus/OSHI Jr.が実行）:
#   bash oshi_jr_autorun.sh --queue fix_zshrc
#   bash oshi_jr_autorun.sh --queue install_arp
#   bash oshi_jr_autorun.sh --queue install_mirofish
#
# 作成: OSHI (2026-03-10)
# 核心原則: ゆーだの作業ゼロ原則
# ============================================================

set -euo pipefail

# --- 設定 ---
OSHI_JR_DIR="${OSHI_JR_DIR:-/Users/nagatayuudai/oshi_jr}"
SCRIPTS_DIR="$OSHI_JR_DIR/scripts/mac-mini"
PENDING_DIR="$OSHI_JR_DIR/pending_tasks"
DONE_DIR="$OSHI_JR_DIR/done_tasks"
LOG_DIR="$OSHI_JR_DIR/logs"
GITHUB_RAW="https://raw.githubusercontent.com/startmeltd-jpg/oshi-core/main/scripts/mac-mini"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/autorun_${TIMESTAMP}.log"

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ディレクトリ作成
mkdir -p "$PENDING_DIR" "$DONE_DIR" "$LOG_DIR" "$SCRIPTS_DIR"

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ============================================================
# --install モード: cronとpm2にこのスクリプトを登録
# ============================================================
if [[ "${1:-}" == "--install" ]]; then
    echo ""
    log "${BLUE}============================================================${NC}"
    log "${BLUE}  OSHI Jr. 自動実行トリガー インストール${NC}"
    log "${BLUE}============================================================${NC}"

    # このスクリプト自体を最新版でダウンロード
    log "${CYAN}[1/4] 最新スクリプトをダウンロード中...${NC}"
    curl -fsSL "$GITHUB_RAW/oshi_jr_autorun.sh" -o "$SCRIPTS_DIR/oshi_jr_autorun.sh" 2>/dev/null || \
        cp "$0" "$SCRIPTS_DIR/oshi_jr_autorun.sh"
    chmod +x "$SCRIPTS_DIR/oshi_jr_autorun.sh"
    log "${GREEN}  スクリプト配置: $SCRIPTS_DIR/oshi_jr_autorun.sh${NC}"

    # 3スクリプトもダウンロード
    log "${CYAN}[2/4] 実行対象スクリプトをダウンロード中...${NC}"
    for script in fix_zshrc.sh install_arp.sh install_mirofish.sh; do
        curl -fsSL "$GITHUB_RAW/$script" -o "$SCRIPTS_DIR/$script" 2>/dev/null
        chmod +x "$SCRIPTS_DIR/$script"
        log "${GREEN}  ダウンロード: $script${NC}"
    done

    # LaunchAgent（macOS推奨: cronより確実）を作成
    log "${CYAN}[3/4] LaunchAgent（自動起動）を設定中...${NC}"
    LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
    mkdir -p "$LAUNCH_AGENTS_DIR"
    PLIST_FILE="$LAUNCH_AGENTS_DIR/com.oshi.jr.autorun.plist"

    cat > "$PLIST_FILE" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.oshi.jr.autorun</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SCRIPTS_DIR}/oshi_jr_autorun.sh</string>
        <string>--run</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/autorun_launchagent.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/autorun_launchagent_error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Users/nagatayuudai/.local/bin</string>
        <key>HOME</key>
        <string>/Users/nagatayuudai</string>
        <key>OSHI_JR_DIR</key>
        <string>${OSHI_JR_DIR}</string>
    </dict>
</dict>
</plist>
PLIST

    # LaunchAgentをロード
    if launchctl load "$PLIST_FILE" 2>/dev/null; then
        log "${GREEN}  LaunchAgent登録完了: com.oshi.jr.autorun${NC}"
        log "${GREEN}  実行間隔: 5分ごと + ログイン時に即時実行${NC}"
    else
        log "${YELLOW}  LaunchAgent登録をスキップ（既に登録済みの可能性）${NC}"
        # アンロード→リロード
        launchctl unload "$PLIST_FILE" 2>/dev/null || true
        launchctl load "$PLIST_FILE" 2>/dev/null || true
        log "${GREEN}  LaunchAgent再登録完了${NC}"
    fi

    # pm2にも登録（pm2が使える場合）
    log "${CYAN}[4/4] pm2登録を試みます（オプション）...${NC}"
    if command -v pm2 &>/dev/null; then
        pm2 start "$SCRIPTS_DIR/oshi_jr_autorun.sh" \
            --name "oshi-jr-autorun" \
            --interpreter bash \
            --cron "*/5 * * * *" \
            --no-autorestart 2>/dev/null || true
        pm2 save 2>/dev/null || true
        log "${GREEN}  pm2登録完了: oshi-jr-autorun（5分ごと）${NC}"
    else
        log "${YELLOW}  pm2が見つかりません（LaunchAgentのみで運用）${NC}"
    fi

    # 初回の3スクリプトをキューに追加
    log ""
    log "${CYAN}初回実行タスクをキューに追加中...${NC}"
    touch "$PENDING_DIR/fix_zshrc.trigger"
    touch "$PENDING_DIR/install_arp.trigger"
    touch "$PENDING_DIR/install_mirofish.trigger"
    log "${GREEN}  キュー追加: fix_zshrc, install_arp, install_mirofish${NC}"
    log "${GREEN}  次の5分以内に自動実行されます${NC}"

    echo ""
    log "${GREEN}============================================================${NC}"
    log "${GREEN}  インストール完了！ゆーだは何もしなくて大丈夫です。${NC}"
    log "${GREEN}  3スクリプトは次の5分以内に自動実行されます。${NC}"
    log "${GREEN}============================================================${NC}"
    echo ""
    exit 0
fi

# ============================================================
# --queue モード: タスクをキューに追加
# ============================================================
if [[ "${1:-}" == "--queue" ]]; then
    TASK="${2:-}"
    if [[ -z "$TASK" ]]; then
        echo "使い方: $0 --queue <task_name>"
        echo "タスク名: fix_zshrc, install_arp, install_mirofish"
        exit 1
    fi
    TRIGGER_FILE="$PENDING_DIR/${TASK}.trigger"
    echo "{\"queued_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"task\": \"$TASK\"}" > "$TRIGGER_FILE"
    echo "キュー追加: $TASK → $TRIGGER_FILE"
    exit 0
fi

# ============================================================
# --run モード（デフォルト）: pendingタスクを実行
# ============================================================
log "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] OSHI Jr. 自動実行チェック開始${NC}"

# pendingタスクの確認
PENDING_COUNT=$(find "$PENDING_DIR" -name "*.trigger" 2>/dev/null | wc -l | tr -d ' ')

if [ "$PENDING_COUNT" -eq 0 ]; then
    log "  pendingタスクなし。スキップ。"
    exit 0
fi

log "${CYAN}  ${PENDING_COUNT} 件のpendingタスクを検出${NC}"

# 実行順序: fix_zshrc → install_arp → install_mirofish
TASK_ORDER=("fix_zshrc" "install_arp" "install_mirofish")

for task in "${TASK_ORDER[@]}"; do
    TRIGGER_FILE="$PENDING_DIR/${task}.trigger"

    if [ ! -f "$TRIGGER_FILE" ]; then
        continue
    fi

    log ""
    log "${CYAN}--- タスク実行: $task ---${NC}"

    # スクリプトの確認（なければダウンロード）
    SCRIPT_FILE="$SCRIPTS_DIR/${task}.sh"
    if [ ! -f "$SCRIPT_FILE" ]; then
        log "  スクリプトをダウンロード中: ${task}.sh"
        curl -fsSL "$GITHUB_RAW/${task}.sh" -o "$SCRIPT_FILE" 2>/dev/null
        chmod +x "$SCRIPT_FILE"
    fi

    # 実行前にdoneに移動（再実行防止）
    DONE_FILE="$DONE_DIR/${task}_${TIMESTAMP}.trigger"
    mv "$TRIGGER_FILE" "$DONE_FILE"

    # スクリプト実行
    TASK_LOG="$LOG_DIR/${task}_${TIMESTAMP}.log"
    log "  実行中: $SCRIPT_FILE"
    log "  ログ: $TASK_LOG"

    if bash "$SCRIPT_FILE" > "$TASK_LOG" 2>&1; then
        log "${GREEN}  [DONE] $task: 実行成功${NC}"
        echo "status=success" >> "$DONE_FILE"

        # Supabaseに結果を記録（可能な場合）
        python3 -c "
import os, json, urllib.request
from datetime import datetime

supabase_url = os.environ.get('SUPABASE_URL', '')
supabase_key = os.environ.get('SUPABASE_KEY', '')

if not supabase_url or not supabase_key:
    # .envから読み込み
    env_file = os.path.expanduser('~/oshi_jr/.env')
    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    k, v = line.strip().split('=', 1)
                    if k == 'SUPABASE_URL': supabase_url = v.strip()
                    if k == 'SUPABASE_KEY': supabase_key = v.strip()

if supabase_url and supabase_key:
    data = json.dumps({
        'content': f'OSHI Jr. 自動実行完了: $task',
        'category': 'system',
        'importance': 'medium',
        'tags': ['autorun', 'mac-mini', '$task'],
        'metadata': {
            'task': '$task',
            'status': 'success',
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'log_file': '$TASK_LOG'
        }
    }).encode()
    req = urllib.request.Request(
        f'{supabase_url}/rest/v1/amato_memories',
        data=data,
        headers={
            'apikey': supabase_key,
            'Authorization': f'Bearer {supabase_key}',
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal'
        },
        method='POST'
    )
    try:
        urllib.request.urlopen(req, timeout=10)
        print('Supabase記録: OK')
    except Exception as e:
        print(f'Supabase記録スキップ: {e}')
else:
    print('Supabase設定なし: スキップ')
" 2>/dev/null | tee -a "$LOG_FILE" || true

    else
        EXIT_CODE=$?
        log "${RED}  [FAIL] $task: 実行失敗 (exit code: $EXIT_CODE)${NC}"
        echo "status=failed&exit_code=$EXIT_CODE" >> "$DONE_FILE"
        log "${YELLOW}  ログ確認: $TASK_LOG${NC}"
    fi
done

log ""
log "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] 自動実行チェック完了${NC}"
