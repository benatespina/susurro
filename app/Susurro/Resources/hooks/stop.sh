#!/bin/sh
# Susurro Claude Code stop hook.
# Receives Claude session JSON on stdin, extracts the last assistant message,
# and pipes it to `susurro read --stdin`.

# --- Debug logging ---
_log() {
	if [ "${SUSURRO_DEBUG:-0}" = "1" ]; then
		log_dir="${HOME}/Library/Logs/Susurro"
		mkdir -p "$log_dir"
		printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "${log_dir}/hook.log"
	fi
}

# --- Read stdin ---
input="$(cat)"
_log "Hook invoked, input length=${#input}"

# --- Extract cwd and transcript_path ---
if command -v jq >/dev/null 2>&1; then
	cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
	transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
	_log "jq: cwd=${cwd} transcript_path=${transcript_path}"
else
	cwd="$(printf '%s' "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | awk -F'"' '{print $4}')"
	transcript_path="$(printf '%s' "$input" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | awk -F'"' '{print $4}')"
	_log "awk: cwd=${cwd} transcript_path=${transcript_path}"
fi

# --- Walk ancestors of cwd up to HOME looking for .susurro-disable ---
if [ -n "$cwd" ]; then
	check_dir="$cwd"
	while [ -n "$check_dir" ] && [ "$check_dir" != "/" ]; do
		if [ -e "${check_dir}/.susurro-disable" ]; then
			_log ".susurro-disable found at ${check_dir}, exiting silently"
			exit 0
		fi
		if [ "$check_dir" = "$HOME" ]; then
			break
		fi
		check_dir="$(dirname "$check_dir")"
	done
fi

# --- Extract last assistant message text from JSONL transcript (layer 1) ---
message_text=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
	if command -v jq >/dev/null 2>&1; then
		# Stream JSONL lines through jq:
		# 1. Collect all assistant events (top-level "type":"assistant")
		# 2. Filter to those containing at least one text block (skip tool-use-only turns)
		# 3. Take the last such event
		# 4. Concatenate all its text blocks
		message_text="$(jq -rn \
			'[inputs | select(.type == "assistant" and .message.role == "assistant" and (any(.message.content[]?; .type == "text")))] | last | .message.content[]? | select(.type == "text") | .text' \
			"$transcript_path" 2>/dev/null | paste -sd' ' -)"
	else
		# awk/grep fallback (no jq): approximate extraction — known limitation.
		# Real schema: each line is {"type":"assistant","message":{"role":"assistant","content":[...]}}
		# Strategy: take the last line that has both "type":"assistant" and "type":"text" in content,
		# then extract "text":"<value>" substrings, unescaping basic JSON escapes.
		last_assistant="$(grep '"type"[[:space:]]*:[[:space:]]*"assistant"' "$transcript_path" | \
			grep '"type"[[:space:]]*:[[:space:]]*"text"' | tail -1)"
		message_text="$(printf '%s' "$last_assistant" | \
			grep -o '"text"[[:space:]]*:[[:space:]]*"[^"]*"' | \
			awk -F'"' 'BEGIN{t=""} {v=$4; gsub(/\\n/,"\n",v); gsub(/\\"/,"\"",v); if(t!="")t=t" "; t=t v} END{print t}')"
	fi
	_log "Layer 1 (transcript) extracted text length=${#message_text}"
else
	_log "No transcript_path or file missing; skipping layer 1"
fi

# --- Layer 2: top-level last_assistant_message field from stdin JSON ---
if [ -z "$message_text" ]; then
	if command -v jq >/dev/null 2>&1; then
		message_text="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
	else
		message_text="$(printf '%s' "$input" | grep -o '"last_assistant_message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | awk -F'"' '{print $4}')"
	fi
	_log "Layer 2 (last_assistant_message) extracted text length=${#message_text}"
fi

_log "Final extracted text length=${#message_text}"

# --- Skip tool-call-only turns or no extractable text ---
if [ -z "$message_text" ]; then
	_log "no assistant text found in any layer; skipping"
	exit 0
fi

# --- Pipe to susurro read --stdin with 5-second hard timeout via perl ---
# perl is always present on macOS; gtimeout/timeout are not guaranteed.
_log "Piping to susurro read --stdin"
_tmp="/tmp/susurro_hook_msg_$$"
printf '%s' "$message_text" > "$_tmp"
/usr/bin/perl -e '
use POSIX ":sys_wait_h";
alarm(5);
local $SIG{ALRM} = sub { exit 0 };
my $msg_file = $ARGV[0];
open(my $fh, "<", $msg_file) or exit 0;
my $text = do { local $/; <$fh> };
close $fh;
my $cwd_arg = $ARGV[1];
my @cmd = ("susurro", "read", "--stdin");
if (defined $cwd_arg && $cwd_arg ne "") { push @cmd, "--cwd", $cwd_arg; }
open(my $pipe, "|-", @cmd) or exit 0;
print $pipe $text;
close $pipe;
' "$_tmp" "$cwd" 2>/dev/null || true
rm -f "$_tmp"

exit 0
