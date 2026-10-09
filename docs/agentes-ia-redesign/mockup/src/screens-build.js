// ---------- Criar agente: Escolha → Conte → Teste → Ligue ----------
function newBuild(model) {
  return { model, answers: {}, turn: 0, files: [], media: [], images: [], tested: [], chunks: {}, channels: [], linkHint: false, linkAdded: false, tab: 'knowledge', starters: null, window: 'always' };
}
function ensureBuild() { if (!S.build) S.build = newBuild('sdr'); if (!S.build.model) S.build.model = 'sdr'; return S.build; }
const script = () => SCRIPT[S.build.model === 'internal' ? 'internal' : 'sdr'];
const modelName = (id) => (MODELS.concat(MODEL_TEAM, MODEL_FREE).find((m) => m.id === id) || MODEL_FREE).t;
const bName = () => (S.build && S.build.answers.nome) || (S.build && S.build.model === 'internal' ? 'Apoio' : 'Bia');
const isInternal = () => S.build && S.build.model === 'internal';
const defGreeting = (internal, nome) => internal ? `Oi! Sou o ${nome}. Me peça um resumo ou uma sugestão de resposta.` : `Oi! Eu sou a ${nome}, da Hub2You. Posso te ajudar a entender se o Chat2You serve para a sua corretora.`;
const bGreeting = () => (S.build && S.build.greeting) || defGreeting(isInternal(), bName());
const builderTop = (cur) => `<div class="top"><button class="back" data-act="sair">${cur === 0 ? icon('arrow-left') + 'Voltar' : icon('x') + 'Sair e continuar depois'}</button>${stepsBar(cur)}</div>`;

function viewEscolha() {
  const sel = S.build && S.build.model;
  const noTeam = viewState('escolha', 'normal') === 'semajudante';
  const bar = stateBar('escolha', [['normal', 'Normal'], ['semajudante', 'Conta sem o painel da equipe']]);
  return `<div class="page">
    ${bar}${builderTop(0)}
    <header><h1 class="h1">O que o agente vai fazer?</h1>
    <p class="sub">Escolha o trabalho principal. Ele já começa com as perguntas certas para esse trabalho. Você muda tudo depois.</p></header>
    <div class="grid">${MODELS.map((m) => modelCard(m, sel === m.id)).join('')}</div>
    <div class="grid pair">
      ${(noTeam ? [MODEL_FREE] : [MODEL_TEAM, MODEL_FREE]).map((m) => `<button class="model row" data-model="${m.id}" aria-pressed="${sel === m.id}">
        <span class="tile ${m.tone}">${icon(m.icon)}</span><span class="txt"><b>${esc(m.t)}</b><span class="d">${esc(m.d)}</span></span></button>`).join('')}
    </div>
    <div class="top"><span class="small">${sel ? 'Escolhido: <b>' + esc(modelName(sel)) + '</b>' : 'Escolha um para continuar'}</span>
      <button class="btn primary lg" data-go="conte" ${sel ? '' : 'disabled'}>Continuar${icon('arrow-right')}</button></div>
  </div>`;
}

function chatMessages(b) {
  const sc = script();
  const out = [];
  sc.slice(0, Math.min(b.turn + 1, sc.length)).forEach((s) => {
    out.push(`<div class="who"><span class="mini">${icon('sparkles')}</span>Construtor</div><div class="msg bot">${esc(s.ask)}</div>`);
    if (b.answers[s.key]) out.push(`<div class="msg me">${esc(b.answers[s.key])}${s.key === 'negocio' && b.images.length ? `<div class="tagline" style="color:rgba(255,255,255,.8)">${b.images.length} imagem anexada</div>` : ''}</div>`);
  });
  if (b.turn >= sc.length) {
    out.push(`<div class="who"><span class="mini">${icon('sparkles')}</span>Construtor</div><div class="msg bot">Pronto. ${isInternal() ? 'O ' : 'A '}${esc(bName())} já sabe o básico. ${isInternal() ? 'Teste como ele ajudaria numa conversa.' : 'Se tiver um material sobre seus planos, coloque ao lado: ela responde melhor. Ou teste agora.'}</div>`);
  }
  return out.join('');
}

