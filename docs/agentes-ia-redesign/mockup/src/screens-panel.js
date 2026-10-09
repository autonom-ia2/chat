// ---------- Painel do agente ----------
function panelTabs(a) {
  const t = [['resumo', 'Como está indo'], ['testar', 'Testar']];
  if (can()) t.push(['sabe', 'O que sabe']);
  if (can() && a.actuation !== 'internal') t.push(['onde', 'Onde atende']);
  if (can()) t.push(['ajustes', 'Ajustes']);
  if (isSuper() && a.type !== 'insurance_quote') t.push(['ferramentas', 'Ferramentas']);
  return t;
}

function viewAgente(id, tab) {
  const a = agentById(id);
  if (!a) return viewLista();
  const tabs = panelTabs(a);
  if (!tabs.some(([k]) => k === tab)) tab = 'resumo';
  const body = { resumo: tabResumo, testar: tabTestar, sabe: tabSabe, onde: tabOnde, ajustes: tabAjustes, ferramentas: tabFerramentas }[tab](a);
  const draft = a.status === 'todo' || a.status === 'ready';
  return `<div class="page">
    <button class="back" data-go="lista">${icon('arrow-left')}Seus agentes</button>
    <header class="ph">
      <div style="display:flex;align-items:center;gap:1rem;min-width:0">
        ${avatar(a, 'width:4rem;height:4rem;font-size:1.5rem;border-radius:1.25rem')}
        <div style="min-width:0"><h1 class="h1" style="display:flex;flex-wrap:wrap;align-items:center;gap:.75rem">${esc(a.name)} ${statusPill(a)}</h1>
        <p class="muted" style="margin-top:.25rem;max-width:44rem">${esc(a.card)}</p></div></div>
      <div style="display:flex;gap:.75rem;align-items:center;flex-wrap:wrap">
        ${draft && can() ? `<button class="btn primary" data-continue="${a.id}">${a.status === 'todo' ? 'Continuar montagem' : 'Ligar'}</button>` : switchBtn(a)}
      </div>
    </header>
    ${a.type === 'insurance_quote' ? `<div class="callout">${icon('shield-check')}<span>A forma de cotar da ${esc(a.name)} é mantida pela Hub2You. Você escolhe nome, horário, jeito de cotar e para quem ela responde. Conexão com as seguradoras fica em <button class="btn link" style="min-height:auto;padding:0">Cotação</button>.</span></div>` : ''}
    <div class="tabs" role="tablist">${tabs.map(([k, l]) => `<button role="tab" aria-selected="${tab === k}" data-go="agente-${a.id}-${k}">${l}</button>`).join('')}</div>
    <section style="display:flex;flex-direction:column;gap:1.25rem">${body}</section>
  </div>`;
}

