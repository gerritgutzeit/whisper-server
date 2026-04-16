import Foundation

/// Single-page log UI served at `GET /` (no external assets).
enum TranscriptionLogWebResources {
    static let indexHTML: String = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>WhisperServer · Log</title>
  <style>
    :root {
      --bg0: #07080c;
      --bg1: #10121a;
      --card: rgba(255,255,255,0.045);
      --card-hover: rgba(255,255,255,0.075);
      --stroke: rgba(255,255,255,0.09);
      --text: rgba(255,255,255,0.92);
      --muted: rgba(255,255,255,0.52);
      --faint: rgba(255,255,255,0.32);
      --accent: #8b5cf6;
      --accent2: #22d3ee;
      --danger: #f87171;
      --radius: 14px;
      --shadow: 0 24px 80px rgba(0,0,0,0.55);
      --font: ui-sans-serif, system-ui, -apple-system, "SF Pro Text", "Segoe UI", sans-serif;
      --mono: ui-monospace, "SF Mono", Menlo, monospace;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: var(--font);
      color: var(--text);
      background: radial-gradient(1200px 800px at 10% -10%, rgba(139,92,246,0.18), transparent 55%),
                  radial-gradient(900px 600px at 100% 0%, rgba(34,211,238,0.12), transparent 50%),
                  linear-gradient(165deg, var(--bg0), var(--bg1) 45%, #0a0c14);
    }
    .wrap { max-width: 920px; margin: 0 auto; padding: 48px 24px 64px; }
    header {
      display: flex; flex-wrap: wrap; align-items: flex-end; justify-content: space-between; gap: 20px;
      margin-bottom: 36px;
    }
    .brand h1 {
      margin: 0 0 6px;
      font-size: clamp(1.6rem, 3vw, 2rem);
      font-weight: 650;
      letter-spacing: -0.03em;
      background: linear-gradient(120deg, #fff 0%, rgba(255,255,255,0.72) 40%, var(--accent2) 95%);
      -webkit-background-clip: text;
      background-clip: text;
      color: transparent;
    }
    .brand p { margin: 0; color: var(--muted); font-size: 0.95rem; max-width: 36rem; line-height: 1.45; }
    .actions { display: flex; gap: 10px; align-items: center; }
    button {
      font: inherit; font-size: 0.85rem; font-weight: 600;
      border: 1px solid var(--stroke);
      border-radius: 10px;
      padding: 10px 16px;
      cursor: pointer;
      color: var(--text);
      background: var(--card);
      backdrop-filter: blur(10px);
      transition: background 0.15s, border-color 0.15s, transform 0.12s;
    }
    button:hover { background: var(--card-hover); border-color: rgba(255,255,255,0.16); }
    button:active { transform: scale(0.98); }
    button.danger { color: #fecaca; border-color: rgba(248,113,113,0.35); }
    button.danger:hover { background: rgba(248,113,113,0.12); }
    button:disabled { opacity: 0.45; cursor: not-allowed; }
    .meta { font-size: 0.78rem; color: var(--faint); font-family: var(--mono); }
    #list { display: flex; flex-direction: column; gap: 14px; }
    .card {
      position: relative;
      overflow: hidden;
      border-radius: var(--radius);
      border: 1px solid var(--stroke);
      background: var(--card);
      box-shadow: var(--shadow);
      padding: 18px 20px 20px;
      backdrop-filter: blur(14px);
      animation: rise 0.45s ease backwards;
      cursor: copy;
      transition: border-color 0.16s ease, box-shadow 0.2s ease, background-color 0.2s ease;
    }
    .card::after {
      content: "";
      position: absolute;
      inset: 0;
      border-radius: inherit;
      pointer-events: none;
      opacity: 0;
      background: linear-gradient(120deg, rgba(34,211,238,0.12), rgba(139,92,246,0.08));
      transition: opacity 0.22s ease;
    }
    .card:hover { border-color: rgba(255,255,255,0.2); }
    .card.copied {
      border-color: rgba(34,211,238,0.75);
      box-shadow: 0 0 0 1px rgba(34,211,238,0.28), 0 24px 80px rgba(0,0,0,0.55);
      background-color: rgba(34,211,238,0.05);
    }
    .card.copied::after { opacity: 1; }
    @keyframes rise { from { opacity: 0; transform: translateY(10px); } }
    .card-top { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 10px; margin-bottom: 12px; }
    .time { font-family: var(--mono); font-size: 0.8rem; color: var(--accent2); letter-spacing: 0.02em; }
    .file { font-size: 0.8rem; color: var(--muted); max-width: 70%; word-break: break-all; }
    .text {
      font-size: 1.02rem; line-height: 1.55; color: rgba(255,255,255,0.88);
      white-space: pre-wrap; word-break: break-word;
    }
    .empty {
      text-align: center; padding: 56px 20px; color: var(--muted);
      border: 1px dashed var(--stroke); border-radius: var(--radius);
      background: rgba(255,255,255,0.02);
    }
    .empty strong { display: block; color: var(--text); margin-bottom: 8px; font-size: 1.05rem; }
    footer { margin-top: 40px; text-align: center; color: var(--faint); font-size: 0.8rem; }
    a { color: var(--accent2); text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <div class="brand">
        <h1>WhisperServer</h1>
        <p>Live transcription log from this instance. Plain text is shown (JSON wrappers are stripped). API: <a href="/v1/models">/v1/models</a></p>
      </div>
      <div class="actions">
        <button type="button" id="btn-refresh">Refresh</button>
        <button type="button" class="danger" id="btn-clear">Clear log</button>
      </div>
    </header>
    <p class="meta" id="status">Loading…</p>
    <div id="list"></div>
    <footer>WhisperServer · local log · auto-refresh every 4s</footer>
  </div>
  <script>
    const listEl = document.getElementById('list');
    const statusEl = document.getElementById('status');
    const btnRefresh = document.getElementById('btn-refresh');
    const btnClear = document.getElementById('btn-clear');
    let lastRenderedSignature = null;

    function setStatus(msg) { statusEl.textContent = msg; }

    function esc(s) {
      return String(s).replace(/[&<>"']/g, function(c) {
        return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]);
      });
    }

    function render(items) {
      if (!items.length) {
        listEl.innerHTML = '<div class="empty"><strong>No transcriptions yet</strong>POST audio to /v1/audio/transcriptions — entries appear here.</div>';
        return;
      }
      listEl.innerHTML = items.map(function(row, i) {
        var file = row.file ? '<div class="file">' + esc(row.file) + '</div>' : '<div class="file">—</div>';
        var text = String(row.text || '');
        return '<article class="card" data-copy="' + encodeURIComponent(text) + '" style="animation-delay:' + (i * 0.04) + 's">' +
          '<div class="card-top"><span class="time">' + esc(row.at) + '</span>' + file + '</div>' +
          '<div class="text">' + esc(text) + '</div></article>';
      }).join('');
    }

    async function copyText(text) {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text);
        return;
      }
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    }

