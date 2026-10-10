#!/bin/bash
SP="$1"; M="$(cd "$(dirname "$0")/../mockup" && pwd)/jornada.html"; C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; W="${3:-1440}"; H="${4:-1300}"; THEME="${5:-light}"
mkdir -p "$SP/v2"; i=0
for s in $2; do i=$((i+1)); n=$(printf "%02d" $i)_$(echo "$s" | tr '@#' '__')
{ echo "<!doctype html><html data-theme=\"$THEME\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><script>window.addEventListener('error',e=>{setTimeout(()=>document.body.insertAdjacentHTML('afterbegin','<div style=\"position:fixed;z-index:999;top:0;left:0;right:0;background:red;color:#fff;padding:20px;font-size:28px\">JSERR '+e.message+' @'+e.lineno+'</div>'),50)});</script>"; /bin/cat "$M"; echo "<script>window.addEventListener('load',()=>setTimeout(()=>mapGo('$s'),300));</script></body></html>"; } > "$SP/v2/t.html"
"$C" --headless=new --disable-gpu --hide-scrollbars --window-size=$W,$H --virtual-time-budget=5000 --screenshot="$SP/v2/$n.png" "file://$SP/v2/t.html" >/dev/null 2>&1
done
