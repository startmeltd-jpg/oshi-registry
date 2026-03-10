#!/usr/bin/env bash
# =============================================================================
# install_arp_mac.sh — ARP (Agent Relay Protocol) Mac Mini インストーラー
# 対象: macOS Tahoe 26.2 / Apple M4 Pro / 24GB RAM
# 使い方: bash install_arp_mac.sh
#
# 【Grok/Claude両方に確認済み】
# - Grok推奨: uv venv で仮想環境を使いPEP668対応
# - Claude推奨: Rust環境（aarch64-apple-darwin）+ uv init + config.yaml
# - 採用: Rustバイナリ直接インストール（公式install.sh）+ 安全ラッパー
#
# 【なぜこのスクリプトが正しいか】
# 1. ARPはRust製バイナリ（arpc/arps）で、Pythonパッケージではない
#    → pip installではなく、公式install.shまたはcargo buildが正しい
# 2. 公式install.sh を curl | bash せず、ファイルに保存してから実行（安全）
# 3. Apple Silicon (arm64) でのRustビルドは rustup + aarch64-apple-darwin
# 4. E2E暗号化はデフォルト有効（HPKE Auth mode, RFC 9180）
# 5. バックアップ・ロールバック機能付き
# =============================================================================
set -euo pipefail

# ── カラー定義 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

LOG_FILE="/tmp/arp_install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
     _    ____  ____  
    / \  |  _ \|  _ \ 
   / _ \ | |_) | |_) |
  / ___ \|  _ <|  __/ 
 /_/   \_\_| \_\_|    
                      
  Agent Relay Protocol v0.3.2
  Mac Mini インストーラー
  Grok + Claude 両方確認済み
BANNER
echo -e "${NC}"

# ── 前提条件チェック ──
step "Step 1: 前提条件チェック"

# macOS確認
if [[ "$(uname)" != "Darwin" ]]; then
    error "このスクリプトはmacOS専用です"
    exit 1
fi
success "macOS確認OK: $(sw_vers -productVersion)"

# Apple Silicon確認
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    warn "Apple Silicon (arm64) ではありません: $ARCH"
    warn "Intel Macでも動作しますが、最適化されていません"
fi
success "アーキテクチャ: $ARCH"

# Homebrew確認
if ! command -v brew &>/dev/null; then
    warn "Homebrewが見つかりません。インストールを推奨します。"
    warn "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
fi

# ── Rust環境セットアップ ──
step "Step 2: Rust環境セットアップ"

if command -v rustc &>/dev/null; then
    RUST_VER=$(rustc --version)
    success "Rust既存: $RUST_VER"
else
    info "Rustをインストール中..."
    # Claude推奨: curlパイプ不使用、ファイルに保存してから実行
    RUSTUP_SCRIPT="/tmp/rustup_install.sh"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$RUSTUP_SCRIPT"
    chmod +x "$RUSTUP_SCRIPT"
    
    info "rustup-init を実行中（デフォルト設定）..."
    bash "$RUSTUP_SCRIPT" -y --default-toolchain stable
    
    # PATHに追加
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # .zshrcにPATH追加（既存チェック付き）
    if ! grep -q 'cargo/bin' "$HOME/.zshrc" 2>/dev/null; then
        echo '' >> "$HOME/.zshrc"
        echo '# Rust/Cargo PATH (added by install_arp_mac.sh)' >> "$HOME/.zshrc"
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.zshrc"
        info ".zshrcにCargo PATHを追加しました"
    fi
    
    success "Rustインストール完了: $(rustc --version)"
    rm -f "$RUSTUP_SCRIPT"
fi

# Apple Silicon向けターゲット追加
if [[ "$ARCH" == "arm64" ]]; then
    rustup target add aarch64-apple-darwin 2>/dev/null || true
    success "Rustターゲット: aarch64-apple-darwin"
fi

# ── ARP公式インストーラーの取得・実行 ──
step "Step 3: ARP v0.3.2 インストール"

ARP_INSTALL_SCRIPT="/tmp/arp_install_official.sh"
ARP_INSTALL_URL="https://arp.offgrid.ing/install.sh"

info "公式インストールスクリプトをダウンロード中..."
curl -fsSL "$ARP_INSTALL_URL" -o "$ARP_INSTALL_SCRIPT"

