// ---------- Dentro de uma conversa: copiloto e "resposta errada" ----------
function viewConversa() {
  const helper = S.agents.find((x) => x.actuation === 'internal' || x.actuation === 'both');
  return `<div class="page">
    <button class="back" data-go="lista">${icon('arrow-left')}Seus agentes</button>
    <header><h1 class="h1">Dentro de uma conversa</h1><p class="sub">Como a equipe encontra os agentes enquanto atende. Conversa de exemplo, sem dados de clientes.</p></header>
    <div class="convo">
      <section class="convpane" aria-label="Conversa">
        <div class="bar2" style="display:flex;align-items:center;gap:.6rem;padding-bottom:.75rem;border-bottom:1px solid var(--weak)"><span class="av slate t-slate" style="width:2.4rem;height:2.4rem;border-radius:.75rem;font-size:1rem">M</span><div><b>Cliente de exemplo</b><div class="small">WhatsApp (11) 94454-7873</div></div></div>
        <div class="msgrow"><div class="msg bot">Oi, quanto custa o Chat2You para 3 atendentes?</div></div>
        <div class="msgrow out"><div class="ctx"><button class="more" aria-label="Opções da mensagem" aria-haspopup="menu" aria-expanded="${S.open === 'msgmenu'}" data-menu="msgmenu">${icon('more-vertical')}</button>
          ${S.open === 'msgmenu' ? `<div class="menu" role="menu" style="right:auto;left:0"><button role="menuitem" data-act="wrong">${icon('flag')}Marcar resposta como errada</button><button role="menuitem">${icon('copy')}Copiar</button></div>` : ''}</div>
          <div><div class="msg me">O valor depende do tamanho da sua corretora. Vou chamar alguém do comercial para te passar os planos, tudo bem?</div><div class="tagline" style="text-align:right">Clara · agente</div></div></div>
        <div class="callout" style="background:var(--a3);border-color:transparent;color:var(--a11)">${icon('lock')}<span><b>Nota interna</b> · A Clara passou esta conversa para a equipe: o cliente pediu uma pessoa.</span></div>
      </section>
      <aside class="copilot" aria-label="Ajudante da equipe">
        <header>${icon('sparkles')}${helper ? esc(helper.name) : 'Ajudante da equipe'}</header>
        <div class="body">${helper ? `<div class="msg bot" style="max-width:100%">Resumo: cliente quer saber o preço para 3 atendentes. A Clara já explicou que depende do tamanho e passou para o comercial.</div>
          <div class="quick"><button>Sugerir resposta</button><button>Resumir de novo</button></div>
          <form class="composer" onsubmit="event.preventDefault()"><label for="cp" class="sr">Pergunte</label><textarea id="cp" rows="1" placeholder="Pergunte algo sobre esta conversa"></textarea><button class="iconbtn send" aria-label="Enviar">${icon('arrow-up')}</button></form>`
    : `<p class="muted">Nenhum ajudante ligado. Crie um agente "Ajudar minha equipe" para ele aparecer aqui.</p>${can() ? '<button class="btn primary" data-model="internal">Criar ajudante</button>' : ''}`}</div>
      </aside></div></div>`;
}

// ---------- Lista de conversas por resultado (painel lateral) ----------
function openDrill(agentId, key) {
  const a = agentById(agentId);
  const label = OUT_LABELS.find((o) => o[0] === key)[1];
  const n = { handled: a.stats[S.period].conv, handed: a.stats[S.period].handed }[key] || 0;
  const layer = $('#layer');
  const prev = document.activeElement;
  layer.innerHTML = `<div class="scrim" data-scrim style="place-items:stretch end;padding:0"><aside class="drawer" role="dialog" aria-modal="true" aria-labelledby="drT">
    <header><div><h2 id="drT">${esc(label)}</h2><div style="color:#B9C6DA;font-size:13px">${n} conversa${n === 1 ? '' : 's'} · últimos ${S.period} dias</div></div><button class="iconbtn" aria-label="Fechar" data-dlg-close>${icon('x')}</button></header>
    <div class="scroll">${key === 'wrong' ? `<p class="small">Cada marcação mostra o motivo e a resposta certa que a equipe sugeriu (exemplo).</p>
      <div class="mat"><b>Informação errada</b><div class="why">Sugestão da equipe: "O plano mínimo atende até 3 pessoas."</div><div style="display:flex;gap:.5rem"><button class="btn outline">Abrir conversa</button><button class="btn primary" data-go="agente-${a.id}-sabe">Ensinar</button></div></div>` : ''}
      ${n ? `<p class="small">Algumas conversas são de caixas que você não vê.</p><p class="small">No produto aparecem as conversas reais, com contato, canal e última mensagem. Aqui elas ficam ocultas para não expor clientes.</p>
      ${Array.from({ length: Math.min(n, 6) }, (_, i) => `<div class="tool"><span class="tile t-slate" style="width:2.4rem;height:2.4rem;border-radius:.7rem;display:grid;place-items:center">${icon('message-circle')}</span><div class="grow"><b>Conversa ${i + 1}</b><div class="small">${esc(CH_LABEL(a.channels[0]))}</div></div><button class="btn outline">Abrir</button></div>`).join('')}`
    : '<p class="muted">Nenhuma conversa com esse resultado no período.</p>'}</div></aside></div>`;
  paint();
  const close = () => { layer.innerHTML = ''; prev && prev.focus(); };
  layer.querySelector('[data-dlg-close]').addEventListener('click', close);
  layer.querySelector('[data-scrim]').addEventListener('click', (e) => { if (e.target.hasAttribute('data-scrim')) close(); });
  layer.querySelector('[data-dlg-close]').focus();
}

