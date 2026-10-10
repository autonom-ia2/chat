// ---------- estado do protótipo ----------
const S = {
  agents: structuredClone(AGENTS),
  profile: 'manage', // manage | view | super
  build: null,
  period: 30,
  view: {}, // estado simulado por tela: { lista: 'normal' }
  open: null, // menus/desenhos abertos
};

// ---------- utilidades ----------
const $ = (s, el = document) => el.querySelector(s);
const esc = (s) => String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const icon = (n, cls = 'ico') => `<i data-lucide="${n}" class="${cls}" aria-hidden="true"></i>`;
const can = () => S.profile !== 'view';
const isSuper = () => S.profile === 'super';
const agentById = (id) => S.agents.find((a) => a.id === id);
// D32: gênero vem de "Tratar por" (config.voice), nunca da última letra do nome
const isEle = (a) => (a.voice ? a.voice === 'masculina' : a.actuation === 'internal');
const ela = (a) => (isEle(a) ? 'ele' : 'ela');
const artigo = (a) => (isEle(a) ? 'o' : 'a');
const channelById = (id) => CHANNELS.find((c) => c.id === id);
function paint() { if (window.lucide) window.lucide.createIcons(); }

function toast(text, tone = 'ok') {
  document.querySelectorAll('.toast').forEach((t) => t.remove());
  const t = document.createElement('div');
  t.className = 'toast'; t.setAttribute('role', 'status');
  t.innerHTML = icon(tone === 'ok' ? 'check' : 'alert-triangle') + esc(text);
  document.body.appendChild(t); paint();
  setTimeout(() => t.remove(), 3400);
}

// Diálogo com foco preso, Esc e clique fora devolvem o foco ao gatilho.
function dialog({ title, body, confirm, danger, onOk, wide, html, okDisabled }) {
  const layer = $('#layer');
  const prev = document.activeElement;
  layer.innerHTML = `<div class="scrim" data-scrim><div class="dlg ${wide ? 'wide' : ''}" role="dialog" aria-modal="true" aria-labelledby="dlgT">
    <h2 id="dlgT">${esc(title)}</h2>${body ? `<p class="muted">${body}</p>` : ''}${html || ''}
    <div class="acts"><button class="btn outline" data-dlg-close>${confirm ? 'Cancelar' : 'Fechar'}</button>
    ${confirm ? `<button class="btn ${danger ? 'danger' : 'primary'}" id="dlgOk" ${okDisabled ? 'disabled' : ''}>${esc(confirm)}</button>` : ''}</div></div></div>`;
  paint();
  const dlg = layer.querySelector('.dlg');
  const close = () => { layer.innerHTML = ''; document.removeEventListener('keydown', onKey); prev && prev.focus && prev.focus(); };
  const onKey = (e) => {
    if (e.key === 'Escape') close();
    if (e.key === 'Tab') {
      const f = [...dlg.querySelectorAll('button,input,textarea,[tabindex="0"]')].filter((x) => !x.disabled);
      if (!f.length) return;
      if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f[f.length - 1].focus(); }
      else if (!e.shiftKey && document.activeElement === f[f.length - 1]) { e.preventDefault(); f[0].focus(); }
    }
  };
  document.addEventListener('keydown', onKey);
  layer.querySelector('[data-scrim]').addEventListener('click', (e) => { if (e.target.hasAttribute('data-scrim')) close(); });
  layer.querySelector('[data-dlg-close]').addEventListener('click', close);
  const ok = $('#dlgOk');
  if (ok) ok.addEventListener('click', () => { if (onOk && onOk(dlg) === false) return; close(); });
  (dlg.querySelector('input,textarea') || ok || layer.querySelector('[data-dlg-close]')).focus();
  return dlg;
}

// Barra de estados simulados (só no protótipo).
function stateBar(key, options) {
  const cur = S.view[key] || options[0][0];
  return `<div class="statebar" role="group" aria-label="Estado da tela (protótipo)">${icon('eye', 'ico')}<span>Ver esta tela como:</span>
    ${options.map(([k, l]) => `<button data-state="${key}:${k}" aria-pressed="${cur === k}">${esc(l)}</button>`).join('')}</div>`;
}
const viewState = (key, def) => S.view[key] || def;