// ----- Como está indo -----
const OUT_LABELS = [['handled', 'Conversas atendidas'], ['resolved', 'Resolvidas sem ninguém da equipe'], ['handed', 'Passadas para a equipe'], ['reopened', 'Voltaram depois de resolvidas'], ['wrong', 'Respostas marcadas como erradas']];
function tabResumo(a) {
  const st = viewState('resumo', 'normal');
  const bar = stateBar('resumo', [['normal', 'Com dados'], ['carregando', 'Carregando'], ['erro', 'Erro'], ['vazio', 'Sem conversas ainda']]);
  const p = S.period;
  const s = a.stats[p];
  const period = `<div class="seg2" role="group" aria-label="Período"><button aria-pressed="${p === 7}" data-period="7">Últimos 7 dias</button><button aria-pressed="${p === 30}" data-period="30">Últimos 30 dias</button></div>`;
  if (a.actuation === 'internal') {
    return `<div class="errorbox"><span class="tile t-violet">${icon('users')}</span><div><b style="font-size:1.125rem">O ${esc(a.name)} ajuda a equipe dentro das conversas</b><p class="muted">Os números de uso ainda não aparecem aqui.</p></div><button class="btn outline" data-go="conversa">Ver numa conversa</button></div>`;
  }
  if (st === 'carregando') return `${bar}${period}<div class="stats">${'<div class="skel" style="height:6.5rem"></div>'.repeat(4)}</div><div class="skel" style="height:14rem"></div>`;
  if (st === 'erro') return `${bar}<div class="errorbox" role="alert"><span class="tile t-ruby">${icon('cloud-off')}</span><b>Não deu para carregar os números</b><button class="btn soft" data-state="resumo:normal">${icon('refresh-cw')}Tentar de novo</button></div>`;
  if (st === 'vazio' || (!s.replies && !s.handed)) {
    return `${bar}${period}<div class="errorbox"><span class="tile t-blue">${icon('sparkles')}</span>
      <div><b style="font-size:1.125rem">${p === 7 && a.stats[30].replies ? 'Nenhuma conversa nesta semana' : `${artigo(a).toUpperCase()} ${esc(a.name)} está pront${artigo(a)}`}</b>
      <p class="muted">${p === 7 && a.stats[30].replies ? `Nos últimos 30 dias foram ${a.stats[30].replies} respostas. Confira se o canal está recebendo mensagens.` : 'Os números aparecem aqui depois das primeiras conversas. Enquanto isso, teste.'}</p></div>
      <div style="display:flex;gap:.6rem;flex-wrap:wrap">${p === 7 && a.stats[30].replies ? '<button class="btn soft" data-period="30">Ver 30 dias</button>' : ''}<button class="btn outline" data-go="agente-${a.id}-testar">Testar</button></div></div>`;
  }
  const rate = Math.round((s.handed / (s.replies + s.handed)) * 100);
  const days = serie(a.serie, p);
  const max = Math.max(1, ...days.map((d) => d.r + d.h));
  const fmt = (k) => k.slice(8, 10) + '/' + k.slice(5, 7);
  const out = { handled: s.conv, resolved: a.id === 'lia' && p === 30 ? 26 : 0, handed: s.handed, reopened: 0, wrong: 0 };
  const maxR = Math.max(1, ...s.reasons.map((r) => r[1]));
  const insight = rate >= 40 ? ['Muitas conversas estão indo para a equipe', 'Veja os motivos abaixo e ensine o que faltou.']
    : s.know !== null && s.know <= 30 ? ['Poucas respostas vieram dos seus materiais', 'Adicione material sobre o que os clientes mais perguntam.'] : null;
  return `${bar}<div class="top">${period}<span class="small">Dados reais da conta, até 05/10</span></div>
    <div class="stats">
      <div class="stat"><div class="num">${s.conv}</div><div class="lab">conversas atendidas</div></div>
      <div class="stat"><div class="num">${s.replies}</div><div class="lab">respostas enviadas</div></div>
      <div class="stat"><div class="num">${rate}%</div><div class="lab">passaram para a equipe (${s.handed})</div></div>
      <div class="stat"><div class="num">${s.conf === null ? 'Sem dados' : s.conf + '%'}</div><div class="lab">certeza média nas respostas</div></div>
      ${a.type === 'insurance_quote' ? '' : `<div class="stat"><div class="num">${s.know === null ? 'Sem dados' : s.know + '%'}</div><div class="lab">respostas que usaram seus materiais</div></div>`}
    </div>
    ${insight ? `<div class="banner amber">${icon('lightbulb')}<span class="grow"><b>${insight[0]}</b>. ${insight[1]}</span>${a.type === 'insurance_quote' ? '' : `<button class="btn soft" data-go="agente-${a.id}-sabe">Ensinar</button>`}</div>` : ''}
    <div class="sect"><header><div><h3>Resultado das conversas</h3><p class="desc">Toque num número para ver as conversas.</p></div></header>
      <div class="outcomes">${OUT_LABELS.map(([k, l]) => `<button class="outcome" data-drill="${a.id}:${k}"><b>${out[k]}</b><span>${l}</span></button>`).join('')}</div></div>
    <div class="sect"><header><div><h3>Dia a dia</h3></div><div class="legend"><span><i style="background:var(--brand)"></i>Respostas</span><span><i style="background:var(--a9)"></i>Passadas para a equipe</span></div></header>
      <div class="chart" role="img" aria-label="Respostas e passagens por dia">${days.map((d) => `<div class="day" title="${fmt(d.date)}: ${d.r} respostas, ${d.h} para a equipe">
        <span class="r" style="height:${(d.r / max) * 100}%"></span><span class="h" style="height:${(d.h / max) * 100}%"></span></div>`).join('')}</div>
      <div class="axis"><span>${fmt(days[0].date)}</span><span>${fmt(days[days.length - 1].date)}</span></div></div>
    <div class="sect"><header><div><h3>Por que passou para a equipe</h3></div></header>
      ${s.reasons.length ? `<ul class="reasons">${s.reasons.map(([l, n]) => `<li><span>${l}</span><div class="progress amber"><i style="width:${(n / maxR) * 100}%"></i></div><b>${n}</b></li>`).join('')}</ul>`
    : '<p class="muted">Nenhuma conversa foi para a equipe neste período.</p>'}</div>`;
}