function viewConte() {
  const b = ensureBuild();
  const st = viewState('conte', 'normal');
  const sc = script();
  const finished = b.turn >= sc.length;
  const cur = sc[b.turn];
  const filled = sc.filter((s) => b.answers[s.key]).length;
  const bar = stateBar('conte', [['normal', 'Normal'], ['pensando', 'Pensando'], ['erro', 'Erro ao enviar'], ['recusado', 'Não salvou'], ['demora', 'Demorando'], ['ocupado', 'Ainda respondendo'], ['limite', 'Muitas mensagens']]);
  const banners = {
    erro: `<div class="banner red" role="alert">${icon('wifi-off')}<span class="grow">Sua mensagem não foi enviada. Confira a internet e tente de novo.</span><button class="btn soft" data-state="conte:normal">Tentar de novo</button></div>`,
    recusado: `<div class="banner red" role="alert">${icon('alert-octagon')}<span class="grow">Nada foi salvo: a primeira mensagem ficou maior que o permitido. Peça para encurtar ou tente de novo.</span><button class="btn soft" data-state="conte:normal">Tentar de novo</button></div>`,
    demora: `<div class="banner amber" role="status">${icon('hourglass')}<span class="grow">Está demorando mais que o normal. Envie sua mensagem de novo.</span><button class="btn soft" data-state="conte:normal">Enviar de novo</button></div>`,
    limite: `<div class="banner amber" role="status">${icon('timer')}<span class="grow">Você mandou muitas mensagens seguidas. Espere um minuto e tente de novo.</span></div>`,
    ocupado: `<div class="banner blue" role="status">${icon('loader')}<span class="grow">Ainda estou respondendo sua mensagem anterior. Espere um instante.</span></div>`,
  };
  const know = sc.map((s) => `<li class="${b.answers[s.key] ? 'ok' : ''}"><span class="st">${icon(b.answers[s.key] ? 'check' : 'circle')}</span>
    <div><div class="k">${esc(s.label)}</div><div class="v">${esc(b.answers[s.key] || 'Ainda não')}</div></div></li>`).join('');
  const list = b.tab === 'knowledge' ? b.files : b.media;
  const accepted = b.files.filter((f) => f.state === 'accepted').length;
  const atLimit = b.files.length >= 30;
  return `<div class="page">
    ${bar}${builderTop(1)}
    <header><h1 class="h1">${isInternal() ? 'Conte como ele vai ajudar' : 'Conte sobre o seu negócio'}</h1>
    <p class="sub">Responda como falaria com alguém novo na equipe. Uma pergunta de cada vez. Pode mandar print ou foto também.</p></header>
    <div class="two">
      <section class="panel" aria-label="Conversa">
        <div class="chat" aria-live="polite">${chatMessages(b)}
          ${st === 'pensando' ? '<div class="think" aria-label="Pensando"><i></i><i></i><i></i></div>' : ''}</div>
        ${banners[st] || ''}
        ${b.linkHint && !b.linkAdded ? `<div class="banner blue">${icon('link')}<span class="grow">Vi o link <b>hub2you.ai/chat2you</b>. Usar como material ${isInternal() ? 'do' : 'da'} ${esc(bName())}?</span>
          <button class="btn primary" data-act="link-sim">Usar</button><button class="btn link" data-act="link-nao">Agora não</button></div>` : ''}
        ${!finished ? `<div class="quick"><button data-ans="${esc(cur.ex)}">${icon('corner-down-right')}${esc(cur.ex)}</button></div>` : ''}
        ${`
        ${b.images.length ? `<div class="imgchips">${b.images.map((n, i) => `<span class="imgchip"><span class="th"></span>${esc(n)}<button aria-label="Tirar imagem ${esc(n)}" data-rmimg="${i}">${icon('x')}</button></span>`).join('')}</div>` : ''}
        <form class="composer" id="composer"><button type="button" class="iconbtn" aria-label="Anexar foto ou arquivo" data-act="anexar">${icon('paperclip')}</button>
          <label for="answer" class="sr">Sua resposta</label>
          <textarea id="answer" rows="1" placeholder="${finished ? 'Quer mudar ou acrescentar algo? Escreva aqui.' : 'Escreva sua resposta'}" ${st === 'ocupado' || st === 'limite' ? 'disabled' : ''}></textarea>
          <button class="iconbtn send" aria-label="Enviar" ${st === 'ocupado' ? 'disabled' : ''}>${icon('arrow-up')}</button></form>
        <p class="small">${finished ? 'O que você escrever aqui atualiza o que o agente sabe.' : 'Toque na sugestão para usar a resposta de exemplo.'} Até 4 imagens por mensagem, 5 MB cada.</p>`}
      </section>
      <aside class="panel" aria-label="O que o agente já sabe">
        <h3>O que ${isInternal() ? 'o' : 'a'} ${esc(b.answers.nome || 'agente')} já sabe</h3>
        <div><div class="progress" role="progressbar" aria-valuemin="0" aria-valuemax="4" aria-valuenow="${filled}" aria-label="Respostas"><i style="width:${filled * 25}%"></i></div>
        <p class="small" style="margin-top:.4rem">${filled === 4 ? 'Pronto para testar' : `${filled} de 4 respostas`}</p></div>
        <ul class="know">${know}</ul>
        <div style="display:flex;flex-direction:column;gap:.7rem">
          <div style="display:flex;align-items:center;justify-content:space-between;gap:.5rem;flex-wrap:wrap">
            <b style="font-size:15px">Materiais <span class="small">(se tiver)</span></b>
            </div>
          <p class="small">O agente lê e usa para responder.</p>
          ${b.tab === 'knowledge' && b.files.length ? meter('Base de conhecimento', b.files.some((f) => f.state === 'accepted') ? 71 : 0) : ''}
          ${list.map((m) => matCard(m, { agentId: 'build' })).join('')}
          <div class="drop">${icon('upload')}<span>${b.tab === 'knowledge' ? 'Solte um PDF, Word, Excel, TXT ou link' : 'Solte uma foto, vídeo ou PDF'}</span>
            <div style="display:flex;flex-wrap:wrap;gap:.25rem;justify-content:center">
              ${b.tab === 'knowledge' ? `<button class="btn link" data-act="usar-pdf" ${atLimit ? 'disabled' : ''}>Usar o PDF que a Clara já usa<span class="newtag">Novo</span></button><button class="btn link" data-act="add-link">Colar um link</button><button class="btn link" data-act="demo-falha">Simular arquivo com problema</button>`
    : '<button class="btn link" data-act="add-media">Adicionar foto de exemplo</button>'}</div></div>
          ${b.tab === 'knowledge' ? `<p class="counter">${b.files.length} de 30 materiais${accepted ? ` · ${accepted} pronto${accepted > 1 ? 's' : ''}` : ''}</p>` : ''}
        </div>
        <button class="btn primary lg" data-go="teste" ${finished ? '' : 'disabled'}>Testar ${isInternal() ? 'o' : 'a'} ${esc(bName())}${icon('arrow-right')}</button>
      </aside>
    </div>
  </div>`;
}

