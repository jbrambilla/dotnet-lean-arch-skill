#!/usr/bin/env bash
# Valida a integridade do repositorio. Sai com codigo 1 se qualquer checagem falhar.
# Checagens:
#   1. Frontmatter do SKILL.md com name, description e version
#   2. description com no maximo 250 caracteres
#   3. SKILL.md com no maximo 500 linhas
#   4. Versao identica entre SKILL.md, plugin.json e marketplace.json
#   5. Nenhum caminho absoluto ou string parecida com credencial no repositorio
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_NAME="dotnet-lean-arch"
SKILL_MD="$ROOT/skills/$SKILL_NAME/SKILL.md"
PLUGIN_JSON="$ROOT/skills/$SKILL_NAME/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$ROOT/.claude-plugin/marketplace.json"

FAIL=0
err() { echo "ERRO: $*"; FAIL=1; }
ok()  { echo "OK:   $*"; }

# --- 0. arquivos obrigatorios ------------------------------------------------
for f in "$SKILL_MD" "$PLUGIN_JSON" "$MARKETPLACE_JSON"; do
  if [ ! -f "$f" ]; then
    err "arquivo obrigatorio ausente: ${f#"$ROOT"/}"
  fi
done
if [ "$FAIL" -ne 0 ]; then
  echo "VALIDACAO FALHOU"
  exit 1
fi

# --- 1. frontmatter: name / description / version ----------------------------
FRONTMATTER="$(awk '/^---[[:space:]]*$/{c++; next} c==1{print} c>=2{exit}' "$SKILL_MD" | tr -d '\r')"

for field in name description version; do
  if echo "$FRONTMATTER" | grep -qE "^${field}:"; then
    ok "frontmatter tem '$field'"
  else
    err "frontmatter sem campo obrigatorio: $field"
  fi
done

# --- 2. description <= 250 caracteres ----------------------------------------
DESC_LINE="$(echo "$FRONTMATTER" | grep -E '^description:' | head -n1)"
if [ -n "$DESC_LINE" ]; then
  if echo "$DESC_LINE" | grep -qE '^description:[[:space:]]*[>|]'; then
    # estilo folded/literal do YAML: concatena as linhas indentadas seguintes
    DESC="$(echo "$FRONTMATTER" \
      | awk '/^description:/{f=1; next} f && /^[[:space:]]/{printf "%s ", $0; next} f{exit}' \
      | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  else
    DESC="$(echo "$DESC_LINE" | sed -E 's/^description:[[:space:]]*//; s/^"//; s/"$//')"
  fi
  DESC_LEN=${#DESC}
  if [ "$DESC_LEN" -le 250 ]; then
    ok "description com $DESC_LEN caracteres (limite 250)"
  else
    err "description com $DESC_LEN caracteres (limite 250)"
  fi
fi

# --- 3. SKILL.md <= 500 linhas -----------------------------------------------
LINES="$(wc -l < "$SKILL_MD" | tr -d '[:space:]')"
if [ "$LINES" -le 500 ]; then
  ok "SKILL.md com $LINES linhas (limite 500)"
else
  err "SKILL.md com $LINES linhas (limite 500)"
fi

# --- 4. versao sincronizada ---------------------------------------------------
json_version() {
  grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$1" | head -n1 \
    | sed -E 's/.*"([^"]+)"$/\1/'
}
V_SKILL="$(echo "$FRONTMATTER" | grep -E '^version:' | head -n1 \
  | sed -E 's/^version:[[:space:]]*//; s/"//g' | tr -d '[:space:]')"
V_PLUGIN="$(json_version "$PLUGIN_JSON")"
V_MARKET="$(json_version "$MARKETPLACE_JSON")"
if [ -n "$V_SKILL" ] && [ "$V_SKILL" = "$V_PLUGIN" ] && [ "$V_SKILL" = "$V_MARKET" ]; then
  ok "versao sincronizada: $V_SKILL"
else
  err "versao divergente: SKILL.md='$V_SKILL' plugin.json='$V_PLUGIN' marketplace.json='$V_MARKET'"
fi

# --- 5. caminhos absolutos e credenciais --------------------------------------
# validate.sh e excluido do scan (contem os proprios padroes de busca)
ABS_RE='([A-Za-z]:\\|[A-Za-z]:/[A-Za-z]|/home/[a-z]|/Users/[A-Za-z])'
CRED_RE="(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|(password|passwd|secret|api[_-]?key|apikey|token)[[:space:]]*[:=][[:space:]]*[\"'][A-Za-z0-9+/=_-]{12,}[\"'])"

ABS_HITS="$(grep -rInE --exclude-dir=.git --exclude='validate.sh' --exclude='*.zip' "$ABS_RE" "$ROOT" 2>/dev/null || true)"
if [ -n "$ABS_HITS" ]; then
  err "caminho absoluto encontrado:"
  echo "$ABS_HITS"
else
  ok "nenhum caminho absoluto"
fi

CRED_HITS="$(grep -rInEi --exclude-dir=.git --exclude='validate.sh' --exclude='*.zip' "$CRED_RE" "$ROOT" 2>/dev/null || true)"
if [ -n "$CRED_HITS" ]; then
  err "string parecida com credencial encontrada:"
  echo "$CRED_HITS"
else
  ok "nenhuma credencial aparente"
fi

# --- resultado -----------------------------------------------------------------
echo
if [ "$FAIL" -ne 0 ]; then
  echo "VALIDACAO FALHOU"
  exit 1
fi
echo "VALIDACAO OK"