// ----- Testar -----
function tabTestar(a) {
  S.ptest = S.ptest || { tested: [], chunks: {}, files: a.files };
  S.ptest.files = a.files;
  const st = viewState('ptestar', 'normal');
  const bar = stateBar('ptestar', [['normal', 'Normal'], ['incompleto', 'Montagem não terminou'], ['erro', 'Não respondeu'], ['semperm', 'Ferramenta pulada (só ver)']]);
  const internal = a.actuation === 'internal';
  const draft = a.status === 'todo';
  return `${bar}
    ${draft || st === 'incompleto' ? `<div class="banner amber">${icon('construction')}<span class="grow">${artigo(a).toUpperCase()} ${esc(a.name)} ainda não terminou de ser montad${artigo(a)}. O teste pode não mostrar o jeito final.</span></div>` : ''}
    ${st === 'erro' ? `<div class="banner red" role="alert">${icon('alert-octagon')}<span class="grow">${ela(a)[0].toUpperCase() + ela(a).slice(1)} não conseguiu responder agora. Tente de novo.</span><button class="btn soft" data-state="ptestar:normal">Tentar de novo</button></div>` : ''}
    ${a.type === 'insurance_quote' ? `<div class="callout">${icon('shield-check')}<span>No teste a cotação não é feita de verdade: ${esc(a.name)} conversa e pede os dados, mas não consulta as seguradoras.</span></div>` : ''}
    ${st === 'semperm' ? `<div class="callout">${icon('lock')}<span>Neste teste, ${ela(a)} não usou Consulta de estoque: só quem edita testa essa consulta.</span></div>` : ''}
    <div class="two">${testPhone(S.ptest, a.name, { internal })}
      <aside class="panel"><h3>Como ler o teste</h3>
        <ul class="know"><li class="ok"><span class="st">${icon('gauge')}</span><div><div class="k">Certeza</div><div class="v">Quanto ${ela(a)} confia na resposta. Quem decide passar para a equipe é a regra de "Quando passa para a equipe".</div></div></li>
        <li class="ok"><span class="st">${icon('book-open')}</span><div><div class="k">Material usado</div><div class="v">Mostra de qual material veio a resposta.</div></div></li>
        ${internal ? '' : `<li class="ok"><span class="st">${icon('user-round')}</span><div><div class="k">Amarelo</div><div class="v">Aqui a conversa iria para a equipe, e o motivo.</div></div></li>`}</ul>
        ${can() && a.type !== 'insurance_quote' ? `<button class="btn outline" data-go="agente-${a.id}-sabe">${icon('plus')}Ensinar algo que faltou</button>` : ''}</aside></div>`;
}

