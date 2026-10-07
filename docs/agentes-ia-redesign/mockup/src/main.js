// ---------- moldura ----------
function shell() {
  document.body.insertAdjacentHTML('afterbegin', `
  <div class="proto" role="region" aria-label="Controles do protótipo">
    <b>Protótipo · Agentes</b>
    <button class="mapbtn" data-act="mapa">${icon('map')} Todas as telas</button>
    <span class="sep" aria-hidden="true"></span>
    <span class="seg" role="group" aria-label="Ver como"><span class="lbl">Ver como:</span>
      <button data-profile="manage">Pode editar</button><button data-profile="view">Só pode ver</button><button data-profile="super">Admin da plataforma</button></span>
    <span class="note">Dados reais da conta Hub2you (05/10). Respostas do teste e conversas são exemplos. <b>Novo</b> = precisa de backend.</span>
  </div>
  <div class="app">
    <aside class="side" aria-label="Menu">
      <div class="acct"><span class="logo" aria-hidden="true"></span>Hub2you</div>
      ${[['list-checks', 'Primeiros passos'], ['inbox', 'Caixa de Entrada'], ['message-circle', 'Conversas'], ['repeat', 'Automações']].map(([i, l]) => `<a href="#lista" tabindex="-1">${icon(i)}${l}</a>`).join('')}
      <a href="#lista" class="on">${icon('bot')}Agentes de IA</a>
      ${[['search', 'Prospecção'], ['shield-check', 'Cotação'], ['contact', 'Relacionamentos'], ['kanban', 'CRM'], ['megaphone', 'Campanhas'], ['library', 'Central de Ajuda']].map(([i, l]) => `<a href="#lista" tabindex="-1">${icon(i)}${l}</a>`).join('')}
    </aside>
    <main class="main" id="main" tabindex="-1"></main>
  </div><div id="layer"></div>`);
}

// ---------- roteador ----------
const ROUTES = { lista: viewLista, escolha: viewEscolha, conte: viewConte, teste: viewTeste, ligue: viewLigue, pronto: viewPronto, conectar: viewConectar, conversa: viewConversa };
let lastRoute = 'lista';
function current() { return location.hash.slice(1) || 'lista'; }
function go(r) { if (current() === r) render(); else location.hash = r; }
function render() {
  const r = current();
  const main = $('#main');
  if (r.startsWith('agente-')) { const [, id, tab] = r.split('-'); main.innerHTML = viewAgente(id, tab || 'resumo'); }
  else main.innerHTML = (ROUTES[r] || viewLista)();
  document.querySelectorAll('[data-profile]').forEach((b) => b.setAttribute('aria-current', String(b.dataset.profile === S.profile)));
  paint();
  const ta = $('#answer');
  if (ta) ta.addEventListener('input', () => { ta.style.height = 'auto'; ta.style.height = ta.scrollHeight + 'px'; });
}
window.addEventListener('hashchange', () => {
  const r = current();
  if (r !== lastRoute) { S.open = null; window.scrollTo(0, 0); $('#main').focus({ preventScroll: true }); }
  if (!r.startsWith('conectar')) lastRoute = r;
  render();
});

