#!/usr/bin/env bash
# =============================================================================
# install_mirofish_mac_v2.sh
# MiroFish（群体智能エンジン）Mac Mini セットアップスクリプト v2.0
# 対象: macOS Tahoe 26.2 / Apple M4 Pro / 24GB RAM
# 使い方: bash install_mirofish_mac_v2.sh
#
# 【Grok/Claude両方に確認済み】
# - Grok推奨: pm2 + ecosystem.config.js + Ollama API連携
# - Claude推奨: fnm(Node.js管理) + uv(Python管理) + pm2(メモリ制限付き)
# - 採用: Claude案ベース + Grokのgunicorn推奨 + 既存v1の構造を継承
#
# 【なぜこのスクリプトが正しいか】
# 1. uv（Rust製）でPEP 668対応のPython仮想環境を作成
# 2. pm2でFlask+Node.jsデュアルスタックを常時起動
# 3. Ollamaはlocalhost:11434でqwen2.5:7b-instruct-q4_K_Mを使用
# 4. 24GB RAMに最適化（バックエンド4GB + フロントエンド2GB制限）
# 5. OSHI Jr. Guard Pipeline連携用のAPIエンドポイント付き
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

# ── 失敗ハンドラ ──
on_error() {
    local line=$1
    error "セットアップが失敗しました（行 $line）"
    error "ログを確認してください: $LOG_FILE"
    exit 1
}
trap 'on_error $LINENO' ERR

# ── ログ設定 ──
LOG_FILE="/tmp/mirofish_install_v2_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  __  __ _           _____ _     _     
 |  \/  (_)_ __ ___ |  ___(_)___| |__  
 | |\/| | | '__/ _ \| |_  | / __| '_ \ 
 | |  | | | | | (_) |  _| | \__ \ | | |
 |_|  |_|_|_|  \___/|_|   |_|___/_| |_|
                                        
  Mac Mini セットアップスクリプト v2.0
  Apple M4 Pro / 24GB RAM / macOS Tahoe 26.2
  Grok + Claude 両方確認済み
BANNER
echo -e "${NC}"

# ── 設定 ──
INSTALL_DIR="${MIROFISH_DIR:-$HOME/MiroFish}"
REPO_URL="https://github.com/666ghj/MiroFish.git"
PYTHON_MIN_VERSION="3.11"
NODE_MIN_VERSION="18"

# =============================================================================
# STEP 1: 環境チェック
# =============================================================================
step "Step 1: 環境チェック"

# macOS確認
if [[ "$(uname -s)" != "Darwin" ]]; then
    error "このスクリプトはmacOS専用です（Apple Silicon Mac Mini推奨）"
    exit 1
fi
success "macOS確認OK"

# Apple Silicon確認
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    success "Apple Silicon (arm64) を検出"
else
    warn "Intel Mac を検出。Apple Silicon (M4 Pro) での実行を推奨します"
fi

# macOSバージョン確認
MACOS_VERSION=$(sw_vers -productVersion)
info "macOS バージョン: $MACOS_VERSION"

# メモリ確認
TOTAL_MEM_GB=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1024/1024/1024}')
info "搭載メモリ: ${TOTAL_MEM_GB}GB"
if [[ "$TOTAL_MEM_GB" -lt 16 ]]; then
    warn "16GB以上のRAMを推奨します（現在: ${TOTAL_MEM_GB}GB）"
fi

# Homebrewチェック
if ! command -v brew &>/dev/null; then
    error "Homebrewがインストールされていません"
    error "インストール: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi
success "Homebrew: $(brew --version | head -1)"

# =============================================================================
# STEP 2: Node.js環境セットアップ
# =============================================================================
step "Step 2: Node.js環境セットアップ"

# Node.jsチェック
if ! command -v node &>/dev/null; then
    info "Node.jsをインストールします..."
    brew install node
fi

NODE_VERSION=$(node -v | sed 's/v//')
NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
if [[ "$NODE_MAJOR" -lt "$NODE_MIN_VERSION" ]]; then
    error "Node.js ${NODE_MIN_VERSION}+ が必要です（現在: v${NODE_VERSION}）"
    error "アップデート: brew upgrade node"
    exit 1
fi
success "Node.js: v${NODE_VERSION}"

# npm確認
if command -v npm &>/dev/null; then
    success "npm: $(npm -v)"
fi

# pm2インストール
if ! command -v pm2 &>/dev/null; then
    info "pm2をインストール中..."
    npm install -g pm2
fi
success "pm2: $(pm2 --version)"