// ---------- Mapa das telas ----------
const MAP = [
  ['Seus agentes', [['lista', 'Lista com agentes'], ['lista@carregando', 'Carregando'], ['lista@erro', 'Erro ao carregar'], ['lista@vazio', 'Conta sem agentes']]],
  ['Criar agente', [['escolha', '1. Escolha o trabalho'], ['conte', '2. Conte (conversa + materiais)'], ['conte@pensando', '2. Pensando'], ['conte@erro', '2. Erro ao enviar'], ['conte@recusado', '2. Não salvou'], ['conte@limite', '2. Muitas mensagens'], ['teste', '3. Teste'], ['teste@incompleto', '3. Ainda montando'], ['ligue', '4. Confira e ligue'], ['ligue@semcanal', '4. Sem canal livre'], ['ligue@falhou', '4. Falhou ao ligar'], ['escolha@semajudante', '1. Conta sem o painel da equipe'], ['teste@demora', '3. Demorando'], ['teste@material', '3. Aprendeu material novo'], ['teste@grava', '3. Ferramenta que grava'], ['ligue@semteste', '4. Sem teste'], ['interno', 'Ajudante da equipe (interno)'], ['interno-teste', 'Ajudante: teste numa conversa de exemplo']]],
  ['Clara (agente comum)', [['agente-clara-resumo', 'Como está indo'], ['agente-clara-resumo@vazio', 'Como está indo: sem conversas'], ['agente-clara-testar', 'Testar'], ['agente-clara-sabe', 'O que sabe'], ['agente-clara-sabe@estados', 'Materiais em todos os estados'], ['agente-clara-sabe@limite', 'Limite de 30 materiais'], ['agente-clara-onde', 'Onde atende'], ['agente-clara-onde@semcanal', 'Sem canal'], ['agente-clara-ajustes', 'Ajustes'], ['agente-clara-ajustes@versoes', 'Ajustes com versões'], ['agente-clara-ajustes@semhorario', 'Ajustes: canais sem horário'], ['agente-clara-testar@semperm', 'Testar: ferramenta pulada (só ver)'], ['agente-clara-ferramentas#super', 'Ferramentas (admin da plataforma)']]],
  ['Lia (Agente de Cotação)', [['agente-lia-resumo', 'Como está indo'], ['agente-lia-sabe', 'O que cota'], ['agente-lia-ajustes', 'Ajustes da cotação']]],
  ['Outras', [['conversa', 'Dentro da conversa: ajudante e "resposta errada"'], ['lista#view', 'Quem só pode ver']]],
];
function openMap() {
  const layer = $('#layer');
  const prev = document.activeElement;
  layer.innerHTML = `<div class="scrim" data-scrim style="place-items:stretch end;padding:0"><aside class="drawer" role="dialog" aria-modal="true" aria-labelledby="mapT">
    <header><h2 id="mapT">Todas as telas</h2><button class="iconbtn" aria-label="Fechar" data-dlg-close>${icon('x')}</button></header>
    <div class="scroll">${MAP.map(([g, items]) => `<div><div class="mapgroup">${g}</div><ul class="maplist">${items.map(([k, l]) => `<li><button data-mapgo="${k}">${icon('chevron-right')}${esc(l)}</button></li>`).join('')}</ul></div>`).join('')}</div></aside></div>`;
  paint();
  const close = () => { layer.innerHTML = ''; prev && prev.focus(); };
  layer.querySelector('[data-dlg-close]').addEventListener('click', close);
  layer.querySelector('[data-scrim]').addEventListener('click', (e) => { if (e.target.hasAttribute('data-scrim')) close(); });
  layer.querySelectorAll('[data-mapgo]').forEach((b) => b.addEventListener('click', () => { close(); mapGo(b.dataset.mapgo); }));
  layer.querySelector('[data-mapgo]').focus();
}
function mapGo(spec) {
  let [r, prof] = spec.split('#');
  let st = null;
  if (r.includes('@')) [r, st] = r.split('@');
  S.profile = prof === 'super' ? 'super' : prof === 'view' ? 'view' : 'manage';
  if (r === 'interno') { S.build = newBuild('internal'); r = 'conte'; }
  if (r === 'interno-teste') { S.build = newBuild('internal'); r = 'teste'; }
  if (['conte', 'teste', 'ligue'].includes(r) && !S.build) S.build = newBuild('sdr');
  if (r === 'teste' && !S.build.turn) { S.build.turn = 4; script().forEach((s) => { S.build.answers[s.key] = s.ex; }); }
  if (r === 'ligue') { if (!S.build.turn) { S.build.turn = 4; script().forEach((s) => { S.build.answers[s.key] = s.ex; }); } if (!S.build.tested.length) S.build.tested = ['O que vocês fazem?']; }
  const key = { 'agente-clara-resumo': 'resumo', 'agente-lia-resumo': 'resumo', 'agente-clara-sabe': 'sabe', 'agente-clara-onde': 'onde', 'agente-clara-ajustes': 'ajustes', 'agente-clara-testar': 'ptestar' }[r] || r;
  Object.keys(S.view).forEach((k) => { delete S.view[k]; });
  if (st) S.view[key] = st;
  go(r);
}