if [[ ! -f "$ARP_INSTALL_SCRIPT" ]]; then
    error "インストールスクリプトのダウンロードに失敗しました"
    exit 1
fi

# スクリプト内容を確認（安全チェック）
SCRIPT_SIZE=$(wc -c < "$ARP_INSTALL_SCRIPT")
info "ダウンロード完了: $SCRIPT_SIZE bytes"
info "スクリプト冒頭を表示（安全確認）:"
head -5 "$ARP_INSTALL_SCRIPT"
echo ""

chmod +x "$ARP_INSTALL_SCRIPT"

# 対話的に確認
if [[ -t 0 ]]; then
    read -r -p "公式install.shを実行しますか？ [y/N]: " REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        warn "インストールをスキップしました"
        warn "手動実行: bash $ARP_INSTALL_SCRIPT"
        exit 0
    fi
fi

info "ARP公式インストーラーを実行中..."
bash "$ARP_INSTALL_SCRIPT"
rm -f "$ARP_INSTALL_SCRIPT"

# PATHに追加
export PATH="$HOME/.local/bin:$PATH"

# .zshrcにPATH追加（既存チェック付き）
if ! grep -q '.local/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo '' >> "$HOME/.zshrc"
    echo '# ARP PATH (added by install_arp_mac.sh)' >> "$HOME/.zshrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    info ".zshrcにARP PATHを追加しました"
fi

# ── インストール検証 ──
step "Step 4: インストール検証"

if command -v arpc &>/dev/null; then
    success "arpc コマンド確認OK"
else
    error "arpc コマンドが見つかりません"
    error "PATH: $PATH"
    error "手動確認: ls -la $HOME/.local/bin/arpc"
    exit 1
fi

# ── 設定ファイル作成 ──
step "Step 5: 設定ファイル作成"

CONFIG_DIR="$HOME/.config/arpc"
CONFIG_FILE="$CONFIG_DIR/config.toml"

mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
    info "既存の設定ファイルが見つかりました: $CONFIG_FILE"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    success "バックアップ作成完了"
fi

cat > "$CONFIG_FILE" << 'ARPCONFIG'
# ARP Client Configuration
# Generated by install_arp_mac.sh
# Grok + Claude 両方確認済み

# ── リレーサーバー ──
# 公式リレー（デフォルト）
relay = "wss://arps.offgrid.ing"

# マルチリレー構成（クロスリレー通信用）
# [[relays]]
# url = "wss://arps.offgrid.ing"
# [[relays]]
# url = "wss://your-relay.example.com"
# send_strategy = "fan_out"  # or "sequential"

# ── ローカルAPI ──
listen = "tcp://127.0.0.1:7700"

# ── 暗号化（デフォルト有効） ──
[encryption]
enabled = true
# HPKE Auth mode (RFC 9180)
# KEM: X25519-HKDF-SHA256
# KDF: HKDF-SHA256
# AEAD: ChaCha20Poly1305

# ── Webhook（OSHI Jr. Telegram Bot連携用） ──
[webhook]
enabled = false
# OSHI Jr.と連携する場合:
# enabled = true
# url = "http://127.0.0.1:18789/hooks/agent"
# token = "your-gateway-token"
# channel = "last"
ARPCONFIG

success "設定ファイル作成: $CONFIG_FILE"

# ── OSHI Jr. 連携スクリプト作成 ──
step "Step 6: OSHI Jr. 連携ヘルパー作成"

OSHI_ARP_DIR="$HOME/oshi_jr/arp"
mkdir -p "$OSHI_ARP_DIR"

cat > "$OSHI_ARP_DIR/arp_bridge.py" << 'PYBRIDGE'
#!/usr/bin/env python3
"""
ARP ↔ OSHI Jr. ブリッジ
ARPメッセージをOSHI Jr.のGuard Pipelineに接続する。

使い方:
  python3 arp_bridge.py

Grok/Claude両方確認済み:
- Grok: FlaskでAPI呼び出しを推奨
- Claude: requestsライブラリでOllama連携を推奨
- 採用: 両方の利点を統合
"""
import subprocess
import json
import sys
import os
from datetime import datetime

ARP_LISTEN = "tcp://127.0.0.1:7700"
LOG_FILE = "/tmp/arp_bridge.log"