// ---------- ações ----------
function answer(text) {
  const b = S.build; const s = script()[b.turn];
  if (!text.trim() || !s) return;
  b.answers[s.key] = text.trim(); b.turn += 1;
  if (text.includes('hub2you.ai')) b.linkHint = true;
  render();
}
function progressMaterial(list, m, done = 'accepted') {
  list.push(m); render();
  setTimeout(() => { m.state = 'analyzing'; render(); }, 900);
  setTimeout(() => { m.state = done; render(); }, 2300);
}
function playTest(holder, q) {
  const idx = holder.tested.length;
  holder.tested.push(q); holder.chunks[idx] = 0; holder.stale = false; render();
  const total = TEST_ANSWERS[q].a.length; // perguntas genéricas por trabalho (D28)
  const tick = () => { holder.chunks[idx] += 1; render(); if (holder.chunks[idx] < total) setTimeout(tick, 800); };
  setTimeout(tick, 900);
}
function toggleAgent(id) {
  const a = agentById(id);
  const internal = a.actuation === 'internal';
  if (a.status === 'on') {
    dialog({ title: `Pausar ${artigo(a)} ${a.name}?`,
      body: internal ? `O ${a.name} some do painel das conversas até você ligar de novo.` : `As conversas que estão com ${ela(a)} vão para a equipe agora. As novas mensagens chegam direto para as pessoas até você ligar de novo.`,
      confirm: 'Pausar', onOk: () => { a.status = 'off'; render(); toast(internal ? `${a.name} pausado.` : `${a.name} pausad${artigo(a)}. As conversas foram para a equipe.`); } });
  } else { a.status = 'on'; render(); toast(`${a.name} voltou a atender.`); }
}
function saveNewAgent(on) {
  const b = S.build; const internal = isInternal();
  const nome = bName();
  S.agents = S.agents.filter((x) => x.id !== 'novo');
  CHANNELS.forEach((c) => { if (c.busyBy === 'novo') c.busyBy = null; });
  const zero = { conv: 0, replies: 0, handed: 0, conf: null, know: null, reasons: [] };
  const a = { id: 'novo', name: nome, color: 'violet', type: b.model, actuation: internal ? 'internal' : 'external', status: on ? 'on' : 'ready', mode: 'guided',
    channels: on && !internal ? [b.channel] : [], card: internal ? 'Ajuda a equipe: resume a conversa e sugere a próxima resposta.' : `Conversa com donos e gestores de corretoras que chegam pelo site e chama a equipe quando pedem preço ou demonstração.`,
    greeting: bGreeting(), fallback: 'Não sei responder isso com segurança. Vou chamar alguém da equipe.', tone: '', handoff: 'low_confidence', threshold: 0.6,
    window: b.window, audience: null, starters: b.starters || [], base: b.files.some((f) => f.state === 'accepted') ? 71 : null, faqOn: false, faq: [], versions: [],
    files: b.files, media: b.media, stats: { 7: zero, 30: zero }, serie: {}, stepName: 'Ligue' };
  S.agents.push(a);
  if (on && !internal) channelById(b.channel).busyBy = 'novo';
  if (on) { S.build = null; go('pronto'); } else { b.answers.nome = nome; go('lista'); toast(`${nome} guardad${artigo(a)}. Ligue quando quiser.`); }
}