// ----- O que sabe -----
function tabSabe(a) {
  if (a.type === 'insurance_quote') {
    return `<div class="sect"><header><div><h3>O que a ${esc(a.name)} cota</h3><p class="desc">Os ramos ligados na sua conta. As regras de cada ramo e as condições gerais são mantidas pela Hub2You.</p></div></header>
      <div class="rows">${a.ramos.map((r) => `<div class="rowi"><span class="tile t-teal" style="width:2.5rem;height:2.5rem;border-radius:.75rem;display:grid;place-items:center">${icon('shield-check')}</span><div class="grow"><b>${esc(r)}</b><div class="small">Ligado</div></div></div>`).join('')}</div></div>`;
  }
  const st = viewState('sabe', 'normal');
  const bar = stateBar('sabe', [['normal', 'Como está'], ['estados', 'Materiais em todos os estados'], ['vazio', 'Sem material'], ['limite', 'Limite de 30']]);
  S.sabeTab = S.sabeTab || 'knowledge';
  let files = a.files;
  if (st === 'estados') files = [a.files[0] || PDF_CLARA,
    { id: 'x1', name: 'tabela-planos-2026.xlsx', type: 'xlsx', state: 'analyzing' },
    { id: 'x2', name: 'hub2you.ai/chat2you', type: 'link', state: 'sending' },
    { id: 'x3', name: 'contrato-escaneado.pdf', type: 'pdf', state: 'failed' },
    { id: 'x4', name: 'faq-antigo.docx', type: 'docx', state: 'resend' },
    { id: 'x5', name: 'politica-de-cancelamento.md', type: 'md', state: 'review' },
    { id: 'x6', name: 'cardapio-restaurante.pdf', type: 'pdf', state: 'offscope' }];
  if (st === 'vazio') files = [];
  const count = st === 'limite' ? 30 : files.length;
  const limit = count >= 30;
  const media = false; // D20: sem aba "Para enviar"
  const faqOn = a.faqOn;
  const faqItems = st === 'estados' ? [{ q: 'Vocês atendem corretora com só uma pessoa?', ans: 'Sim. O Chat2You funciona para corretoras de qualquer tamanho.', conv: 412 }] : a.faq;
  return `${bar}
    <div class="sect"><header><div><h3>Materiais</h3><p class="desc">${media ? 'Fotos, vídeos e arquivos que o agente manda para o cliente quando faz sentido.' : 'O que o agente lê para responder. Quanto mais completo, melhor ele responde.'}</p></div>
      <span class="counter">${count} de 30</span></header>
      ${!media && files.length && a.base ? meter('Base de conhecimento', a.base) : ''}
      ${media ? ''
    : files.length ? files.map((m) => matCard(m, { agentId: a.id })).join('') : `<p class="muted">Nenhum material ainda. Sem material, ${ela(a)} responde só com o que você contou na montagem.</p>`}
      ${limit && !media ? `<div class="banner amber">${icon('alert-triangle')}<span class="grow">Chegou ao limite de 30 materiais. Tire um para colocar outro.</span></div>` : ''}
      <div style="display:flex;flex-wrap:wrap;gap:.6rem;align-items:center">
        <button class="btn primary" data-act="add-material" ${limit && !media ? 'disabled' : ''}>${icon('plus')}${media ? 'Adicionar mídia' : 'Adicionar material'}</button>
        ${!media ? `<span class="counter">${count} de 30 materiais</span>` : ''}</div></div>
    <div class="sect"><header><div><h3>Perguntas que a equipe respondeu</h3>
      <p class="desc">Quando uma conversa é resolvida, as perguntas que alguém da equipe respondeu aparecem aqui. Aprove e ${ela(a)} passa a saber.</p></div>
      <button class="sw" role="switch" aria-checked="${faqOn}" data-faqon="${a.id}"><span class="track"></span>${faqOn ? 'Ligado' : 'Desligado'}</button></header>
      ${!faqOn ? '<p class="muted">Ligue para receber sugestões a partir das conversas resolvidas.</p>'
    : faqItems.length ? faqItems.map((f, i) => `<div class="mat"><b>${esc(f.q)}</b><div class="why">${esc(f.ans)}</div>
        <div style="display:flex;flex-wrap:wrap;gap:.5rem;align-items:center"><button class="btn primary" data-faq="ok:${i}">Aprovar</button><button class="btn outline" data-faq="edit:${i}">Mudar e aprovar</button><button class="btn link" data-faq="no:${i}">Ignorar</button>
        <span class="small" style="margin-left:auto">Da conversa #${f.conv}</span></div></div>`).join('')
      : `<p class="muted">Nenhuma pergunta nova. Elas aparecem depois que conversas com resposta da equipe são resolvidas.</p>`}</div>`;
}

// ----- Onde atende -----
function tabOnde(a) {
  const st = viewState('onde', 'normal');
  const bar = stateBar('onde', [['normal', 'Como está'], ['semcanal', 'Sem canal'], ['falhou', 'Falhou ao colocar'], ['naoadmin', 'Quem edita sem ser admin']]);
  const chans = st === 'semcanal' ? [] : a.channels;
  const free = CHANNELS.filter((c) => !c.busyBy);
  const off = a.status !== 'on'; // rascunho ou pausado (backend recusa agent_not_active)
  return `${bar}
    ${st === 'falhou' ? `<div class="banner red" role="alert">${icon('plug-zap')}<span class="grow">Não deu para colocar no Chat do site hub2you: esse canal já tem um robô de outro sistema. Tire o outro robô nas configurações da caixa e tente de novo.</span></div>` : ''}
    <div class="sect"><header><div><h3>Onde ${ela(a)} atende</h3><p class="desc">Cada canal tem um agente só. ${esc(a.name)} responde todo mundo que escreve nestes canais${a.audience ? ', dentro do público escolhido' : ''}.</p></div></header>
      ${chans.length ? `<div class="rows">${chans.map((id) => { const c = channelById(id); return `<div class="rowi"><span class="tile t-blue" style="width:2.5rem;height:2.5rem;border-radius:.75rem;display:grid;place-items:center">${icon(c.icon)}</span>
        <div class="grow"><b>${esc(c.name)}</b><div class="small">Conectado</div></div><button class="btn outline" data-disc="${a.id}:${id}">Tirar deste canal</button></div>`; }).join('')}</div>`
    : `<div class="banner amber">${icon('alert-triangle')}<span class="grow">${artigo(a).toUpperCase()} ${esc(a.name)} não está em nenhum canal. Ninguém fala com ${ela(a)}.</span></div>`}</div>
    <div class="sect"><header><div><h3>Colocar em outro canal</h3><p class="desc">Aparecem só canais conectados que ainda não têm agente.</p></div></header>
      ${off ? `<div class="callout">${icon('info')}<span>Ligue ${artigo(a)} ${esc(a.name)} para colocar em outro canal.</span></div>` : ''}
      ${free.length ? `<div class="rows">${free.map((c) => `<div class="rowi"><span class="tile t-slate" style="width:2.5rem;height:2.5rem;border-radius:.75rem;display:grid;place-items:center">${icon(c.icon)}</span>
        <div class="grow"><b>${esc(c.name)}</b></div><button class="btn primary" data-conn="${a.id}:${c.id}" ${off ? 'disabled' : ''}>Colocar aqui</button></div>`).join('')}</div>` : '<p class="muted">Todos os canais já têm agente.</p>'}
      ${st === 'naoadmin' ? '<p class="small">Peça a quem administra a conta para abrir Canais.</p>' : `<div><a class="btn outline" href="/app/accounts/16/settings/inboxes/new" data-route="settings_inbox_new">${icon('plus')}Abrir Canais</a></div>`}</div>`;
}

// ----- Ajustes -----
const TONES = ['Amigável', 'Profissional', 'Neutro', 'Descontraído'];
function tabAjustes(a) {
  const quote = a.type === 'insurance_quote';
  const manual = a.mode === 'manual';
  const noTeam = viewState('ajustes', 'normal') === 'semajudante';
  const handoffs = [['low_confidence', 'Quando estiver em dúvida', 'Chama a equipe quando não tem segurança na resposta.'], ['always_ask', 'Sempre oferecer uma pessoa', 'Pergunta ao cliente se quer falar com alguém.'], ['never', 'Nunca', 'Não oferece uma pessoa. Ainda passa quando o cliente pede.']];
  const windows = [['always', 'Sempre', 'Responde a qualquer hora.'], ['business_hours', 'No horário comercial', 'Usa a agenda da caixa de entrada.'], ['outside_business_hours', 'Fora do horário comercial', 'Só quando a equipe não está.']];
  const acts = [['external', 'Clientes', 'Responde nos canais.'], ['internal', 'A equipe', 'Ajuda dentro das conversas. Não fala com clientes.'], ['both', 'Os dois', 'Responde clientes e ajuda a equipe.']];
  const target = a.target || 'any';
  const aud = a.audienceOpen ? 'some' : a.audience ? 'some' : 'all';
  const sect = (h, d, inner, save = true, saveTxt = 'Salvar') => `<div class="sect"><header><div><h3>${h}</h3>${d ? `<p class="desc">${d}</p>` : ''}</div></header>${inner}${save ? `<div><button class="btn primary" data-save="${esc(h)}">${saveTxt}</button></div>` : ''}</div>`;
  const parts = [];
  parts.push(sect('Foto e nome', '', `<div style="display:flex;flex-wrap:wrap;align-items:center;gap:1rem">${avatar(a, 'width:4rem;height:4rem;font-size:1.5rem;border-radius:1.25rem')}
    <div style="display:flex;gap:.5rem;flex-wrap:wrap"><button class="btn outline">${icon('image-up')}Trocar foto</button><button class="btn link">Tirar foto</button></div></div>
    <div class="field"><label for="aNome">Nome</label><input id="aNome" value="${esc(a.name)}"></div>
    <div class="field"><label>Tratar por</label><div class="radiocards" role="radiogroup" aria-label="Tratar por"><button class="rc" role="radio" aria-checked="${!isEle(a)}" data-voice="${a.id}:feminina"><b>Ela</b><span>"A ${esc(a.name)} está atendendo"</span></button><button class="rc" role="radio" aria-checked="${isEle(a)}" data-voice="${a.id}:masculina"><b>Ele</b><span>"O ${esc(a.name)} está atendendo"</span></button></div></div>`));
  if (quote) {
    parts.push(sect('Jeito de cotar', `Quando ${artigo(a)} ${esc(a.name)} explica a cobertura. Nos dois casos ${ela(a)} nunca responde de memória.`, `<div class="radiocards" role="radiogroup" aria-label="Jeito de cotar">
      <button class="rc" role="radio" aria-checked="${a.behavior === 'consultivo'}" data-behavior="consultivo"><b>Consultivo</b><span>Explica o que o cliente vai receber antes de cotar.</span></button>
      <button class="rc" role="radio" aria-checked="${a.behavior === 'objetivo'}" data-behavior="objetivo"><b>Objetivo</b><span>Cota primeiro. Explica se perguntarem.</span></button></div>`));
    parts.push(sect(`Horário que ${ela(a)} informa ao cliente`, `É o que ${artigo(a)} ${esc(a.name)} diz quando perguntam quando a equipe atende.`, `<div class="field"><label for="lhor" class="sr">Horário</label><input id="lhor" value="de segunda a sexta, das 09h às 18h"></div>`));
  } else {
    parts.push(sect('O que faz', 'Resumo do trabalho. Para mudar, converse com o construtor ou escreva você mesmo.', `<p class="sentence">${esc(a.card)}</p>
      <div style="display:flex;flex-wrap:wrap;gap:.6rem;align-items:center"><button class="btn primary" data-act="reconversar" ${manual ? 'disabled' : ''}>${icon('message-square-text')}Mudar conversando</button>
      <button class="sw" role="switch" aria-checked="${manual}" data-manual="${a.id}"><span class="track"></span>Escrever as instruções eu mesmo</button></div>
      ${manual ? `<p class="small">Para mudar conversando, volte ao modo guiado (desligue o interruptor).</p><div class="banner amber">${icon('alert-triangle')}<span class="grow">Aqui você escreve tudo. Ao ligar isso, o texto montado pela conversa é trocado pelo seu. As proteções de segurança continuam valendo.</span></div>
      <div class="field"><label for="instr">Instruções</label><textarea id="instr" rows="10" maxlength="50000" placeholder="Escreva aqui como ${artigo(a)} ${esc(a.name)} deve atender."></textarea><span class="counter">0 de 50.000 caracteres · o modo manual só vale depois de salvar</span></div>` : ''}`, manual, 'Salvar instruções'));
    parts.push(sect('Onde atua', '', `<div class="radiocards" role="radiogroup" aria-label="Onde atua">${acts.map(([k, t, d]) => `<button class="rc" role="radio" aria-checked="${a.actuation === k}" data-act-mode="${a.id}:${k}" ${noTeam && k !== 'external' ? 'disabled' : ''}><b>${t}</b><span>${d}</span></button>`).join('')}</div>
      ${noTeam ? '<p class="small">Esta conta ainda não tem o ajudante dentro das conversas.</p>' : ''}
      ${a.channels.length ? `<p class="small">Para mudar para "A equipe", tire ${artigo(a)} ${esc(a.name)} dos canais antes.</p>` : ''}`));
    parts.push(sect('Como fala', '', `${a.actuation === 'internal' ? '' : `<div class="field"><label for="aOla">Primeira mensagem</label><textarea id="aOla" rows="3">${esc(a.greeting)}</textarea></div>`}
      <div class="field"><label for="aFall">${a.actuation === 'internal' ? 'Quando não souber, o ajudante mostra à equipe' : 'Quando não souber responder'}</label><textarea id="aFall" rows="3">${esc(a.fallback)}</textarea></div>
      <div class="field"><label>Jeito de falar</label><div class="chipsel" role="group" aria-label="Jeito de falar">${TONES.map((t) => `<button aria-pressed="false">${t}</button>`).join('')}<button aria-pressed="true">Do meu jeito</button></div>
        <input aria-label="Do meu jeito" value="${esc(a.tone)}"></div>`));
  }
  if (a.actuation !== 'internal') { // ajudante: sem leitor para estes controles (§6.3)
    if (a.actuation === 'both') parts.push(`<div class="callout">${icon('info')}<span>As seções abaixo valem só quando ${ela(a)} atende clientes. No painel da equipe, isto não se aplica.</span></div>`);
  parts.push(sect(quote ? 'Para quem vai a conversa' : 'Quando passa para a equipe', '', `${quote ? '' : `<div class="radiocards" role="radiogroup" aria-label="Quando passa">${handoffs.map(([k, t, d]) => `<button class="rc" role="radio" aria-checked="${a.handoff === k}" data-handoff="${a.id}:${k}"><b>${t}</b><span>${d}</span></button>`).join('')}</div>`}
    <div class="field"><label>Para quem vai<span class="newtag">Novo</span></label><div class="radiocards" role="radiogroup" aria-label="Para quem vai">
      ${[['any', 'Quem estiver livre', 'A distribuição normal da caixa.'], ['member', 'Uma pessoa', 'Só aparece quem está em todas as caixas do agente.'], ['team', 'Um time', 'Ex.: Comercial.']].map(([k, t, d]) => `<button class="rc" role="radio" aria-checked="${target === k}" data-target="${a.id}:${k}"><b>${t}</b><span>${d}</span></button>`).join('')}</div>
      ${target !== 'any' ? `<button class="pick" style="max-width:20rem">${target === 'member' ? 'Escolha a pessoa' : 'Escolha o time'}${icon('chevron-down')}</button>` : ''}</div>`));
  parts.push(sect('Para quem responde', 'Quem fica fora vai direto para a equipe, sem resposta do agente.', `<div class="radiocards" role="radiogroup" aria-label="Para quem responde">
      <button class="rc" role="radio" aria-checked="${aud === 'all'}" data-aud="${a.id}:all"><b>Todo mundo</b><span>Responde todas as conversas dos canais.</span></button>
      <button class="rc" role="radio" aria-checked="${aud === 'some'}" data-aud="${a.id}:some"><b>Só alguns clientes</b><span>Escolha as condições.</span></button></div>
    ${aud === 'some' ? `<div class="cond"><div class="condrow"><span>Responder quando</span><button class="pick" style="min-width:6rem">todas${icon('chevron-down')}</button><span>as condições valerem:</span></div>
      <div class="condrow"><button class="pick">Etiqueta${icon('chevron-down')}</button><button class="pick" style="min-width:7rem">é${icon('chevron-down')}</button><input aria-label="Valor" value="cliente-ativo"><button class="iconbtn" aria-label="Tirar condição">${icon('trash-2')}</button></div>
      <div class="condrow"><button class="pick">Cidade${icon('chevron-down')}</button><button class="pick" style="min-width:7rem">contém${icon('chevron-down')}</button><input aria-label="Valor" value="São Paulo"><button class="iconbtn" aria-label="Tirar condição">${icon('trash-2')}</button></div>
      <div style="display:flex;gap:.5rem;flex-wrap:wrap"><button class="btn link">${icon('plus')}Mais uma condição</button><button class="btn link">${icon('layers')}Grupo de condições (e/ou)</button></div></div>
      <div class="field"><label>Quando ainda não dá para saber quem é o cliente</label><div class="radiocards" role="radiogroup">
        <button class="rc" role="radio" aria-checked="true"><b>Responder normalmente</b><span>Alguns canais abrem a conversa antes de saber quem é.</span></button>
        <button class="rc" role="radio" aria-checked="false"><b>Passar para a equipe</b><span>Só responde quem dá para conferir.</span></button></div></div>` : ''}`));
  parts.push(sect('Quando atende', 'Fora desse horário, as conversas vão direto para a equipe.', `<div class="radiocards" role="radiogroup" aria-label="Quando atende">${windows.map(([k, t, d]) => `<button class="rc" role="radio" aria-checked="${a.window === k}" data-win="${a.id}:${k}"><b>${t}</b><span>${d}</span></button>`).join('')}</div>
    ${viewState('ajustes', 'normal') === 'semhorario' ? `<div class="banner amber">${icon('clock')}<span class="grow">Estes canais não têm horário definido: ${ela(a)} responde sempre neles.<br><a href="#" class="btn link">WhatsApp Comercial · definir horário</a> <a href="#" class="btn link">Chat do site · definir horário</a></span></div>` : ''}`));
  } else {
    parts.push(`<div class="callout">${icon('info')}<span>O ${esc(a.name)} só ajuda a equipe dentro das conversas. Horário, público e passagem para a equipe não se aplicam a ele.</span></div>`);
  }
  if (!quote) {
    const vers = a.versions.length ? a.versions : (viewState('ajustes', 'normal') === 'versoes' ? [['Mudança conversando', '04/10/2026', 'Rodrigo'], ['Edição manual', '02/10/2026', 'Rodrigo'], ['Material novo entrou', '28/09/2026', 'Automático'], ['Antes de escrever eu mesmo', '27/09/2026', 'Rodrigo'], ['Versão restaurada', '21/09/2026', 'Rodrigo']] : []);
    parts.push(sect('Versões anteriores', 'Cada mudança nas instruções fica guardada. Se algo piorar, volte para uma versão anterior.',
      vers.length ? vers.map(([r, d, w], i) => `<div class="ver"><div class="grow"><b>${r}</b><div class="small">${d} · ${w}</div></div>${i === 0 ? '<span class="pill on">Atual</span>' : `<button class="btn outline" data-restore="${a.id}">Voltar para esta</button>`}</div>`).join('')
        : '<p class="muted">Ainda não há versões anteriores. Elas aparecem depois da primeira mudança.</p>', false));
  }
  parts.push(`${a.status !== 'on' && a.status !== 'off' ? `<div class="danger"><div><b>Continuar a montagem</b><div class="small">${artigo(a).toUpperCase()} ${esc(a.name)} ainda não está atendendo.</div></div><button class="btn primary" data-go="${a.status === 'ready' ? 'ligue' : a.stepName === 'Teste' ? 'teste' : 'conte'}">Continuar montagem</button></div>` : ''}${a.status !== 'on' && a.status !== 'off' ? '' : `<div class="danger"><div><b>${a.status === 'on' ? `Pausar ${artigo(a)} ${esc(a.name)}` : `Ligar ${artigo(a)} ${esc(a.name)}`}</b><div class="small">${a.actuation === 'internal' ? (a.status === 'on' ? `O ${esc(a.name)} some do painel das conversas até você ligar de novo.` : 'Volta a aparecer no painel das conversas.') : a.status === 'on' ? 'As conversas com ' + ela(a) + ' vão para a equipe na hora.' : 'Volta a responder as conversas novas.'}</div></div>${switchBtn(a)}</div>`}
    <div class="danger"><div><b>Excluir ${esc(a.name)}</b><div class="small">${a.actuation === 'internal' ? `O ${esc(a.name)} sai da lista e some do painel das conversas.` : `${artigo(a).toUpperCase()} ${esc(a.name)} sai da lista e para de atender. As conversas com ${ela(a)} vão para a equipe.`}</div></div>
      <button class="btn danger" data-del="${a.id}">${icon('trash-2')}Excluir</button></div>`);
  const bar = quote ? '' : stateBar('ajustes', [['normal', 'Como está'], ['versoes', 'Com versões anteriores'], ['semhorario', 'Vários canais sem horário'], ['semajudante', 'Conta sem o painel da equipe']]);
  return bar + parts.join('');
}

// ----- Ferramentas (só administrador da plataforma) -----
function tabFerramentas(a) {
  const tools = a.tools || [];
  return `<div class="callout">${icon('shield')}<span>Só administradores da plataforma veem esta aba.</span></div>
    <div class="sect"><header><div><h3>Ferramentas</h3><p class="desc">Consultas a sistemas de fora que ${ela(a)} faz quando as instruções pedem. Até 10 por agente.</p></div>
      <button class="btn primary" data-act="tool-new">${icon('plus')}Nova ferramenta</button></header>
      ${tools.length ? tools.map((t, i) => `<div class="tool"><div class="grow"><b>${esc(t.name)}</b> <span class="pill ${t.on ? 'on' : 'off'}">${t.on ? 'Ligada' : 'Desligada'}</span><div class="small mono">${esc(t.slug)} · ${t.method}</div><div class="small">${esc(t.when)}</div></div>
        <button class="btn outline" data-tooltest="${i}">${icon('play')}Testar</button><button class="btn outline" data-act="tool-new">${icon('pencil')}Mudar</button><button class="iconbtn" aria-label="Excluir ${esc(t.name)}" data-tooldel="${a.id}:${i}">${icon('trash-2')}</button></div>`).join('')
    : `<p class="muted">Nenhuma ferramenta ainda.</p><div><button class="btn link" data-act="tool-model">Começar pelo modelo de consulta de estoque</button></div>`}
      ${S.toolResult ? `<div class="mat"><b>Resultado do teste</b><pre class="mono" style="margin:0;white-space:pre-wrap;overflow-wrap:anywhere">${esc(S.toolResult)}</pre></div>` : ''}</div>`;
}