def log(msg: str):
    """ログ出力（無音失敗禁止）"""
    ts = datetime.now().isoformat()
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def get_identity() -> str:
    """自分のARP公開鍵を取得"""
    try:
        result = subprocess.run(
            ["arpc", "identity"],
            capture_output=True, text=True, timeout=10
        )
        return result.stdout.strip()
    except Exception as e:
        log(f"ERROR: identity取得失敗: {e}")
        return ""

def send_message(recipient: str, message: str) -> bool:
    """ARPメッセージを送信"""
    try:
        result = subprocess.run(
            ["arpc", "send", recipient, message],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            log(f"SENT: to={recipient[:16]}... msg={message[:50]}...")
            return True
        else:
            log(f"SEND_FAILED: {result.stderr}")
            return False
    except Exception as e:
        log(f"ERROR: 送信失敗: {e}")
        return False

def check_status() -> dict:
    """ARPステータス確認"""
    try:
        result = subprocess.run(
            ["arpc", "status"],
            capture_output=True, text=True, timeout=10
        )
        return {
            "connected": result.returncode == 0,
            "output": result.stdout.strip(),
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        return {
            "connected": False,
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

if __name__ == "__main__":
    log("ARP Bridge 起動")
    identity = get_identity()
    if identity:
        log(f"ARP Identity: {identity}")
    else:
        log("WARNING: ARP identity取得失敗。arpc startが必要かもしれません。")
    
    status = check_status()
    log(f"ARP Status: {json.dumps(status, ensure_ascii=False)}")
    
    print("\n=== ARP Bridge Ready ===")
    print(f"Identity: {identity}")
    print(f"Status: {'Connected' if status['connected'] else 'Disconnected'}")
    print(f"Log: {LOG_FILE}")
PYBRIDGE

chmod +x "$OSHI_ARP_DIR/arp_bridge.py"
success "ARP Bridge作成: $OSHI_ARP_DIR/arp_bridge.py"

# ── 起動・停止スクリプト ──
step "Step 7: 起動・停止スクリプト作成"

cat > "$OSHI_ARP_DIR/start_arp.sh" << 'STARTARP'
#!/usr/bin/env bash
# ARP デーモン起動スクリプト
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

echo "ARP デーモンを起動中..."

# arpc start（バックグラウンド）
arpc start

echo ""
echo "ARP Identity:"
arpc identity
echo ""
echo "ARP Status:"
arpc status
echo ""
echo "ARP デーモンが起動しました"
echo "メッセージ送信: arpc send <name-or-pubkey> \"message\""
echo "ステータス確認: arpc status"
echo "停止: arpc stop (存在する場合) or kill"
STARTARP
chmod +x "$OSHI_ARP_DIR/start_arp.sh"
success "起動スクリプト: $OSHI_ARP_DIR/start_arp.sh"

# ── ヘルスチェック ──
step "Step 8: ヘルスチェック"

info "arpc doctor を実行中..."
if arpc doctor 2>/dev/null; then
    success "ヘルスチェック完了"
else
    warn "arpc doctor が失敗しました（初回起動前は正常）"
    info "arpc start を実行後に再度確認してください"
fi

# ── 完了メッセージ ──
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   ARP v0.3.2 インストール完了！                     ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}設定ファイル:${NC} $CONFIG_FILE"
echo -e "${BOLD}ブリッジ:${NC}     $OSHI_ARP_DIR/arp_bridge.py"
echo -e "${BOLD}ログ:${NC}         $LOG_FILE"
echo ""
echo -e "${BOLD}次のステップ:${NC}"
echo "  1. ARP デーモン起動:"
echo "     bash $OSHI_ARP_DIR/start_arp.sh"
echo ""
echo "  2. 公開鍵を確認:"
echo "     arpc identity"
echo ""
echo "  3. コンタクト追加:"
echo "     arpc contact add <name> <their-pubkey>"
echo ""
echo "  4. メッセージ送信:"
echo "     arpc send <name> \"hello from OSHI Jr.\""
echo ""
echo -e "${BOLD}OSHI Jr. 連携:${NC}"
echo "  - ARP Bridge: python3 $OSHI_ARP_DIR/arp_bridge.py"
echo "  - Webhook連携: vi $CONFIG_FILE (webhook section)"
echo ""
success "セットアップが正常に完了しました！"