const ACTIONS = {
  mapa: openMap,
  sair() {
    const b = S.build; const r = current();
    const stepName = { conte: 'Conte', teste: 'Teste', ligue: 'Teste' }[r] || 'Conte';
    S.agents = S.agents.filter((x) => x.id !== 'novo' || x.status === 'on' || x.status === 'off');
    if (r === 'escolha') { go('lista'); return; } // o rascunho só nasce depois da Escolha (§6.6)
    if (b && b.model) {
      const zero = { conv: 0, replies: 0, handed: 0, conf: null, know: null, reasons: [] };
      const tested = b.tested.some((q, i) => (b.chunks[i] ?? 99) >= TEST_ANSWERS[q].a.length) && !b.stale; // §6.6: E4 com teste válido
      S.agents.push({ id: 'novo', name: b.answers.nome || 'Novo agente', color: 'violet', type: b.model, actuation: isInternal() ? 'internal' : 'external', status: (r === 'ligue' || (r === 'teste' && tested)) ? 'ready' : 'todo', stepName, empty: !Object.keys(b.answers).length, channels: [], card: 'Montagem pela metade.', greeting: b.greeting || '', fallback: '', tone: '', handoff: 'low_confidence', threshold: 0.6, window: 'always', audience: null, starters: [], base: null, faqOn: false, faq: [], versions: [], files: b.files, media: b.media, stats: { 7: zero, 30: zero }, serie: {} });
      toast('Guardado. Continue quando quiser.');
    }
    go('lista');
  },
  anexar() {
    const b = S.build;
    if (!b || current() !== 'conte') { toast('No produto abre a escolha de arquivo.'); return; }
    if (b.images.length >= 4) { toast('Até 4 imagens por mensagem.', 'warn'); return; }
    b.images.push(`print-${b.images.length + 1}.png`); render();
  },
  'link-sim'() { const b = S.build; b.linkAdded = true; progressMaterial(b.files, { id: 'l' + Date.now(), kind: 'knowledge', name: 'hub2you.ai/chat2you', type: 'link', state: 'sending', nota: 7, label: 'Boa', conf: 'média', resumo: 'Página do Chat2You: canais, agentes e planos.' }); toast('Link adicionado. Lendo agora.'); },
  'link-nao'() { S.build.linkAdded = true; render(); },
  'usar-pdf'() { const b = S.build; if (b.files.some((f) => f.id === 's1')) return; progressMaterial(b.files, { ...PDF_CLARA, state: 'sending' }); },
  'demo-falha'() { const b = S.build; progressMaterial(b.files, { id: 'f' + Date.now(), kind: 'knowledge', name: 'contrato-escaneado.pdf', type: 'pdf', state: 'sending' }, 'failed'); },
  'add-media'() { const b = S.build; b.media.push({ id: 'm' + Date.now(), kind: 'media', name: 'tela-do-chat2you.png', type: 'png', state: 'accepted' }); render(); },
  'add-link'() { addMaterialDialog(S.build.files, true); },
  'add-material'() { const a = agentById(current().split('-')[1]); addMaterialDialog(S.sabeTab === 'media' ? a.media : a.files, false, S.sabeTab === 'media'); },
  'limpar-teste'() { const h = current() === 'teste' ? S.build : S.ptest; h.tested = []; h.chunks = {}; render(); },
  ligar() { saveNewAgent(true); },
  'ligar-depois'() { saveNewAgent(false); },
  reconversar() {
    const a = agentById(current().split('-')[1]);
    dialog({ title: `Mudar ${artigo(a)} ${a.name} conversando`, wide: true, confirm: 'Concluir',
      html: `<div class="chat" style="min-height:12rem"><div class="who"><span class="mini">${icon('sparkles')}</span>Construtor</div><div class="msg bot">O que você quer mudar ${a.name.endsWith('a') ? 'na' : 'no'} ${esc(a.name)}? Ex.: "passe a perguntar o número de atendentes antes de falar de preço".</div></div>
        <form class="composer" onsubmit="event.preventDefault()"><button type="button" class="iconbtn" aria-label="Anexar">${icon('paperclip')}</button><label for="rc" class="sr">Mudança</label><textarea id="rc" rows="2" placeholder="Escreva o que mudar"></textarea><button class="iconbtn send" aria-label="Enviar">${icon('arrow-up')}</button></form>
        <p class="small">A conversa continua de onde parou na montagem. Toda mudança vira uma versão nova, e dá para voltar.</p>`,
      onOk: () => toast('Mudanças salvas.') });
  },
  'tool-new'() { toolDialog(); },
  'tool-model'() { const a = agentById(current().split('-')[1]); a.tools = [{ name: 'Consulta de estoque', slug: 'consultar_estoque', method: 'POST', when: 'Quando o cliente perguntar se um item tem em estoque.', on: true }]; render(); },
  wrong() {
    S.open = null; render();
    const opts = ['Informação errada', 'Resposta inadequada', 'Resposta incompleta', 'Informação desatualizada', 'Outro'];
    const dlg = dialog({ title: 'Marcar esta resposta como errada', confirm: 'Marcar como errada', okDisabled: true,
      body: 'Conte o que saiu errado. Só a equipe vê. Ajuda quem cuida do agente a corrigir.',
      html: `<div class="field"><label>O que houve</label><div class="chipsel" role="radiogroup">${opts.map((o) => `<button role="radio" aria-pressed="false" data-wr="${o}">${o}</button>`).join('')}</div></div>
        <div class="field"><label for="wrd">Qual seria a resposta certa? (se souber)</label><textarea id="wrd" rows="3"></textarea></div>`,
      onOk: () => toast('Obrigado. A resposta foi marcada como errada.') });
    dlg.querySelectorAll('[data-wr]').forEach((b) => b.addEventListener('click', () => { dlg.querySelectorAll('[data-wr]').forEach((x) => x.setAttribute('aria-pressed', 'false')); b.setAttribute('aria-pressed', 'true'); $('#dlgOk').disabled = false; }));
  },
};

