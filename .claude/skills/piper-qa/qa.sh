#!/bin/zsh
# Build, start, drive, capture, and stop PiperQA: a copy of Piper with its own
# bundle identifier, home folder, and folder of files. PiperQA starts with
# -PiperQA YES, so it never becomes the active app.
#
# Usage:
#   qa.sh start [repo-dir]   Build the repo (default: current folder), then start PiperQA with its main window.
#   qa.sh js <body>          Run the body of an async function in the editor page. Prints its return value as JSON.
#   qa.sh type <text>        Insert text at the end of the open file in the editor page.
#   qa.sh shot <name>        Save a screenshot of a PiperQA window to $QA/<name>.png.
#   qa.sh stop               Quit PiperQA and remove the screenshots.
#
# QA (default /tmp/piper-qa) holds PiperQA.app, home/, folder/, and the screenshots.
set -euo pipefail

QA=${QA:-/tmp/piper-qa}
APP=$QA/PiperQA.app
AD=agent-desktop
HERE=${0:A:h}
POST=$QA/qa-post
RESULT=$QA/result.txt

qa_pid() {
	pgrep -f "$APP/Contents/MacOS/" | head -1 || true
}

windows() {
	$AD list-windows --app PiperQA | python3 -I -c '
import json, sys
for w in json.load(sys.stdin).get("data") or []:
    print(w["id"], w.get("is_focused"), w.get("title"), sep="\t")'
}

run_js() {
	[[ -n $(qa_pid) ]] || { echo "qa.sh: PiperQA is not running" >&2; return 1; }
	if [[ ! -x $POST || $HERE/qa-post.swift -nt $POST ]]; then
		swiftc -O -o "$POST" "$HERE/qa-post.swift"
	fi
	rm -f "$RESULT"
	"$POST" "$1"
	for _ in {1..50}; do [[ -f $RESULT ]] && break; sleep 0.1; done
	[[ -f $RESULT ]] || { echo "qa.sh: no result in 5 s. The build has no QA hooks, or the editor page is not loaded." >&2; return 1; }
	local qa_status
	qa_status=$(head -1 "$RESULT")
	tail -n +2 "$RESULT"
	echo
	[[ $qa_status == ok ]]
}

case ${1:-} in
start)
	repo=${2:-$PWD}
	[[ -f $repo/Makefile ]] || { echo "qa.sh: no Makefile in $repo" >&2; exit 1; }
	pkill -f "$APP/Contents/MacOS/" 2>/dev/null || true
	make -C "$repo" build | tail -1
	mkdir -p "$QA/home/Library" "$QA/folder/Notes"
	rm -rf "$APP"
	cp -R "$repo/build/Piper.app" "$APP"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.piper.qa" -c "Set :CFBundleName PiperQA" "$APP/Contents/Info.plist"
	codesign --force --sign - "$APP" 2>/dev/null
	defaults delete com.piper.qa 2>/dev/null || true
	if [[ -z $(ls -A "$QA/folder/Notes") ]]; then
		printf -- '---\nstatus: draft\n---\n# First note\n\nA note for the QA run. See [[Second note]].\n\n- [ ] Open a file\n' > "$QA/folder/Notes/First note.md"
		printf '# Second note\n\nThe second note.\n' > "$QA/folder/Notes/Second note.md"
	fi
	open -g -n -a "$APP" --env CFFIXED_USER_HOME="$QA/home" --args -wikiPath "$QA/folder" -PiperQA YES -PiperQAResult "$RESULT"
	for _ in {1..20}; do [[ -n $(qa_pid) && -n $(windows) ]] && break; sleep 0.5; done
	[[ -n $(qa_pid) ]] || { echo "qa.sh: PiperQA did not start" >&2; exit 1; }
	[[ -n $(windows) ]] || { echo "qa.sh: no main window. The build has no QA hooks (branch qa-hooks)." >&2; exit 1; }
	echo "PiperQA started. Folder: $QA/folder"
	;;
js)
	run_js "${2:?usage: qa.sh js <body>}"
	;;
type)
	text=$(python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1]))' "${2:?usage: qa.sh type <text>}")
	run_js "
const el = document.querySelector('[contenteditable=true]');
if (!el) throw new Error('no editable element in the editor page');
el.focus();
const range = document.createRange();
range.selectNodeContents(el);
range.collapse(false);
const selection = getSelection();
selection.removeAllRanges();
selection.addRange(range);
return document.execCommand('insertText', false, $text);"
	;;
shot)
	name=${2:?usage: qa.sh shot <name>}
	id=$(windows | awk -F'\t' '$2=="True"{print $1; exit}')
	[[ -n $id ]] || id=$(windows | head -1 | cut -f1)
	[[ -n $id ]] || { echo "qa.sh: PiperQA has no window" >&2; exit 1; }
	out=$QA/$name.png
	rm -f "$out"
	$AD screenshot --window-id "$id" "$out" >/dev/null
	sips -Z 1400 "$out" >/dev/null
	echo "$out"
	;;
stop)
	$AD close-app PiperQA >/dev/null 2>&1 || pkill -f "$APP/Contents/MacOS/" 2>/dev/null || true
	find "$QA" -maxdepth 1 -name '*.png' -delete 2>/dev/null
	rm -f "$RESULT"
	echo "PiperQA stopped."
	;;
*)
	sed -n 7,11p "$0" >&2
	exit 1
	;;
esac