function testBubble(q, b, idx, internal) {
  const r = TEST_ANSWERS[q];
  const shown = b.chunks[idx] ?? r.a.length;
  const typing = shown < r.a.length;
  const parts = r.a.slice(0, shown).map((t, i) => `<div class="msg bot">${esc(t)}${i === r.a.length - 1 && !typing ? `
      <div class="conf"><span>Certeza</span><div class="progress ${r.conf >= 70 ? 'teal' : r.conf >= 40 ? 'amber' : 'red'}"><i style="width:${r.conf}%"></i></div><b>${r.conf}%</b></div>
      ${r.used && b.files.length ? `<details class="used"><summary>${icon('book-open')}Material usado (1)</summary><blockquote>${esc(b.files[0].name)}<br>"Chat2You é a plataforma de atendimento da Hub2You…"</blockquote></details>` : ''}` : ''}</div>`).join('');
  return `<div class="msg me">${esc(q)}</div>${parts}${typing ? '<div class="think" aria-label="Digitando"><i></i><i></i><i></i></div>' : ''}
    ${!typing && r.flag && !internal ? `<div class="flag">${icon('user-round')}Aqui ${isInternal() ? 'ele' : 'ela'} passaria para a equipe. ${esc(r.flag)}</div>` : ''}`;
}

