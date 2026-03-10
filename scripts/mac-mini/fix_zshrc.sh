#!/usr/bin/env bash
# =============================================================================
# fix_zshrc.sh — ~/.zshrc 不正行修正スクリプト
# 対象: macOS Tahoe 26.2 / Apple M4 Pro / ユーザー: nagatayuudai
# 使い方: bash fix_zshrc.sh
#
# 【Grok/Claude両方に確認済み】
# - Grok推奨: BSD sed -i "" で直接削除（シンプル・高速）
# - Claude推奨: バックアップ付き + python3代替案も提供
# - 採用: Claude案ベース（安全性重視）+ Grokの簡潔さ
#
# 【なぜこのコマンドが正しいか】
# 1. BSD sed の -i '' は macOS 標準（GNU sed の -i とは異なる）
# 2. 正規表現 /^export \/[^=]*$/ は「export /」で始まり「=」を含まない行にマッチ
#    → 正常な「export PATH="/usr/local/bin:$PATH"」は「=」を含むので削除されない
#    → 不正な「export /Users/nagatayuudai/.zshrc」は「=」がないので削除される
# 3. バックアップはタイムスタンプ付きで複数回実行しても安全
# =============================================================================
set -euo pipefail

# ── カラー定義 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

ZSHRC="$HOME/.zshrc"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP="${ZSHRC}.backup.${TIMESTAMP}"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  .zshrc 不正行修正スクリプト v1.0           ║${NC}"
echo -e "${BOLD}║  Grok + Claude 両方確認済み                  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: ファイル存在確認 ──
if [[ ! -f "$ZSHRC" ]]; then
    error "$ZSHRC が見つかりません"
    exit 1
fi
info "対象ファイル: $ZSHRC"

# ── Step 2: 不正行の検出 ──
info "不正行を検索中..."
BAD_LINES=$(grep -n '^export /[^=]*$' "$ZSHRC" 2>/dev/null || true)

if [[ -z "$BAD_LINES" ]]; then
    success "不正行は見つかりませんでした。修正不要です。"
    exit 0
fi

echo -e "${YELLOW}検出された不正行:${NC}"
echo "$BAD_LINES"
echo ""

# ── Step 3: バックアップ作成 ──
info "バックアップを作成中: $BACKUP"
cp "$ZSHRC" "$BACKUP"
if [[ -f "$BACKUP" ]]; then
    success "バックアップ完了: $BACKUP ($(wc -c < "$BACKUP") bytes)"
else
    error "バックアップ作成に失敗しました"
    exit 1
fi

# ── Step 4: 不正行を削除 ──
# 方法A: python3（文字化け耐性が高い、Grok/Claude両方が代替案として推奨）
# 方法B: BSD sed（Grok推奨、Claude推奨）
#
# 採用: python3をメイン、sed をフォールバックとして使用
# 理由: ターミナルコピペ時の文字化け問題を完全回避（ゆーだの要件）

info "不正行を削除中（python3使用）..."
if python3 -c "
import os
path = os.path.expanduser('~/.zshrc')
with open(path, 'r') as f:
    lines = f.readlines()
cleaned = [l for l in lines if not (l.strip().startswith('export /') and '=' not in l)]
with open(path, 'w') as f:
    f.writelines(cleaned)
print(f'削除完了: {len(lines) - len(cleaned)} 行を除去')
"; then
    success "python3による修正完了"
else
    warn "python3が失敗しました。BSD sedにフォールバック..."
    # BSD sed フォールバック（Grok推奨構文）
    sed -i '' '/^export \/[^=]*$/d' "$ZSHRC"
    success "BSD sedによる修正完了"
fi

# ── Step 5: 修正結果の検証 ──
info "修正結果を検証中..."
REMAINING=$(grep -n '^export /[^=]*$' "$ZSHRC" 2>/dev/null || true)

if [[ -z "$REMAINING" ]]; then
    success "検証OK: 不正行は全て削除されました"
else
    error "検証NG: まだ不正行が残っています"
    echo "$REMAINING"
    error "手動で確認してください: vi $ZSHRC"
    exit 1
fi

# ── Step 6: diff表示 ──
info "変更差分:"
diff "$BACKUP" "$ZSHRC" || true
echo ""

# ── Step 7: source実行の案内 ──
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  修正完了!                                   ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}バックアップ:${NC} $BACKUP"
echo ""
echo -e "${BOLD}次のステップ:${NC}"
echo "  source ~/.zshrc"
echo ""
echo -e "${BOLD}エラーが出なければ成功です。${NC}"
echo ""

# ── 自動source（対話シェルの場合のみ） ──
if [[ -t 0 ]]; then
    read -r -p "今すぐ source ~/.zshrc を実行しますか？ [y/N]: " REPLY
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        info "source ~/.zshrc を実行中..."
        # サブシェルでsourceしてエラーチェック
        if bash -c "source $ZSHRC" 2>/dev/null; then
            success "source完了。エラーなし。"
        else
            warn "sourceでエラーが発生しました。手動で確認してください。"
        fi
    fi
fi