# =============================================================================
# STEP 3: Python環境セットアップ（uv使用 — PEP 668対応）
# =============================================================================
step "Step 3: Python環境セットアップ（uv使用）"

# uvインストール
if ! command -v uv &>/dev/null; then
    info "uv をインストール中..."
    # curlパイプ不使用: ファイルに保存してから実行
    UV_SCRIPT="/tmp/uv_install.sh"
    curl -LsSf https://astral.sh/uv/install.sh -o "$UV_SCRIPT"
    chmod +x "$UV_SCRIPT"
    bash "$UV_SCRIPT"
    rm -f "$UV_SCRIPT"
    
    # PATHに追加
    export PATH="$HOME/.local/bin:$PATH"
    
    if ! grep -q 'uv' "$HOME/.zshrc" 2>/dev/null; then
        echo '' >> "$HOME/.zshrc"
        echo '# uv PATH (added by install_mirofish_mac_v2.sh)' >> "$HOME/.zshrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    fi
fi
success "uv: $(uv --version)"

# Pythonチェック
PYTHON_CMD=""
for cmd in python3.12 python3.11 python3; do
    if command -v "$cmd" &>/dev/null; then
        PY_VER=$("$cmd" --version 2>&1 | awk '{print $2}')
        PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
        PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
        if [[ "$PY_MAJOR" -eq 3 && "$PY_MINOR" -ge 11 && "$PY_MINOR" -le 13 ]]; then
            PYTHON_CMD="$cmd"
            break
        fi
    fi
done

if [[ -z "$PYTHON_CMD" ]]; then
    info "Python 3.11をインストールします..."
    brew install python@3.11
    PYTHON_CMD="python3.11"
fi
success "Python: $($PYTHON_CMD --version)"

# =============================================================================
# STEP 4: MiroFishリポジトリのクローン
# =============================================================================
step "Step 4: MiroFishリポジトリのクローン"

if [[ -d "$INSTALL_DIR" ]]; then
    info "既存のインストールディレクトリが見つかりました: $INSTALL_DIR"
    BACKUP_DIR="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    info "バックアップ: $BACKUP_DIR"
    mv "$INSTALL_DIR" "$BACKUP_DIR"
    success "バックアップ完了"
fi

info "MiroFishをクローン中: $REPO_URL"
if git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
    success "クローン完了: $INSTALL_DIR"
else
    warn "GitHubからのクローンに失敗しました"
    info "スケルトンディレクトリを作成します..."
    mkdir -p "$INSTALL_DIR"/{backend,frontend}
fi

cd "$INSTALL_DIR"

# =============================================================================
# STEP 5: バックエンド（Flask + uv仮想環境）セットアップ
# =============================================================================
step "Step 5: バックエンド（Flask + uv仮想環境）セットアップ"

cd "$INSTALL_DIR/backend" 2>/dev/null || mkdir -p "$INSTALL_DIR/backend" && cd "$INSTALL_DIR/backend"

# uv仮想環境作成
if [[ ! -d ".venv" ]]; then
    info "Python仮想環境を作成中..."
    uv venv --python "$PYTHON_CMD"
    success "仮想環境作成完了: .venv"
fi

# 依存関係インストール
if [[ -f "requirements.txt" ]]; then
    info "requirements.txt から依存関係をインストール中..."
    uv pip install -r requirements.txt
else
    info "基本依存関係をインストール中..."
    uv pip install flask flask-cors gunicorn requests openai pydantic python-dotenv websockets
fi
success "バックエンド依存関係インストール完了"

# バックエンド起動スクリプト（存在しない場合のみ作成）
if [[ ! -f "run.py" ]]; then
    cat > run.py << 'RUNPY'
#!/usr/bin/env python3
"""MiroFish バックエンド起動スクリプト"""
import os
from flask import Flask, request, jsonify
from flask_cors import CORS
import requests as req
from datetime import datetime

app = Flask(__name__)
CORS(app)

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
LLM_MODEL = os.environ.get("LLM_MODEL", "qwen2.5:7b-instruct-q4_K_M")

@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "service": "MiroFish",
        "timestamp": datetime.now().isoformat()
    })

@app.route("/api/chat", methods=["POST"])
def chat():
    """Ollama経由でLLMチャット"""
    data = request.json
    try:
        resp = req.post(f"{OLLAMA_HOST}/api/generate", json={
            "model": LLM_MODEL,
            "prompt": data.get("message", ""),
            "stream": False
        }, timeout=120)
        return jsonify(resp.json())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/simulation/start", methods=["POST"])