    function signatureOf(items) {
      if (!Array.isArray(items)) return '[]';
      return items.map(function(row) {
        return [row.id || '', row.at || '', row.file || '', row.text || ''].join('||FIELD||');
      }).join('||ROW||');
    }

    async function load() {
      btnRefresh.disabled = true;
      try {
        const r = await fetch('/api/transcription-log', { headers: { 'Accept': 'application/json' } });
        if (!r.ok) throw new Error('HTTP ' + r.status);
        const data = await r.json();
        const items = Array.isArray(data) ? data : [];
        const newSignature = signatureOf(items);
        if (newSignature !== lastRenderedSignature) {
          render(items);
          lastRenderedSignature = newSignature;
        }
        setStatus('Last updated: ' + new Date().toLocaleTimeString() + ' · ' + data.length + ' ' + (data.length === 1 ? 'entry' : 'entries'));
      } catch (e) {
        setStatus('Error: ' + e.message);
      } finally {
        btnRefresh.disabled = false;
      }
    }

    async function clearLog() {
      if (!confirm('Clear all log entries on this machine?')) return;
      btnClear.disabled = true;
      try {
        const r = await fetch('/api/transcription-log', { method: 'DELETE' });
        if (r.status !== 204 && !r.ok) throw new Error('HTTP ' + r.status);
        await load();
      } catch (e) {
        setStatus('Clear failed: ' + e.message);
      } finally {
        btnClear.disabled = false;
      }
    }

    btnRefresh.addEventListener('click', load);
    btnClear.addEventListener('click', clearLog);
    listEl.addEventListener('click', async function(evt) {
      const card = evt.target.closest('.card');
      if (!card) return;
      try {
        const text = decodeURIComponent(card.getAttribute('data-copy') || '');
        if (!text) return;
        await copyText(text);
        card.classList.remove('copied');
        requestAnimationFrame(function() {
          card.classList.add('copied');
        });
        setTimeout(function() { card.classList.remove('copied'); }, 320);
        setStatus('Copied transcript to clipboard');
      } catch (e) {
        setStatus('Copy failed: ' + e.message);
      }
    });
    load();
    setInterval(load, 4000);
  </script>
</body>
</html>
"""
}
