#!/usr/bin/env bash
# wake.sh: hook de Claude Code. Cuando la sesión termina, falla o pide permiso,
# hace POST de un JSON corto al webhook de la rutina del bot que la lanzó.
# Nunca traba a Claude: siempre sale 0.
#
# Variables:
#   NOTIFY_AGENT  slug del bot (en la nube lo pone el environment)
#   WAKE_URL      URL del webhook de la rutina "Claude Code wake" de ese bot
#   WAKE_KEY_FILE (solo local) archivo modo 600 con la key del webhook.
#                 En la nube no hace falta: el proxy de Anthropic agrega el header
#                 Authorization con el network secret del environment.
#   WAKE_SUMMARY_MAX (default 4000, 0 = sin resumen), WAKE_TIMEOUT (default 8),
#   WAKE_STATE_DIR, WAKE_DRY_RUN=1 (imprime el aviso en vez de mandarlo)
set -u
umask 077
command -v jq >/dev/null 2>&1 || exit 0
IN=$(cat 2>/dev/null || true)
printf '%s' "$IN" | jq -e 'type == "object"' >/dev/null 2>&1 || exit 0

j()  { printf '%s' "$IN" | jq -r --arg k "$1" '.[$k] // empty | tostring' 2>/dev/null; }
cl() { printf '%s' "$2" | LC_ALL=C tr -c "$1" '_' | LC_ALL=C cut -c 1-120; }   # lista blanca + tope

[ -n "$(j agent_id)" ] && exit 0            # el Stop de un subagente no es el fin de la tarea

ev=$(cl 'A-Za-z' "$(j hook_event_name)")
sid=$(cl 'A-Za-z0-9_-' "$(j session_id)")
pid=$(cl 'A-Za-z0-9_-' "$(j prompt_id)"); pid=${pid:-turn}
transcript=$(j transcript_path)
cwd=$(j cwd); [ -d "$cwd" ] || cwd=$PWD
S="${WAKE_STATE_DIR:-$HOME/.local/state/cc-wake}/${sid:-nosession}"
mkdir -p "$S" 2>/dev/null || exit 0
recent() { [ -e "$S/$1" ] && [ $(( $(date +%s) - $(stat -c %Y "$S/$1") )) -le "$2" ]; }

detail=""
case "$ev" in
  Stop)              kind=finished;    mark="Stop-$pid";  [ -e "$S/$mark" ] && exit 0 ;;
  StopFailure)       kind=failed;      mark="Fail-$pid";  [ -e "$S/$mark" ] && exit 0
                     detail="error=$(cl 'A-Za-z0-9_.=-' "$(j error)")" ;;
  PermissionRequest) kind=needs_input; mark="Perm"        # solo el nombre de la tool, nunca su input
                     detail="tool=$(cl 'A-Za-z0-9_.=-' "$(j tool_name)")" ;;
  Notification)      nt=$(cl 'A-Za-z0-9_' "$(j notification_type)")
                     case "$nt" in
                       permission_prompt) recent Perm 120 && exit 0 ;;   # ya avisó PermissionRequest
                       elicitation_dialog|elicitation_url_dialog|agent_needs_input) ;;
                       *) exit 0 ;;                                      # idle_prompt y demás: nada
                     esac
                     kind=needs_input; mark="Notif-$nt-$pid"; [ -e "$S/$mark" ] && exit 0
                     detail="type=$nt" ;;
  SessionEnd)        kind=ended; mark="End"
                     compgen -G "$S/Stop-*" >/dev/null && exit 0; [ -e "$S/$mark" ] && exit 0
                     detail="reason=$(cl 'A-Za-z0-9_.=-' "$(j reason)")" ;;
  *) exit 0 ;;
esac