function testPhone(b, nome, { greeting, internal } = {}) {
  const left = (internal ? TEAM_QUESTIONS : CLIENT_QUESTIONS).filter((q) => !b.tested.includes(q));
  return `<section class="phone" aria-label="${internal ? 'Como a equipe vê' : 'Como o cliente vê'}">
    <div class="bar2"><span class="av ${internal ? 'violet' : 'blue'}" style="width:2.4rem;height:2.4rem;border-radius:.75rem;font-size:1rem">${esc(nome[0])}</span>
      <div style="flex:1"><b>${esc(nome)}</b><div class="small">Teste · só você vê</div></div>
      ${b.tested.length ? `<button class="btn link" data-act="limpar-teste">Limpar conversa</button>` : ''}</div>
    ${internal ? `<div class="callout">${icon('messages-square')}<span><b>Conversa de exemplo:</b> Marcos pergunta o preço do plano para 3 atendentes e pede uma demonstração.</span></div>` : '<p class="small">No teste, horário e público não são aplicados. A primeira resposta já vem com o cumprimento.</p>'}
    <div aria-live="polite" style="display:flex;flex-direction:column;gap:.85rem">${b.tested.map((q, i) => testBubble(q, b, i, internal)).join('')}</div>
    <div class="quick" style="margin-top:auto">${left.map((q) => `<button data-q="${esc(q)}">${esc(q)}</button>`).join('')}</div>
    <form class="composer" onsubmit="event.preventDefault()"><button type="button" class="iconbtn" aria-label="Anexar foto" data-act="anexar">${icon('image')}</button>
      <label for="tq" class="sr">Pergunta de teste</label><textarea id="tq" rows="1" placeholder="${internal ? 'Peça como alguém da equipe pediria' : 'Escreva como um cliente escreveria'}"></textarea>
      <button class="iconbtn send" aria-label="Enviar">${icon('arrow-up')}</button></form>
  </section>`;
}