function addMaterialDialog(list, linkOnly, media) {
  let mode = linkOnly ? 'link' : media ? 'file' : 'link';
  const html = () => `${linkOnly || media ? '' : `<div class="seg2" role="group" aria-label="Tipo"><button aria-pressed="${mode === 'link'}" data-mm="link">Um link</button><button aria-pressed="${mode === 'file'}" data-mm="file">Um arquivo</button></div>`}
    ${mode === 'link' ? '<div class="field"><label for="mlink">Link</label><input id="mlink" type="url" placeholder="https://exemplo.com/pagina" value="https://hub2you.ai/protege"></div>'
    : `<div class="drop">${icon('upload')}<span>${media ? 'Foto, vídeo ou PDF para enviar ao cliente' : 'PDF, Word, Excel, TXT, MD ou JSON · até 25 MB'}</span><button class="btn link">Escolher arquivo</button></div>`}
    <p class="small">${media ? 'O agente manda quando fizer sentido na conversa.' : 'Word e Excel ainda podem perder parte do conteúdo. Depois de enviar, ele lê e confere cada material.'}</p>`;
  const dlg = dialog({ title: media ? 'Adicionar mídia' : linkOnly ? 'Colar um link' : 'Adicionar material', confirm: 'Adicionar', html: `<div id="mmb">${html()}</div>`,
    onOk: () => {
      if (media) { list.push({ id: 'm' + Date.now(), kind: 'media', name: 'catalogo-planos.pdf', type: 'pdf', state: 'accepted' }); render(); toast('Mídia adicionada.'); return true; }
      const name = mode === 'link' ? ($('#mlink').value || 'link').replace('https://', '') : 'tabela-planos-2026.xlsx';
      progressMaterial(list, { id: 'n' + Date.now(), kind: 'knowledge', name, type: mode === 'link' ? 'link' : 'xlsx', state: 'sending', nota: 7, label: 'Boa', conf: 'média', resumo: 'Conteúdo novo lido e conferido.' });
      toast('Adicionado. Lendo agora.');
      return true;
    } });
  dlg.addEventListener('click', (e) => { const t = e.target.closest('[data-mm]'); if (!t) return; mode = t.dataset.mm; $('#mmb').innerHTML = html(); paint(); });
}