# Resumen: último mensaje del asistente (del hook o del transcript, sin subagentes).
max=${WAKE_SUMMARY_MAX:-4000}; case "$max" in ''|*[!0-9]*) max=4000 ;; esac
summary=""
if [ "$max" -gt 0 ]; then
  summary=$(j last_assistant_message)
  if [ -z "$summary" ] && [ -r "$transcript" ]; then
    # Un mensaje puede venir partido en varias líneas con el mismo message.id: se juntan.
    summary=$(jq -nrR 'reduce (inputs | fromjson? | objects
        | select(.type == "assistant" and (.isSidechain // false) == false)
        | {id: (.message.id // ""), t: ([.message.content // empty | if type == "string" then .
            elif type == "array" then .[] | select(.type? == "text") | .text else empty end] | join("\n"))}
        | select(.t | length > 0)) as $m
        ({id: "", t: ""}; if $m.id != "" and $m.id == .id then .t += "\n" + $m.t else $m end) | .t' \
      <"$transcript" 2>/dev/null)
  fi
fi

repo=$(git -C "$cwd" remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#^[a-z+]+://([^@/]*@)?[^/]+/##; s#^[^@]+@[^:]+:##')
repo=$(cl 'A-Za-z0-9._/-' "$repo")
branch=$(cl 'A-Za-z0-9._/-' "$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null)")
pr_url=$(printf '%s' "$summary" | grep -oE 'https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+' | tail -n 1)
agent=$(printf '%s' "${NOTIFY_AGENT:-unknown}" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -c 'a-z0-9-' '-' | cut -c 1-40)
session_url=""
[ -n "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" ] && {
  rid=$(cl 'A-Za-z0-9_-' "$CLAUDE_CODE_REMOTE_SESSION_ID"); session_url="https://claude.ai/code/${rid/#cse_/session_}"; }
mode=local; [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && mode=cloud

# El JSON se arma con jq. El resumen se limpia: sin caracteres de control, con secretos tapados y truncado.
payload=$(printf '%s' "$summary" | jq -Rsc --arg event "$ev" --arg kind "$kind" --arg detail "$detail" \
  --arg mode "$mode" --arg agent "$agent" --arg session_id "$sid" --arg session_url "$session_url" \
  --arg repo "$repo" --arg branch "$branch" --arg pr_url "$pr_url" --arg u "${WAKE_URL:-}" \
  --argjson max "$max" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  (gsub("[\u0000-\u0008\u000b-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2066-\u2069]"; "")
   | gsub("-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)"; "[REDACTED]")
   | gsub("(?<a>(?i:bearer|basic))\\s+[A-Za-z0-9._~+/=-]{12,}"; "\(.a) [REDACTED]")
   | gsub("(?<a>(?i:[A-Za-z0-9_]*(?:api[_-]?key|token|secret|passw(?:or)?d)[A-Za-z0-9_]*)[\"\u0027]?\\s*[:=]\\s*)[\"\u0027]?[^\\s\"\u0027`,;]{6,}"; "\(.a)[REDACTED]")
   | gsub("(?<a>[a-z][a-z0-9+.-]*://)[^/\\s:@]+:[^/\\s@]+@"; "\(.a)[REDACTED]@")
   | gsub("gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}"; "[REDACTED]")
   | (if ($u | length) >= 8 then split($u) | join("[REDACTED]") else . end)
   | gsub("^\\s+|\\s+$"; "")) as $s
  | {source:"claude-code", v:1, kind:$kind, event:$event, detail:$detail, mode:$mode, agent:$agent,
     session_id:$session_id, session_url:$session_url, repo:$repo, branch:$branch, pr_url:$pr_url,
     summary:(if ($s | length) > $max then $s[0:$max] + " […truncado]" else $s end), ts:$ts}
  | with_entries(select(.value != ""))') || exit 0

if [ "${WAKE_DRY_RUN:-0}" = 1 ]; then printf '%s\n' "$payload"; : >"$S/$mark"; exit 0; fi
case "${WAKE_URL:-}" in https://*) ;; *) exit 0 ;; esac

# Local: la key va a curl por un archivo de headers temporal, nunca por la línea de comandos.
hdr=$(mktemp) || exit 0
if [ "$mode" = local ] && [ -r "${WAKE_KEY_FILE:-}" ]; then
  printf 'Authorization: Bearer %s\n' "$(head -n 1 "$WAKE_KEY_FILE" | tr -d '\r\n')" >"$hdr"
fi
for i in 1 2 3; do
  code=$(printf '%s' "$payload" | curl -sS -o /dev/null -w '%{http_code}' -m "${WAKE_TIMEOUT:-8}" -X POST \
    -H 'Content-Type: application/json' -H "@$hdr" --data-binary @- "$WAKE_URL" 2>/dev/null)
  case "$code" in 2??) : >"$S/$mark"; break ;; esac
  [ "$i" -lt 3 ] && sleep $((i * 2))
done
rm -f "$hdr"
exit 0