function viewTeste() {
  const b = ensureBuild();
  const st = viewState('teste', 'normal');
  const nome = bName();
  const bar = stateBar('teste', [['normal', 'Normal'], ['incompleto', 'Ainda montando'], ['erro', 'Não respondeu'], ['demora', 'Demorando'], ['limite', 'Muitas mensagens'], ['material', 'Aprendeu material novo'], ['grava', 'Ferramenta que grava']]);
  const done = b.tested.filter((q, i) => (b.chunks[i] ?? 99) >= TEST_ANSWERS[q].a.length).length;
  return `<div class="page">
    ${bar}${builderTop(2)}
    <header><h1 class="h1">${isInternal() ? 'Teste como ele ajudaria numa conversa' : 'Teste antes de ligar'}</h1>
    <p class="sub">${isInternal() ? 'Peça como alguém da equipe pediria, sobre a conversa de exemplo.' : 'Pergunte como um cliente perguntaria.'} Nada disso vai para clientes de verdade.</p></header>
    ${b.stale ? `<div class="banner amber" role="status">${icon('pencil')}<span class="grow">Você mudou como ${isInternal() ? 'ele' : 'ela'} se apresenta. O teste recomeçou: faça uma pergunta.</span></div>` : ''}
    ${st === 'demora' ? `<div class="banner amber" role="status">${icon('hourglass')}<span class="grow">Está demorando mais que o normal.</span><button class="btn soft" data-state="teste:normal">Tentar de novo</button></div>` : ''}
    ${st === 'limite' ? `<div class="banner amber" role="status">${icon('timer')}<span class="grow">Você testou muitas vezes seguidas. Espere um minuto.</span></div>` : ''}
    ${st === 'material' ? `<div class="banner amber" role="status">${icon('book-open')}<span class="grow">${isInternal() ? 'O' : 'A'} ${esc(nome)} aprendeu um material novo. Teste de novo antes de ligar.</span></div>` : ''}
    ${st === 'grava' ? `<div class="callout">${icon('database')}<span>Ferramentas que gravam em outro sistema rodam de verdade no teste.</span></div>` : ''}
    ${st === 'incompleto' ? `<div class="banner amber">${icon('construction')}<span class="grow">${isInternal() ? 'O ' : 'A '}${esc(nome)} ainda está sendo montad${isInternal() ? 'o' : 'a'}. As respostas podem mudar quando terminar.</span></div>` : ''}
    ${st === 'erro' ? `<div class="banner red" role="alert">${icon('alert-octagon')}<span class="grow">${isInternal() ? 'Ele' : 'Ela'} não conseguiu responder agora. Tente de novo.</span><button class="btn soft" data-state="teste:normal">Tentar de novo</button></div>` : ''}
    <div class="sect"><h3>Como ${isInternal() ? 'ele' : 'ela'} se apresenta</h3>
      <div class="field"><label for="tNome">Nome</label><input id="tNome" data-bfield="nome" value="${esc(nome)}"></div>
      ${isInternal() ? '' : `<div class="field"><label for="tOla">Primeira mensagem</label><textarea id="tOla" data-bfield="greeting" rows="2">${esc(bGreeting())}</textarea>
        <span class="small">É uma sugestão. Mude como quiser. Se mudar, o teste recomeça: a primeira resposta já traz o novo.</span></div>`}</div>
    <div class="two">
      ${testPhone(b, nome, { internal: isInternal() })}
      <aside class="panel">
        <h3>Ficou bom?</h3>
        <p class="muted">Espere pelo menos uma resposta chegar. Se algo não estiver certo, volte e conte mais.</p>
        <button class="btn primary lg" data-go="ligue" ${done && !b.stale && !['erro', 'demora', 'limite', 'material'].includes(st) ? '' : 'disabled'}>Está bom, continuar${icon('arrow-right')}</button>
        <button class="btn outline lg" data-go="conte">${icon('message-square-text')}Quero mudar algo</button>
        <div class="tip">${icon('lightbulb')}<span>${isInternal() ? 'Abaixo de cada resposta aparece a certeza dele. Ele nunca fala com clientes: só ajuda a equipe.' : 'Abaixo de cada resposta aparece a certeza dela. Quando ela decide chamar alguém da equipe, aparece em amarelo, com o motivo.'}</span></div>
      </aside>
    </div>
  </div>`;
}

