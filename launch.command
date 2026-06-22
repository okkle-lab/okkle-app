#!/bin/bash
# Okkle — double-click launcher for Expo Go.
# Detects your WiFi IP, shows a scannable QR page, and starts the dev server.
# (On macOS, double-click this file in Finder. First time: right-click → Open.)

cd "$(dirname "$0")" || exit 1

# --- find the LAN IP this Mac is on -----------------------------------------
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
if [ -z "$IP" ]; then
  echo "⚠️  Couldn't find your WiFi IP. Make sure WiFi is on, then try again."
  IP="localhost"
fi
URL="exp://$IP:8081"

echo ""
echo "  📦  Okkle launcher"
echo "  ─────────────────────────────────────────"
echo "  Expo URL:  $URL"
echo ""

# --- generate a QR image for the URL ----------------------------------------
QR=/tmp/okkle-qr.png
npx --yes qrcode "$URL" -o "$QR" >/dev/null 2>&1

# --- write a small branded page that shows the QR + instructions ------------
HTML=/tmp/okkle-launch.html
cat > "$HTML" <<HTML
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Launch Okkle</title>
<style>
  :root { --brand:#1FB89A; --brandDeep:#0E8E78; --brandLight:#E2F6F1;
          --bg:#FBF9F6; --card:#FFFFFF; --text:#22302C; --sub:#6B756F; --border:#E8E6E0; }
  * { box-sizing:border-box; }
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
         background:var(--bg); font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
         color:var(--text); padding:32px; }
  .card { background:var(--card); border:1px solid var(--border); border-radius:26px;
          padding:40px; max-width:440px; width:100%; text-align:center;
          box-shadow:0 8px 30px rgba(0,0,0,0.06); }
  .logo { font-size:30px; font-weight:700; letter-spacing:-1px; color:var(--brand); margin:0 0 4px; }
  .tag  { font-size:14px; color:var(--sub); margin:0 0 28px; }
  .qrwrap { background:#fff; border:1px solid var(--border); border-radius:18px; padding:20px;
            display:inline-block; }
  .qrwrap img { width:240px; height:240px; display:block; image-rendering:pixelated; }
  .url { margin-top:22px; font-size:14px; color:var(--brandDeep); font-weight:600;
         background:var(--brandLight); border-radius:999px; padding:8px 16px; display:inline-block; }
  ol { text-align:left; color:var(--sub); font-size:14px; line-height:1.7; margin:26px 0 0; padding-left:20px; }
  b { color:var(--text); }
</style>
<div class="card">
  <p class="logo">Okkle</p>
  <p class="tag">Scan to open in Expo Go</p>
  <div class="qrwrap"><img src="file://$QR" alt="QR code"></div>
  <div class="url">$URL</div>
  <ol>
    <li>Make sure your iPhone is on the <b>same WiFi</b> as this Mac.</li>
    <li>Open the <b>Camera</b> app (or Expo Go → Scan QR code).</li>
    <li>Point it at the QR above and tap the banner.</li>
  </ol>
</div>
HTML

# open the page, then start Metro (its own QR also appears in this terminal)
open "$HTML"
echo "  Opening the QR page… keep this window open while you use the app."
echo "  Press Ctrl+C here to stop the server."
echo ""

exec npx expo start