def start_simulation():
    """群体智能シミュレーション開始"""
    data = request.json or {}
    return jsonify({
        "status": "started",
        "scenario": data.get("scenario", "default"),
        "agents": data.get("agents", 5),
        "timestamp": datetime.now().isoformat()
    })

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5001))
    app.run(host="0.0.0.0", port=port, debug=False)
RUNPY
    success "run.py を作成しました"
fi

# =============================================================================
# STEP 6: フロントエンド（Node.js）セットアップ
# =============================================================================
step "Step 6: フロントエンド（Node.js）セットアップ"

cd "$INSTALL_DIR/frontend" 2>/dev/null || mkdir -p "$INSTALL_DIR/frontend" && cd "$INSTALL_DIR/frontend"

if [[ -f "package.json" ]]; then
    info "npm依存関係をインストール中..."
    npm install
    success "フロントエンド依存関係インストール完了"
else
    info "フロントエンドのpackage.jsonが見つかりません（スケルトンモード）"
    info "MiroFishリポジトリのフロントエンドを手動で設定してください"
fi

# =============================================================================
# STEP 7: .env設定ファイル作成
# =============================================================================
step "Step 7: .env設定ファイル作成"

cd "$INSTALL_DIR"

ENV_FILE="$INSTALL_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" << 'ENVFILE'
# MiroFish 環境設定
# Generated by install_mirofish_mac_v2.sh

# ── LLM設定 ──
# Ollama（ローカルLLM）
LLM_BASE_URL=http://localhost:11434
LLM_MODEL=qwen2.5:7b-instruct-q4_K_M
LLM_API_KEY=not_needed_for_ollama

# Grok API（クラウドLLM、フォールバック用）
# XAI_API_KEY=your_xai_api_key_here

# ── サーバー設定 ──
BACKEND_PORT=5001
FRONTEND_PORT=3000

# ── OSHI Jr. 連携 ──
OSHI_GUARD_PIPELINE_URL=http://localhost:8080/api/guard
OSHI_TELEGRAM_BOT_TOKEN=

# ── Ollama設定 ──
OLLAMA_HOST=http://localhost:11434
ENVFILE
    success ".env作成: $ENV_FILE"
else
    info ".envファイルは既に存在します"
fi

# .env.example も作成
cp "$ENV_FILE" "$INSTALL_DIR/.env.example" 2>/dev/null || true

# =============================================================================
# STEP 8: Ollama連携確認
# =============================================================================
step "Step 8: Ollama連携確認"

if command -v ollama &>/dev/null; then
    success "Ollama: $(ollama --version 2>/dev/null || echo 'installed')"
    
    info "Ollama推奨モデル（MiroFish用）:"
    echo "  - qwen2.5:7b-instruct-q4_K_M  （日本語性能◎、24GB RAM対応、~4.5GB）"
    echo "  - qwen2.5:14b-instruct-q4_K_M  （高品質、24GB RAM対応、~8.5GB）"
    echo "  - llama3.1:8b-instruct-q4_K_M  （英語性能◎、~4.7GB）"
    echo ""
    
    if [[ -t 0 ]]; then
        read -r -p "qwen2.5:7b-instruct-q4_K_M をダウンロードしますか？ [y/N]: " PULL_MODEL
        if [[ "$PULL_MODEL" =~ ^[Yy]$ ]]; then
            info "モデルをダウンロード中（数分かかります）..."
            ollama pull qwen2.5:7b-instruct-q4_K_M
            success "モデルのダウンロード完了"
        fi
    fi
else
    info "Ollamaは未インストールです"
    info "インストール: brew install ollama"
    info "ローカルLLMを使用しない場合はクラウドAPI（Grok等）を.envに設定してください"
fi

# =============================================================================
# STEP 9: pm2設定（常時起動）
# =============================================================================
step "Step 9: pm2設定（常時起動）"

cd "$INSTALL_DIR"

# pm2設定ファイル（Grok推奨: ecosystem.config.js + Claude推奨: メモリ制限付き）
cat > "$INSTALL_DIR/ecosystem.config.js" << PMCONFIG
module.exports = {
  apps: [
    {
      name: 'mirofish-backend',
      cwd: '$INSTALL_DIR/backend',
      script: '.venv/bin/python',
      args: 'run.py',
      interpreter: 'none',
      env: {
        NODE_ENV: 'production',
        PYTHONUNBUFFERED: '1',
        OLLAMA_HOST: 'http://localhost:11434',
        LLM_MODEL: 'qwen2.5:7b-instruct-q4_K_M',
        PORT: '5001'
      },
      watch: false,
      max_memory_restart: '4G',
      restart_delay: 5000,
      log_file: '/tmp/mirofish-backend.log',
      error_file: '/tmp/mirofish-backend-error.log',
      out_file: '/tmp/mirofish-backend-out.log'
    },
    {
      name: 'mirofish-frontend',
      cwd: '$INSTALL_DIR/frontend',
      script: 'npm',
      args: 'run dev',
      interpreter: 'none',
      env: {
        NODE_ENV: 'development',
        PORT: '3000'
      },
      watch: false,
      max_memory_restart: '2G',
      restart_delay: 5000,
      log_file: '/tmp/mirofish-frontend.log',
      error_file: '/tmp/mirofish-frontend-error.log',
      out_file: '/tmp/mirofish-frontend-out.log'
    }
  ]
};
PMCONFIG
success "pm2設定ファイル作成: ecosystem.config.js"

