#!/system/bin/sh

core_dir() { printf '%s/%s' "$XG_DATA" "$1"; }
core_cfg_file() { printf '%s/%s/config.json' "$XG_DATA" "$1"; }
core_status_file() { printf '%s/%s/status.json' "$XG_DATA" "$1"; }

_CORE_JSON_AWK='
function skipws() { while (i <= n && substr(s, i, 1) ~ /[ \t\r\n]/) i++ }
function rdstr(   c, out) {
  out = ""; i++
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") { out = out c substr(s, i + 1, 1); i += 2; continue }
    if (c == "\"") { i++; return out }
    out = out c; i++
  }
  return out
}
function rdraw(   st, d, c, q) {
  st = i; d = 0; q = 0
  while (i <= n) {
    c = substr(s, i, 1)
    if (q) { if (c == "\\") { i += 2; continue } if (c == "\"") q = 0; i++; continue }
    if (c == "\"") { q = 1; i++; continue }
    if (c == "{" || c == "[") d++
    else if (c == "}" || c == "]") { if (d == 0) break; d-- }
    else if (c == "," && d == 0) break
    i++
  }
  return substr(s, st, i - st)
}
function unesc(v) { gsub(/\\"/, "\"", v); gsub(/\\\\/, "\\", v); gsub(/\\n/, "\n", v); gsub(/\\t/, "\t", v); return v }
{ s = s $0 "\n" }
END {
  key = ENVIRON["CORE_KEY"]
  n = length(s); i = 1; cnt = 0
  skipws()
  if (substr(s, i, 1) == "{") {
    i++
    while (i <= n) {
      skipws(); c = substr(s, i, 1)
      if (c == "}") break
      if (c == ",") { i++; continue }
      if (c != "\"") { i++; continue }
      k = rdstr(); skipws()
      if (substr(s, i, 1) == ":") i++
      skipws()
      if (substr(s, i, 1) == "\"") { v = "\"" rdstr() "\""; } else { v = rdraw(); sub(/[ \t\r\n]+$/, "", v) }
      if (!(k in val)) { cnt++; ord[cnt] = k }
      val[k] = v
    }
  }
  if (mode == "get") {
    if (!(key in val)) exit 1
    v = val[key]
    if (v ~ /^".*"$/) v = unesc(substr(v, 2, length(v) - 2))
    else if (v == "true") v = 1
    else if (v == "false") v = 0
    else if (v == "null") v = ""
    printf "%s", v; exit 0
  }
  if (mode == "keys") { for (j = 1; j <= cnt; j++) print ord[j]; exit 0 }
  if (mode == "set") { raw = ENVIRON["CORE_RAW"]; if (!(key in val)) { cnt++; ord[cnt] = key } val[key] = raw }
  if (mode == "del") delete val[key]
  printf "{"; first = 1
  for (j = 1; j <= cnt; j++) {
    k = ord[j]; if (!(k in val)) continue
    printf "%s\n  \"%s\": %s", (first ? "" : ","), k, val[k]; first = 0
  }
  printf "%s}\n", (first ? "" : "\n")
}'

core_json_get() {
  [ -f "$1" ] || return 1
  CORE_KEY=$2 awk -v mode=get "$_CORE_JSON_AWK" "$1" 2>/dev/null
}
core_json_keys() { [ -f "$1" ] && awk -v mode=keys "$_CORE_JSON_AWK" "$1" 2>/dev/null; }

core_json_lit() {
  case "$1" in true|false|null) printf '%s' "$1"; return ;; esac
  if printf '%s' "$1" | grep -Eq '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$'; then printf '%s' "$1"
  else printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\t' '  ')"; fi
}

core_json_set() {
  mkdir -p "${1%/*}"
  _jt=$1.tmp.$$
  _jr=$(core_json_lit "$3")
  if [ -f "$1" ]; then CORE_KEY=$2 CORE_RAW=$_jr awk -v mode=set "$_CORE_JSON_AWK" "$1" >"$_jt"
  else printf '' | CORE_KEY=$2 CORE_RAW=$_jr awk -v mode=set "$_CORE_JSON_AWK" >"$_jt"; fi
  [ -s "$_jt" ] && mv -f "$_jt" "$1" || { rm -f "$_jt"; return 1; }
}
core_json_del() {
  [ -f "$1" ] || return 0
  _jt=$1.tmp.$$
  CORE_KEY=$2 awk -v mode=del "$_CORE_JSON_AWK" "$1" >"$_jt" && [ -s "$_jt" ] && mv -f "$_jt" "$1" || rm -f "$_jt"
}


core_cfg_get() {
  _cv=$(core_json_get "$(core_cfg_file "$1")" "$2") && [ -n "$_cv" ] && { printf '%s' "$_cv"; return 0; }
  _cv=$(prop_get "$XG_CFG/$1.prop" "$2")
  [ -n "$_cv" ] && { printf '%s' "$_cv"; return 0; }
  printf '%s' "${3:-}"
}
core_cfg_set() { core_json_set "$(core_cfg_file "$1")" "$2" "$3"; }
core_cfg_del() { core_json_del "$(core_cfg_file "$1")" "$2"; }


core_status_write() {
  _sid=$1; shift
  _sf=$(core_status_file "$_sid"); mkdir -p "${_sf%/*}"
  {
    printf '{\n  "id": "%s",\n  "updated_at": %s' "$_sid" "$(date +%s)"
    for _kv in "$@"; do
      printf ',\n  "%s": %s' "${_kv%%=*}" "$(core_json_lit "${_kv#*=}")"
    done
    printf '\n}\n'
  } >"$_sf.tmp.$$" && mv -f "$_sf.tmp.$$" "$_sf"
}

core_migrate() { core_migrate_prop shield; }

core_alias_id() { echo "$1"; }

core_prop_to_json() {   # <旧 .prop 文件> <新 id>
  [ -f "$1" ] || return 0
  _pf=$(core_cfg_file "$2")
  grep -E '^[A-Za-z0-9_.]+=' "$1" | sed 's/=.*//' | awk '!s[$0]++' | while read -r _k; do
    core_json_get "$_pf" "$_k" >/dev/null && continue
    core_json_set "$_pf" "$_k" "$(prop_get "$1" "$_k")"
  done
}

core_migrate_prop() {
  [ -f "$XG_STATE/migrated.cfg.$1" ] && return 0
  [ -d "$XG_FEATURES/$1" ] || return 0
  mkdir -p "$XG_DATA/$1"
  core_prop_to_json "$XG_CFG/$1.prop" "$1"
  date +%s >"$XG_STATE/migrated.cfg.$1"
  [ -f "$XG_CFG/$1.prop" ] && log core "迁移：config/$1.prop → $1/config.json（旧文件保留）"
  return 0
}