function viewLigue() {
  const b = ensureBuild();
  const st = viewState('ligue', 'normal');
  const nome = bName();
  const internal = isInternal();
  const free = CHANNELS.filter((c) => !c.busyBy);
  const busy = CHANNELS.filter((c) => c.busyBy);
  b.channels ||= [];
  if (!internal && free.length === 1 && !b.channels.length) b.channels = [free[0].id];
  const selected = b.channels.map((id) => channelById(id)).filter(Boolean);
  const ch = selected[0];
  const selectedNames = selected.map((c) => c.name).join(', ');
  const accepted = b.files.filter((f) => f.state === 'accepted').length;
  const starters = b.starters || (internal ? ['Resuma esta conversa', 'Sugira uma resposta'] : ['Sua corretora atende hoje por WhatsApp?', 'Quer ver como funciona na prática?', 'Quantas pessoas atendem na sua corretora?']);
  b.starters = starters;
  const opt = (c) => `<button class="opt" role="checkbox" aria-checked="${b.channels.includes(c.id)}" data-ch="${c.id}" ${c.busyBy ? 'disabled' : ''}>
    <span class="check" aria-hidden="true"></span><span class="tile t-blue" style="width:2.5rem;height:2.5rem;border-radius:.75rem;display:grid;place-items:center">${icon(c.icon)}</span>
    <span style="flex:1;min-width:0"><b>${esc(c.name)}</b>${c.busyBy ? `<div class="small">Já tem ${artigo(agentById(c.busyBy) || { name: 'a' })} ${esc((agentById(c.busyBy) || {}).name || c.busyBy)} atendendo aqui. Cada canal tem um agente.</div>` : ''}</span></button>`;
  const windows = [['always', 'Sempre', 'Responde a qualquer hora.'], ['business_hours', 'No horário comercial', 'Só quando a caixa está aberta.'], ['outside_business_hours', 'Fora do horário comercial', 'Só quando a equipe não está.']];
  const bar = stateBar('ligue', [['normal', 'Normal'], ['semcanal', 'Nenhum canal livre'], ['falhou', 'Falhou ao ligar'], ['semhorario', 'Canal sem horário'], ['semteste', 'Sem teste'], ['naoadmin', 'Quem edita sem ser admin']]);
  const freeList = st === 'semcanal' ? [] : free;
  return `<div class="page">
    ${bar}${builderTop(3)}
    <header><h1 class="h1">${internal ? `Confira e ligue o ${esc(nome)}` : `Confira e escolha onde ${artigo({ name: nome })} ${esc(nome)} atende`}</h1>
    <p class="sub">${internal ? 'Ele aparece ao lado de cada conversa para a equipe. Nunca fala com clientes.' : 'Aparecem só os canais conectados na sua conta.'}</p></header>
    ${st === 'semteste' ? `<div class="banner amber" role="alert">${icon('flask-conical')}<span class="grow">Teste ${internal ? 'o' : 'a'} ${esc(nome)} antes de ligar.</span><button class="btn soft" data-go="teste">Ir para o teste</button></div>` : ''}
    ${st === 'falhou' ? `<div class="banner red" role="alert">${icon('plug-zap')}<span class="grow">Não deu para ligar ${artigo({ name: nome })} ${esc(nome)} nos canais escolhidos. Nada mudou: ${internal ? 'ele' : 'ela'} continua desligad${internal ? 'o' : 'a'}.</span><button class="btn soft" data-state="ligue:normal">Tentar de novo</button></div>` : ''}
    <div class="two">
      <section style="display:flex;flex-direction:column;gap:1.5rem">
        ${internal ? `<div class="sect"><h3>Onde a equipe encontra</h3><p class="desc">Abra qualquer conversa: ${esc(nome)} fica no painel da direita, com resumo e sugestão de resposta.</p></div>` : `
        <div class="sect"><h3>Onde atende</h3>
          ${freeList.length ? `<div role="group" aria-label="Canais" style="display:flex;flex-direction:column;gap:.75rem">${freeList.map(opt).join('')}</div>`
    : `<div class="callout">${icon('info')}<span>Todos os canais já têm um agente. Abra Canais para conectar outro ou tire um agente de um canal.</span></div>`}
          ${st === 'naoadmin' ? `<p class="small">Peça a quem administra a conta para abrir Canais.</p>` : `<a class="btn outline" href="/app/accounts/16/settings/inboxes/new" data-route="settings_inbox_new">${icon('plus')}Abrir Canais</a>`}
          <details><summary class="small" style="cursor:pointer;min-height:2.75rem;display:flex;align-items:center">Canais ocupados (${busy.length})</summary>
            <div style="display:flex;flex-direction:column;gap:.75rem;margin-top:.5rem">${busy.map(opt).join('')}</div></details></div>`}
        <div class="sect"><header><div><h3>Como ${internal ? 'ele' : 'ela'} se apresenta</h3><p class="desc">Do jeito que você testou.</p></div><button class="btn link" data-go="teste">Mudar</button></header>
          <p class="sentence"><b>${esc(nome)}</b>${internal ? '' : ` · "${esc(bGreeting())}"`}</p></div>
        ${internal ? '' : `<div class="sect"><h3>Quando atende</h3><div class="radiocards" role="radiogroup" aria-label="Quando atende">
          ${windows.map(([k, t, d]) => `<button class="rc" role="radio" aria-checked="${b.window === k}" data-bwin="${k}"><b>${t}</b><span>${d}</span></button>`).join('')}</div>
          ${st === 'semhorario' ? `<div class="banner amber">${icon('clock')}<span class="grow">Este canal não tem horário definido: ${internal ? 'ele' : 'ela'} vai responder sempre.</span><button class="btn soft">Definir horário</button></div>` : ''}</div>`}
      </section>
      <aside class="panel">
        <h3>Resumo</h3>
        <div class="who">${avatar({ name: nome, color: 'violet' }, 'width:2.4rem;height:2.4rem;font-size:1rem;border-radius:.75rem')}<span style="font-size:15px;color:var(--s12)">${esc(nome)} · ${esc(modelName(b.model))}</span></div>
        <p class="sentence">${internal ? `O <b>${esc(nome)}</b> vai aparecer ao lado das conversas para a equipe.`
    : ch ? `A <b>${esc(nome)}</b> vai responder quem escrever ${selected.length > 1 ? 'nos canais' : 'no canal'} <b>${esc(selectedNames)}</b>${b.window === 'always' ? '' : b.window === 'business_hours' ? ', no horário comercial' : ', fora do horário comercial'}. Quando não souber, passa a conversa para a equipe.` : 'Escolha um ou mais canais para ver o resumo.'}</p>
        <p class="small">${b.files.length ? `${accepted} material pronto · base 71%` : 'Sem material: responde só com o que você contou.'}</p>
        <button class="btn primary lg" data-act="ligar" ${internal || selected.length ? '' : 'disabled'}>${icon('power')}Ligar ${internal ? 'o' : 'a'} ${esc(nome)}</button>
        <button class="btn link" data-act="ligar-depois">Deixar desligad${internal ? 'o' : 'a'} por enquanto</button>
      </aside>
    </div>
  </div>`;
}