function toolDialog() {
  const a = agentById(current().split('-')[1]);
  dialog({ title: 'Nova ferramenta', wide: true, confirm: 'Salvar ferramenta',
    html: `<div class="field"><label for="tn">Nome</label><input id="tn" value="Consulta de estoque"></div>
      <div class="field"><label for="ts">Identificador</label><input id="ts" class="mono" value="consultar_estoque"><span class="small">Só letras, números e _. Até 64.</span></div>
      <div class="field"><label for="tw">Quando usar</label><textarea id="tw" rows="2">Quando o cliente perguntar se um item tem em estoque.</textarea></div>
      <div class="field"><label>Método</label><div class="chipsel" role="radiogroup"><button role="radio" aria-pressed="false">GET</button><button role="radio" aria-pressed="true">POST</button></div></div>
      <div class="field"><label for="tu">Endereço</label><input id="tu" class="mono" value="https://api.exemplo.com/estoque"></div>
      <div class="field"><label for="tb">Corpo (JSON)</label><textarea id="tb" class="mono" rows="3">{ "q": "{{q}}", "limit": 5 }</textarea></div>
      <div class="field"><label>Cabeçalhos</label><div class="kv"><input aria-label="Nome" class="mono" value="x-api-key"><input aria-label="Valor" value="••••••••"><label class="check2"><input type="checkbox" checked>Segredo</label><button class="iconbtn" aria-label="Tirar">${icon('trash-2')}</button></div><button class="btn link" style="justify-self:start">${icon('plus')}Mais um</button></div>
      <div class="field"><label>Informações que ela pede ao cliente</label><div class="kv"><input aria-label="Nome" class="mono" value="q"><input aria-label="Para que serve" value="O que o cliente está procurando"><label class="check2"><input type="checkbox" checked>Obrigatório</label><button class="iconbtn" aria-label="Tirar">${icon('trash-2')}</button></div></div>
      <button class="sw" role="switch" aria-checked="true"><span class="track"></span>Ligada</button>`,
    onOk: () => { a.tools = a.tools || []; if (a.tools.length >= 10) { toast('Limite de 10 ferramentas por agente.', 'warn'); return false; } a.tools.push({ name: $('#tn').value, slug: $('#ts').value, method: 'POST', when: $('#tw').value, on: true }); render(); toast('Ferramenta salva.'); return true; } });
}

