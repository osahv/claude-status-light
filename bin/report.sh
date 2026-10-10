#!/bin/bash
# Claude Code hook -> status file for the menu bar light. Pure bash builtins: no python, no jq, no extra processes.
# Usage (from a hook): report.sh working|attention|error|idle|end    (hook JSON on stdin)
# Writes ~/.claude-status/<session_id> as one line "state|project|event|pid"; "end" removes it. Silent, never fails.
state="${1:-idle}"
dir="${CLAUDE_STATUS_DIR:-$HOME/.claude-status}"
read -r -d '' json                                   # whole stdin, builtin (returns non-zero at EOF, that is fine)
sid="${json#*\"session_id\":}"; sid="${sid# }"; sid="${sid#\"}"; sid="${sid%%\"*}"
case "$sid" in ""|*/*|*\{*) exit 0;; esac
[ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || exit 0
if [ "$state" = end ]; then rm -f "$dir/$sid"; exit 0; fi
cwd="${json#*\"cwd\":}"; cwd="${cwd# }"; cwd="${cwd#\"}"; cwd="${cwd%%\"*}"; cwd="${cwd%/}"
ev="${json#*\"hook_event_name\":}"; ev="${ev# }"; ev="${ev#\"}"; ev="${ev%%\"*}"
# Claude waiting on the user counts as attention: a question dialog, a plan to approve,
# or a finished turn whose last lines ask something.
case "$ev" in
PreToolUse)
    tool="${json#*\"tool_name\":}"; tool="${tool# }"; tool="${tool#\"}"; tool="${tool%%\"*}"
    case "$tool" in AskUserQuestion|ExitPlanMode) state=attention; ev="$ev:$tool";; esac;;
Stop)
    case "$json" in *\"last_assistant_message\":*)
        msg="${json#*\"last_assistant_message\":}"; msg="${msg# }"; msg="${msg#\"}"
        msg="${msg//\\\\/}"; msg="${msg//\\\"/}"; msg="${msg%%\"*}"   # drop escapes, cut at the closing quote
        [ ${#msg} -gt 400 ] && msg="${msg:${#msg}-400}"   # bash 3.2: ${msg: -400} is empty for short strings
        while :; do case "$msg" in *\\n|*' '|*'*'|*'`') msg="${msg%\\n}"; msg="${msg%[ *\`]}";; *) break;; esac; done
        case "$msg" in *\?|*'? '*|*'?\n'*|*'?**'*|*'?)'*) state=attention; ev="Stop:question";; esac;;
    esac;;
esac
# 4th field: the hook's parent (Claude Code, or a shell right under it); the app looks there for background commands.
printf '%s|%s|%s|%s\n' "$state" "${cwd##*/}" "${ev:0:40}" "$PPID" > "$dir/$sid" 2>/dev/null
exit 0