function statusPill(a) {
  if (a.status === 'on') return '<span class="pill on"><span class="dot"></span>Atendendo</span>';
  if (a.status === 'off') return '<span class="pill off"><span class="dot slate"></span>Pausado</span>';
  if (a.status === 'ready') return '<span class="pill ready"><span class="dot" style="background:var(--brand)"></span>Pronto para ligar</span>';
  return '<span class="pill todo"><span class="dot amber"></span>Falta terminar</span>';
}
function switchBtn(a) {
  if (!can() || !(a.status === 'on' || a.status === 'off')) return '';
  const on = a.status === 'on';
  return `<button class="sw" role="switch" aria-checked="${on}" data-toggle="${a.id}" aria-label="${on ? 'Atendendo' : 'Pausado'}: ${esc(a.name)}"><span class="track"></span>${on ? 'Atendendo' : 'Pausado'}</button>`;
}
const avatar = (a, size = '') => `<span class="av ${a.color}" ${size ? `style="${size}"` : ''} aria-hidden="true">${esc(a.name[0])}</span>`;

const stepsBar = (cur, names = ['Escolha', 'Conte', 'Teste', 'Ligue']) => `<ol class="steps" aria-label="Etapas">${names.map((n, i) => {
  const c = i < cur ? 'past' : i === cur ? 'cur' : '';
  const bar = i < names.length - 1 ? `<span class="bar ${i < cur ? 'past' : ''}" aria-hidden="true"></span>` : '';
  return `<li class="step ${c}" ${i === cur ? 'aria-current="step"' : ''}><span class="n">${i < cur ? icon('check') : i + 1}</span>${n}</li>${bar}`;
}).join('')}</ol>`;

function meter(label, pct) {
  const tone = pct >= 70 ? 'teal' : pct >= 40 ? 'amber' : 'red';
  const word = pct >= 70 ? 'boa' : pct >= 40 ? 'razoável' : 'fraca';
  return `<div class="meter"><div class="row"><span>${esc(label)}</span><b>${pct}% · ${word}</b></div>
    <div class="progress ${tone}" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${pct}" aria-label="${esc(label)}"><i style="width:${pct}%"></i></div></div>`;
}

// Cartão de material com todos os estados reais de Source.
const MAT_STATES = {
  sending: { st: '<span class="spin" aria-hidden="true"></span>Enviando', cls: '' },
  analyzing: { st: '<span class="spin" aria-hidden="true"></span>Lendo', cls: '' },
  failed: { st: `${icon('file-x')}Não deu para ler`, cls: 'warn', why: 'Confira se o arquivo tem menos de 25 MB, não tem senha e é PDF, Word, Excel, TXT, MD ou JSON.', act: 'Enviar de novo' },
  resend: { st: `${icon('alert-triangle')}Precisa de outro arquivo`, cls: 'warn', why: 'O texto saiu cortado. Envie uma versão com o conteúdo completo.', act: 'Enviar de novo' },
  review: { st: `${icon('clock')}Ainda não conferido`, cls: 'warn', why: 'Lido, mas a conferência não terminou. O agente ainda não usa este material.', act: 'Enviar de novo' },
  offscope: { st: `${icon('ban')}Não é sobre o seu negócio`, cls: 'warn', why: 'O agente não usa este material. Tire ou troque por um sobre o seu negócio.' },
  accepted: { st: `${icon('check')}Pronto`, cls: 'good' },
};
function matCard(m, { removable = true, agentId = '' } = {}) {
  const s = MAT_STATES[m.state];
  const isLink = m.type === 'link';
  const fi = m.kind === 'media' ? 'image' : isLink ? 'link' : 'file-text';
  const color = m.state === 'accepted' ? 'var(--t11)' : s.cls === 'warn' ? 'var(--a11)' : 'var(--s11)';
  return `<div class="mat ${s.cls}">
    <div class="hd"><span class="fi">${icon(fi)}</span><span class="nm">${esc(m.name)}</span>
      <span class="st" style="color:${color}">${s.st}</span>
      ${removable && can() ? `<button class="iconbtn" aria-label="Tirar ${esc(m.name)}" data-rmmat="${agentId}:${m.id}">${icon('trash-2')}</button>` : ''}</div>
    ${m.state === 'accepted' && m.resumo ? `<div class="why">Nota ${m.nota} de 10 · ${m.label} · certeza ${m.conf}. ${esc(m.resumo)}</div>` : ''}
    ${s.why ? `<div class="why">${esc(s.why)}</div>` : ''}
    ${s.act && can() ? `<div><button class="btn outline" data-resend="${agentId}:${m.id}">${icon('upload')}${s.act}</button></div>` : ''}
  </div>`;
}

const CH_LABEL = (id) => (channelById(id) || { name: '' }).name;