document.addEventListener('click', (e) => {
  const t = e.target.closest('button,a'); if (!t) return;
  const d = t.dataset;
  if (t.closest('#layer') && !d.mapgo && !d.wr && !d.mm) return;
  if (d.go) { e.preventDefault(); if (d.go === 'escolha' && !S.build) S.build = newBuild(null); go(d.go); return; }
  if (d.back !== undefined) { go(lastRoute); return; }
  if (d.profile) { S.profile = d.profile; render(); return; }
  if (d.open) { go(`agente-${d.open}-resumo`); return; }
  if (d.state) { const [k, v] = d.state.split(':'); S.view[k] = v; render(); return; }
  if (d.menu) { S.open = S.open === d.menu ? null : d.menu; render(); return; }
  if (d.model) { S.build = S.build && current() === 'escolha' ? S.build : newBuild(null); S.build.model = d.model; if (current() !== 'escolha') go('escolha'); else render(); return; }
  if (d.ans) { answer(d.ans); return; }
  if (d.q) { playTest(current() === 'teste' ? S.build : S.ptest, d.q); return; }
  if (d.ch) { S.build.channel = Number(d.ch); render(); return; }
  if (d.bwin) { S.build.window = d.bwin; render(); return; }
  if (d.btab) { S.build.tab = d.btab; render(); return; }
  if (d.rmimg) { S.build.images.splice(Number(d.rmimg), 1); render(); return; }
  if (d.rmstarter) { S.build.starters.splice(Number(d.rmstarter), 1); render(); return; }
  if (d.rmmat) {
    const [aid, mid] = d.rmmat.split(':');
    const list = aid === 'build' ? null : agentById(aid);
    const arr = aid === 'build' ? (S.build.tab === 'media' ? S.build.media : S.build.files) : (S.sabeTab === 'media' ? list.media : list.files);
    const m = arr.find((x) => x.id === mid);
    if (!m) { toast('Material de exemplo.'); return; }
    dialog({ title: `Tirar "${m.name}"?`, body: 'O agente deixa de usar este material. Não dá para desfazer.', confirm: 'Tirar', danger: true,
      onOk: () => { arr.splice(arr.indexOf(m), 1); render(); toast('Material tirado.'); } });
    return;
  }
  if (d.resend) { const [aid, mid] = d.resend.split(':'); const arr = aid === 'build' ? S.build.files : agentById(aid).files; const m = arr.find((x) => x.id === mid); if (m) { arr.splice(arr.indexOf(m), 1); progressMaterial(arr, { ...m, state: 'sending', nota: 7, label: 'Boa', conf: 'média', resumo: 'Versão nova lida.' }); } else toast('Enviando de novo.'); return; }
  if (d.continue) {
    const a = agentById(d.continue);
    if (!S.build) { S.build = newBuild(a.type === 'internal' ? 'internal' : 'sdr'); S.build.files = a.files; }
    go(a.status === 'ready' ? 'ligue' : ({ Escolha: 'escolha', Conte: 'conte', Teste: 'teste', Ligue: 'ligue' }[a.stepName] || 'conte'));
    return;
  }
  if (d.toggle) { toggleAgent(d.toggle); return; }
  if (d.del) {
    S.open = null;
    const a = agentById(d.del);
    dialog({ title: `Excluir ${a.name}?`, body: a.status !== 'on' && a.status !== 'off' ? 'O rascunho sai da lista.' : a.actuation === 'internal' ? `O ${a.name} sai da lista e some do painel das conversas.` : `${artigo(a).toUpperCase()} ${a.name} sai da lista e para de atender. As conversas com ${ela(a)} vão para a equipe.`, // D34 (#1063)
      confirm: 'Excluir', danger: true, onOk: () => { S.agents = S.agents.filter((x) => x.id !== a.id); CHANNELS.forEach((c) => { if (c.busyBy === a.id) c.busyBy = null; }); go('lista'); toast(`${a.name} foi excluíd${artigo(a)}.`); } });
    return;
  }
  if (d.period) { S.period = Number(d.period); render(); return; }
  if (d.drill) { const [aid, k] = d.drill.split(':'); openDrill(aid, k); return; }
  if (d.sabetab) { S.sabeTab = d.sabetab; render(); return; }
  if (d.faqon) { const a = agentById(d.faqon); a.faqOn = !a.faqOn; render(); toast(a.faqOn ? 'Ligado. As próximas conversas resolvidas viram sugestões.' : 'Desligado.'); return; }
  if (d.faq) {
    const [k] = d.faq.split(':');
    if (k === 'edit') dialog({ title: 'Mudar e aprovar', confirm: 'Salvar e aprovar', html: '<div class="field"><label for="fq">Pergunta</label><input id="fq" value="Vocês atendem corretora com só uma pessoa?"></div><div class="field"><label for="fa">Resposta</label><textarea id="fa" rows="3">Sim. O Chat2You funciona para corretoras de qualquer tamanho.</textarea></div>', onOk: () => toast('Adicionada ao que ela sabe.') });
    else toast(k === 'ok' ? 'Adicionada ao que ela sabe.' : 'Sugestão ignorada.');
    return;
  }
  if (d.disc) {
    const [aid, cid] = d.disc.split(':'); const a = agentById(aid); const c = channelById(Number(cid));
    dialog({ title: `Tirar ${artigo(a)} ${a.name} do ${c.name}?`, body: `As conversas com ${ela(a)} neste canal vão para a equipe agora. Quem escrever depois fala direto com as pessoas.`, confirm: 'Tirar do canal', danger: true,
      onOk: () => { a.channels = a.channels.filter((x) => x !== c.id); c.busyBy = null; render(); toast(`${a.name} saiu do ${c.name}.`); } });
    return;
  }
  if (d.conn) { const [aid, cid] = d.conn.split(':'); const a = agentById(aid); const c = channelById(Number(cid)); a.channels.push(c.id); c.busyBy = a.id; render(); toast(`${a.name} agora atende no ${c.name}.`); return; }
  if (d.actMode) { const [aid, k] = d.actMode.split(':'); const a = agentById(aid); if (k === 'internal' && a.channels.length) { toast(`Tire ${artigo(a)} ${a.name} dos canais antes.`, 'warn'); return; } a.actuation = k; render(); return; }
  if (d.voice) { const [aid, k] = d.voice.split(':'); agentById(aid).voice = k; render(); return; }
  if (d.handoff) { const [aid, k] = d.handoff.split(':'); agentById(aid).handoff = k; render(); return; }
  if (d.target) { const [aid, k] = d.target.split(':'); agentById(aid).target = k; render(); return; }
  if (d.aud) { const [aid, k] = d.aud.split(':'); agentById(aid).audienceOpen = k === 'some'; render(); return; }
  if (d.win) { const [aid, k] = d.win.split(':'); agentById(aid).window = k; render(); return; }
  if (d.manual) {
    const a = agentById(d.manual);
    if (a.mode === 'manual') {
      dialog({ title: 'Voltar ao modo guiado?', body: `O texto que você escreveu deixa de valer e ${ela(a)} volta para a última versão montada pela conversa. O seu texto fica guardado em Versões anteriores.`, confirm: 'Voltar ao modo guiado', onOk: () => { a.mode = 'guided'; render(); toast('Voltou ao modo guiado.'); } });
      return;
    }
    dialog({ title: 'Escrever as instruções você mesmo?', body: 'O campo abre vazio. Enquanto você não salvar, ' + ela(a) + ' continua atendendo como hoje. Ao salvar, o seu texto passa a valer; a versão atual fica guardada.', confirm: 'Escrever eu mesmo', onOk: () => { a.mode = 'manual'; render(); } });
    return;
  }
  if (d.behavior) { agentById(current().split('-')[1]).behavior = d.behavior; render(); return; }
  if (d.restore) { dialog({ title: 'Voltar para esta versão?', body: 'A versão atual fica guardada. Você pode voltar para ela depois.', confirm: 'Voltar para esta', onOk: () => toast('Versão restaurada.') }); return; }
  if (d.save) { toast('Salvo.'); return; }
  if (d.tooltest) { S.toolResult = '{\n  "itens": [{ "nome": "Pastilha de freio dianteira", "estoque": 12 }]\n}  (exemplo)'; render(); toast('Ferramenta executada.'); return; }
  if (d.tooldel) { const [aid, i] = d.tooldel.split(':'); const a = agentById(aid); dialog({ title: `Excluir "${a.tools[i].name}"?`, confirm: 'Excluir', danger: true, onOk: () => { a.tools.splice(Number(i), 1); render(); toast('Ferramenta excluída.'); } }); return; }
  if (d.act && ACTIONS[d.act]) { ACTIONS[d.act](); }
});
document.addEventListener('submit', (e) => { if (e.target.id === 'composer') { e.preventDefault(); answer($('#answer').value); } });
document.addEventListener('keydown', (e) => {
  if (e.target.id === 'answer' && e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); answer(e.target.value); }
  if (e.key === 'Escape' && S.open) { S.open = null; render(); }
});
document.addEventListener('input', (e) => {
  if (e.target.dataset.bfield && S.build) { // D29: mudar como se apresenta invalida o teste anterior
    const f = e.target.dataset.bfield; if (f === 'nome') S.build.answers.nome = e.target.value; else S.build.greeting = e.target.value;
    S.build.stale = true;
  }
});
document.addEventListener('change', (e) => { // D29: ao terminar a edição, a conversa de teste recomeça
  if (e.target.dataset.bfield && S.build && S.build.tested.length) { S.build.tested = []; S.build.chunks = {}; render(); }
  if (e.target.dataset.thr) { const a = agentById(e.target.dataset.thr); a.threshold = Number(e.target.value) / 100; const l = e.target.previousElementSibling.querySelector('span'); if (l) l.textContent = e.target.value + '%'; }
});

function boot() { shell(); render(); }
if (document.body) boot(); else document.addEventListener('DOMContentLoaded', boot);