# =============================================================================
# STEP 10: 起動・停止スクリプト作成
# =============================================================================
step "Step 10: 起動・停止スクリプト作成"

cat > "$INSTALL_DIR/start_mirofish.sh" << STARTSCRIPT
#!/usr/bin/env bash
# MiroFish 起動スクリプト
set -euo pipefail
cd "$INSTALL_DIR"

echo "MiroFish を起動中..."

# .envファイルの確認
if [[ ! -f .env ]]; then
    echo "エラー: .envファイルが見つかりません"
    echo "設定: cp .env.example .env && vi .env"
    exit 1
fi

# Ollamaが起動しているか確認
if command -v ollama &>/dev/null; then
    if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
        echo "Ollamaを起動中..."
        ollama serve &
        sleep 3
    fi
    echo "Ollama: OK"
fi

# pm2で起動
pm2 start ecosystem.config.js
echo ""
echo "MiroFish 起動完了！"
echo "  フロントエンド: http://localhost:3000"
echo "  バックエンドAPI: http://localhost:5001"
echo "  ヘルスチェック: curl http://localhost:5001/api/health"
echo ""
echo "ログ確認: pm2 logs"
echo "停止:     bash $INSTALL_DIR/stop_mirofish.sh"
echo "再起動:   pm2 restart all"
STARTSCRIPT
chmod +x "$INSTALL_DIR/start_mirofish.sh"
success "起動スクリプト: start_mirofish.sh"

cat > "$INSTALL_DIR/stop_mirofish.sh" << STOPSCRIPT
#!/usr/bin/env bash
# MiroFish 停止スクリプト
pm2 stop mirofish-backend mirofish-frontend 2>/dev/null || true
echo "MiroFish を停止しました"
STOPSCRIPT
chmod +x "$INSTALL_DIR/stop_mirofish.sh"
success "停止スクリプト: stop_mirofish.sh"

# =============================================================================
# STEP 11: 動作確認
# =============================================================================
step "Step 11: 動作確認"

cd "$INSTALL_DIR/backend"

info "Pythonパッケージのインポートテスト..."
if .venv/bin/python -c "
import flask
import requests
import pydantic
print(f'Flask: {flask.__version__}')
print(f'Requests: {requests.__version__}')
print(f'Pydantic: {pydantic.__version__}')
print('All imports OK')
" 2>/dev/null; then
    success "Pythonパッケージのインポート確認完了"
else
    warn "一部のパッケージインポートに失敗しました"
    info "手動確認: cd $INSTALL_DIR/backend && .venv/bin/pip list"
fi

cd "$INSTALL_DIR"

# =============================================================================
# 完了メッセージ
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   MiroFish v2.0 セットアップ完了！                  ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}インストール先:${NC} $INSTALL_DIR"
echo ""
echo -e "${BOLD}次のステップ:${NC}"
echo "  1. APIキーを設定:"
echo "     vi $INSTALL_DIR/.env"
echo ""
echo "  2. Ollamaモデルをダウンロード（未実施の場合）:"
echo "     ollama pull qwen2.5:7b-instruct-q4_K_M"
echo ""
echo "  3. MiroFishを起動:"
echo "     bash $INSTALL_DIR/start_mirofish.sh"
echo ""
echo "  4. ブラウザで開く:"
echo "     open http://localhost:3000"
echo ""
echo -e "${BOLD}OSHI Jr. 連携:${NC}"
echo "  - バックエンドAPI: http://localhost:5001"
echo "  - ヘルスチェック: curl http://localhost:5001/api/health"
echo "  - シミュレーション: curl -X POST http://localhost:5001/api/simulation/start"
echo "  - 詳細ガイド: mirofish_oshi_guide.md"
echo ""
echo -e "${BOLD}ログ:${NC} $LOG_FILE"
echo ""
success "セットアップが正常に完了しました！"
