(() => {
  const $ = (id) => document.getElementById(id);
  const kvRow = (k, v) => { const a = document.createElement('span'); a.textContent = k; const b = document.createElement('span'); b.textContent = v; b.title = v; $('kv').append(a, b); };
  const res = (n, d) => fetch(`https://${GetParentResourceName()}/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(d || {}) });
  function toast(text, kind) {
    const t = document.createElement('div');
    t.className = 't ' + (kind || 'info'); t.textContent = text;
    $('toasts').appendChild(t);
    setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 300); }, 4500);
  }
  let fullSrc = '', selR = null, drag = null, cat = '', sev = 'normal', T = {}, busy = false, hasShot = false, allowShot = true;

  function chips(el, items, get, set) {
    el.innerHTML = '';
    items.forEach((it) => {
      const b = document.createElement('button');
      b.className = (get() === it.id ? 'on' : '');
      if (it.k) b.style.setProperty('--k', it.k), b.classList.add('k');
      b.textContent = it.label;
      b.onclick = () => { set(it.id); [...el.children].forEach((c) => c.classList.remove('on')); b.classList.add('on'); };
      el.appendChild(b);
    });
  }
  function showSel() {
    const el = $('sel');
    el.classList.toggle('hidden', !selR);
    $('resetsel').classList.toggle('hidden', !selR);
    $('hint').textContent = !hasShot ? '' : (selR ? T.area : T.hint);
    if (selR) { el.style.left = selR.x * 100 + '%'; el.style.top = selR.y * 100 + '%'; el.style.width = selR.w * 100 + '%'; el.style.height = selR.h * 100 + '%'; }
  }
  function pt(e) {
    const r = $('wrap').getBoundingClientRect();
    return { x: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)), y: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height)) };
  }
  $('wrap').addEventListener('mousedown', (e) => { if (!hasShot) return; drag = pt(e); selR = null; showSel(); e.preventDefault(); });
  window.addEventListener('mousemove', (e) => {
    if (!drag) return;
    const p = pt(e);
    selR = { x: Math.min(drag.x, p.x), y: Math.min(drag.y, p.y), w: Math.abs(p.x - drag.x), h: Math.abs(p.y - drag.y) };
    showSel();
  });
  window.addEventListener('mouseup', () => {
    if (!drag) return;
    drag = null;
    if (selR && (selR.w < 0.04 || selR.h < 0.04)) selR = null;
    showSel();
  });
  $('resetsel').onclick = () => { selR = null; showSel(); };
  // original quality: full frame is sent untouched; a selected area is cropped at native resolution.
  // Only if the result is above ~6 MB it is re-encoded with lower quality, then downscaled.
  const LIMIT = 8000000;
  function cropped() {
    const img = $('img');
    if (!hasShot || !img.naturalWidth) return '';
    if (!selR && fullSrc && /^data:image\/(jpeg|png)/.test(fullSrc) && fullSrc.length <= LIMIT) return fullSrc;
    const nw = img.naturalWidth, nh = img.naturalHeight;
    const sx = selR ? Math.round(selR.x * nw) : 0, sy = selR ? Math.round(selR.y * nh) : 0;
    const sw = selR ? Math.max(1, Math.round(selR.w * nw)) : nw, sh = selR ? Math.max(1, Math.round(selR.h * nh)) : nh;
    let scale = 1, out = '';
    for (let step = 0; step < 6; step++) {
      const c = document.createElement('canvas'); c.width = Math.max(1, Math.round(sw * scale)); c.height = Math.max(1, Math.round(sh * scale));
      c.getContext('2d').drawImage(img, sx, sy, sw, sh, 0, 0, c.width, c.height);
      for (const q of [0.95, 0.85, 0.7]) { out = c.toDataURL('image/jpeg', q); if (out.length <= LIMIT) return out; }
      scale *= 0.75;
    }
    return out;
  }
  function setShot(src) {
    selR = null; fullSrc = src || '';
    hasShot = !!src;
    $('img').classList.toggle('hidden', !src);
    $('noshot').classList.toggle('hidden', !!src);
    $('noshot').textContent = T.noshot || '';
    if (src) $('img').src = src;
    $('f-shot').checked = !!src; $('f-shot').disabled = !src;
    $('shotcard').classList.toggle('hidden', !allowShot);
    $('send').disabled = false;
    $('resetsel').textContent = T.reset; showSel();
    $('retake').textContent = src ? T.retake : T.take;
    $('thumb').classList.toggle('off', !src);
  }
  function open(d) {
    T = d.text; busy = false; allowShot = d.allowShot !== false;
    $('sevrow').classList.toggle('hidden', !d.severity);
    $('h-title').textContent = T.title; $('h-shot').textContent = T.preview; $('h-ctx').textContent = T.ctx; $('auto').textContent = T.k_auto; $('count').textContent = T.subtitle;
    $('l-cat').textContent = T.category; $('l-sev').textContent = T.severity;
    $('f-title').placeholder = T.t_title; $('f-desc').placeholder = T.t_desc; $('f-steps').placeholder = T.t_steps;
    $('f-exp').placeholder = T.t_expected; $('f-act').placeholder = T.t_actual; $('f-console').placeholder = T.t_console;
    $('l-shot').textContent = T.screenshot;
    $('cancel').textContent = T.cancel; $('send').textContent = T.send;
    ['f-title', 'f-desc', 'f-steps', 'f-exp', 'f-act', 'f-console'].forEach((i) => ($(i).value = ''));
    $('err').classList.add('hidden');
    cat = d.categories[0] ? d.categories[0].id : ''; sev = 'normal';
    chips($('cats'), d.categories, () => cat, (v) => (cat = v));
    chips($('sevs'), [{ id: 'low', label: T.low, k: '#5b8def' }, { id: 'normal', label: T.normal, k: '#3fb37f' }, { id: 'high', label: T.high, k: '#e0a43b' }, { id: 'critical', label: T.critical, k: '#e5484d' }], () => sev, (v) => (sev = v));
    setShot(null);
    $('kv').innerHTML = '';
    const c = d.ctx || {};
    kvRow(T.k_pos, c.pos || '—'); kvRow(T.k_street, c.street || '—'); kvRow(T.k_zone, c.zone || '—'); kvRow(T.k_fps, String(c.fps || '—'));
    kvRow(T.k_hp, (c.health || 0) + ' / ' + (c.armor || 0)); if (c.vehicle) kvRow(T.k_veh, c.vehicle);
    $('adm').classList.remove('hidden', 'blank');
    setTimeout(() => $('f-title').focus(), 50);
  }
  function close() { $('adm').classList.add('hidden'); }
  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.type === 'open') open(d);
    else if (d.type === 'close') close();
    else if (d.type === 'blank') $('adm').classList.toggle('blank', !!d.on);
    else if (d.type === 'shot') setShot(d.shot);
    else if (d.type === 'toast') toast(d.text, d.kind);
  });
  $('x').onclick = $('cancel').onclick = () => res('close');
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !$('adm').classList.contains('hidden')) res('close'); });
  $('retake').onclick = () => res('retake');
  $('send').onclick = async () => {
    if (busy) return;
    const title = $('f-title').value.trim();
    const err = $('err');
    if (!title) { err.textContent = T.need_title; err.classList.remove('hidden'); return; }
    busy = true; $('send').disabled = true; $('send').textContent = T.sending; err.classList.add('hidden');
    try {
      const payload = {
        title, description: $('f-desc').value, reproduction: $('f-steps').value, expected: $('f-exp').value, actual: $('f-act').value, console: $('f-console').value,
        category: cat, severity: sev, includeShot: hasShot && $('f-shot').checked,
      };
      if (payload.includeShot) {
        // the NUI page is https (plain-http upload is blocked as mixed content); Lua streams it to the server as a latent event
        payload.shotData = cropped();
      }
      const r = await res('submit', payload);
      const j = await r.json();
      if (!j.ok) { busy = false; $('send').disabled = false; $('send').textContent = T.send; err.textContent = T.failed + (j.why ? ' (' + j.why + ')' : ''); err.classList.remove('hidden'); }
    } catch (_) { busy = false; $('send').disabled = false; $('send').textContent = T.send; err.textContent = T.failed; err.classList.remove('hidden'); }
  };
})();
