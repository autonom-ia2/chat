// ---------- Seus agentes ----------
function agentLine(a) {
  if (a.status === 'todo') return a.empty ? `<span>${icon('pencil-line')}Parou em "Conte". Guardado por 2 dias.</span>` : `<span>${icon('pencil-line')}Parou em "${esc(a.stepName)}". Fica guardado até você terminar ou excluir.</span>`;
  if (a.status === 'ready') return `<span>${icon('plug-zap')}${a.actuation === 'internal' ? 'Falta ligar para a equipe usar' : 'Falta escolher onde atende'}</span>`;
  const parts = [];
  if (a.actuation === 'internal') parts.push(`<span>${icon('users')}Aparece ao lado das conversas da equipe</span>`);
  else if (a.channels.length) parts.push(`<span>${icon(channelById(a.channels[0]).icon)}${esc(CH_LABEL(a.channels[0]))}${a.channels.length > 1 ? ` e mais ${a.channels.length - 1}` : ''}</span>`);
  else parts.push(`<span style="color:var(--a11)">${icon('alert-triangle')}Sem canal: ninguém fala com ${ela(a)}</span>`);
  const w = a.stats[7]; const m = a.stats[30];
  if (a.actuation === 'internal') { /* D14: sem números de uso do ajudante nesta entrega */ }
  else if (w.replies) parts.push(`<span>${icon('activity')}Esta semana: ${w.replies} respostas · passou ${w.handed} para a equipe<span class="newtag">Novo</span></span>`);
  else if (m.replies) parts.push(`<span>${icon('activity')}Nada esta semana · ${m.replies} respostas em 30 dias</span>`);
  else parts.push(`<span>${icon('activity')}Ainda sem conversas</span>`);
  return parts.join('');
}

function agentCard(a) {
  let main;
  if (a.status === 'todo') main = can() ? `<button class="btn primary" data-continue="${a.id}">Continuar</button>` : '';
  else if (a.status === 'ready') main = can() ? `<button class="btn primary" data-continue="${a.id}">${a.actuation === 'internal' ? 'Ligar' : 'Escolher onde atende'}</button>` : '';
  else main = `<button class="btn outline" data-open="${a.id}">Abrir</button>`;
  const tags = [];
  if (a.type === 'insurance_quote') tags.push('<span class="kind">Agente de Cotação</span>');
  if (a.actuation === 'internal') tags.push('<span class="kind">Ajuda a equipe</span>');
  if (a.actuation === 'both') tags.push('<span class="kind">Clientes e equipe</span>');
  const menu = can() && (a.status === 'todo' || a.status === 'ready')
    ? `<div class="ctx"><button class="iconbtn" aria-label="Mais opções de ${esc(a.name)}" aria-haspopup="menu" aria-expanded="${S.open === 'm-' + a.id}" data-menu="m-${a.id}">${icon('more-horizontal')}</button>
      ${S.open === 'm-' + a.id ? `<div class="menu" role="menu"><button role="menuitem" class="red" data-del="${a.id}">${icon('trash-2')}Excluir rascunho</button></div>` : ''}</div>` : '';
  return `<article class="agent">
    ${avatar(a)}
    <div class="body">
      <div class="name">${esc(a.name)} ${tags.join(' ')} ${statusPill(a)}</div>
      <div class="line">${agentLine(a)}</div>
    </div>
    <div class="acts">${switchBtn(a)}${main}${menu}</div>
  </article>`;
}

function viewLista() {
  const st = viewState('lista', 'normal');
  const bar = stateBar('lista', [['normal', 'Com agentes'], ['carregando', 'Carregando'], ['erro', 'Erro ao carregar'], ['vazio', 'Sem nenhum agente']]);
  if (st === 'vazio') return viewVazio(bar);
  const header = `<header class="ph">
      <div><h1 class="h1">Seus agentes</h1>
      <p class="sub">Eles respondem seus clientes e chamam alguém da equipe quando precisam.</p></div>
      ${can() ? `<button class="btn primary lg" data-go="escolha">${icon('plus')}Criar agente</button>` : ''}
    </header>`;
  if (st === 'carregando') {
    return `<div class="page">${bar}${header}<div aria-busy="true" class="list"><span class="sr">Carregando seus agentes</span>
      <div class="skel" style="height:3rem;width:20rem"></div>${'<div class="skel" style="height:6.5rem"></div>'.repeat(3)}</div></div>`;
  }
  if (st === 'erro') {
    return `<div class="page">${bar}${header}<div class="errorbox" role="alert"><span class="tile t-ruby">${icon('cloud-off')}</span>
      <div><b style="font-size:1.125rem">Não deu para carregar seus agentes</b><p class="muted">Pode ser a internet. Seus agentes continuam atendendo normalmente.</p></div>
      <button class="btn soft" data-state="lista:normal">${icon('refresh-cw')}Tentar de novo</button></div></div>`;
  }
  const list = S.agents;
  const on = list.filter((a) => a.status === 'on').length;
  const off = list.filter((a) => a.status === 'off').length;
  const todo = list.filter((a) => a.status === 'todo' || a.status === 'ready').length;
  return `<div class="page">
    ${bar}${header}
    <div class="chips" aria-label="Resumo">
      <span class="count"><span class="dot"></span>${on} atendendo</span>
      <span class="count"><span class="dot slate"></span>${off} pausado${off === 1 ? '' : 's'}</span>
      ${todo ? `<span class="count"><span class="dot amber"></span>${todo} para terminar</span>` : ''}
    </div>
    <section class="list" aria-label="Agentes">${list.map(agentCard).join('')}</section>
    ${!can() ? `<div class="lockline">${icon('lock')}Você pode ver e testar os agentes. Para criar ou mudar, peça a quem administra a conta.</div>` : ''}
    <div class="callout">${icon('info')}<span>Pausou um agente? As conversas que estavam com ele vão para a equipe na hora, e as novas chegam direto para as pessoas.</span></div>
  </div>`;
}

function viewVazio(bar = '') {
  return `<div class="page">${bar}
    <section class="hero">
      <span class="ring" style="width:22rem;height:22rem;right:-6rem;top:-9rem"></span>
      <span class="ring" style="width:14rem;height:14rem;right:9rem;bottom:-9rem;opacity:.08"></span>
      <span class="eyebrow">${icon('sparkles')}Agentes</span>
      <h1>Um agente responde seus clientes enquanto você trabalha</h1>
      <p>Você conta como é o seu negócio, testa as respostas e liga no canal que quiser. Quando ele não souber, chama alguém da equipe.</p>
      ${can() ? `<div class="row"><button class="btn primary lg" data-go="escolha">${icon('plus')}Criar meu primeiro agente</button></div>`
    : '<p style="margin-top:1.25rem">Ainda não há agentes nesta conta. Quem administra a conta pode criar o primeiro.</p>'}
    </section>
    ${can() ? `<div><h2 class="h2">Comece por um destes</h2><p class="muted" style="margin-top:.35rem">Cada um já vem com as perguntas certas. Você ajusta tudo depois.</p></div>
    <div class="grid">${MODELS.slice(0, 3).map((m) => modelCard(m, false)).join('')}</div>` : ''}
  </div>`;
}

function modelCard(m, pressed) {
  return `<button class="model" data-model="${m.id}" aria-pressed="${pressed}">
    <span class="tile ${m.tone}">${icon(m.icon)}</span>
    <b>${esc(m.t)}</b><span class="d">${esc(m.d)}</span>${m.ex ? `<span class="ex">${esc(m.ex)}</span>` : ''}</button>`;
}