function viewPronto() {
  const a = agentById('novo');
  if (!a) return viewLista();
  const internal = a.actuation === 'internal';
  const channelNames = a.channels.map((id) => channelById(id)).filter(Boolean).map((channel) => channel.name).join(', ');
  return `<div class="page">
    <div class="done" role="status"><span class="c">${icon('check')}</span>
      <div><b style="font-size:1.125rem">${internal ? `O ${esc(a.name)} já aparece para a equipe.` : `A ${esc(a.name)} está atendendo em ${esc(channelNames)}.`}</b>
      <div class="muted">${internal ? 'Abra qualquer conversa e veja no painel da direita.' : 'Ela já responde quem chegar. Você pode pausar quando quiser.'}</div></div></div>
    <div class="grid">
      ${internal ? `<button class="model" data-go="conversa"><span class="tile t-violet">${icon('message-circle')}</span><b>Ver numa conversa</b><span class="d">Abre suas conversas. Em qualquer uma, ${esc(a.name)} aparece no painel ao lado.</span></button>` : ''}
      <button class="model" data-open="novo"><span class="tile t-blue">${icon('activity')}</span><b>Ver como está indo</b><span class="d">Respostas, conversas passadas para a equipe e o que ${ela(a)} não soube.</span></button>
      <button class="model" data-go="lista"><span class="tile t-slate">${icon('layout-list')}</span><b>Voltar para seus agentes</b><span class="d">Todos os agentes e o que cada um está fazendo.</span></button>
    </div>
  </div>`;
}
