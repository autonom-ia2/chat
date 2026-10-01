// Standalone design prototype. All state is synthetic and stays in memory.
const $ = id => document.getElementById(id);
const esc = value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
const ICONS = {
  sparkles: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5ZM20 2v4M18 4h4"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chevron: '<path d="m6 9 6 6 6-6"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/>',
  settings: '<path d="M4 7h16M4 17h16"/><circle cx="8" cy="7" r="2"/><circle cx="16" cy="17" r="2"/>',
  filter: '<path d="M4 5h16l-6 7v6l-4 2v-8Z"/>',
  board: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16M15 4v16"/>',
  list: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.1M4 12h.1M4 18h.1"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4M17 3v4M3 11h18"/>',
  refresh: '<path d="M20 7v5h-5M4 17v-5h5M5 8a8 8 0 0 1 13-3l2 2M4 17l2 2a8 8 0 0 0 13-3"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
  users: '<circle cx="9" cy="8" r="3"/><path d="M3 20v-2a6 6 0 0 1 12 0v2M16 5a3 3 0 0 1 0 6M18 15a5 5 0 0 1 3 5"/>',
  building: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7h1M15 7h1M8 11h1M15 11h1M10 21v-6h4v6"/>',
  message: '<path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5H3l2-5a8.5 8.5 0 1 1 16-3.5Z"/>',
  phone: '<path d="M5 3h4l2 5-3 2a15 15 0 0 0 6 6l2-3 5 2v4a2 2 0 0 1-2 2C9 21 3 15 3 5a2 2 0 0 1 2-2Z"/>',
  inbox: '<path d="M4 4h16l2 14H2Z M2 14h6l2 3h4l2-3h6"/>',
  bot: '<rect x="4" y="7" width="16" height="14" rx="3"/><path d="M12 3v4M8 12h.1M16 12h.1M9 17h6M2 12v4M22 12v4"/>',
  x: '<path d="m6 6 12 12M18 6 6 18"/>',
  move: '<path d="M4 12h15m-5-5 5 5-5 5"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  wallet: '<rect x="3" y="5" width="18" height="15" rx="2"/><path d="M3 5V3h15M16 11h5v5h-5Z"/>',
  campaign: '<path d="m3 8 18-5v16L3 14ZM7 15l2 6h4l-2-7"/>',
  help: '<circle cx="12" cy="12" r="9"/><path d="M9 9a3 3 0 0 1 6 0c0 2-3 2-3 4M12 17h.1"/>',
  arrowLeft: '<path d="m14 6-6 6 6 6"/>',
  arrowRight: '<path d="m10 6 6 6-6 6"/>',
};
const icon = name => `<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="shrink-0">${ICONS[name] || ICONS.board}</svg>`;
const hydrate = () => document.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icon(el.dataset.icon); });
const secondary = 'inline-flex min-h-11 items-center justify-center gap-2 rounded-lg border border-slate-200 bg-white px-4 text-sm font-medium hover:bg-slate-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600';
const primary = 'inline-flex min-h-11 items-center justify-center gap-2 rounded-lg bg-blue-600 px-4 text-sm font-semibold text-white hover:bg-blue-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600';
const NOW = new Date('2026-10-01T12:00:00-03:00');
const COMPANY = { id: 1, name: 'Norte Logística' };
const PEOPLE = [
  { id: 1, name: 'Mariana Costa', phone_number: '+55 11 90000-0001', company: COMPANY },
  { id: 2, name: 'Ana Clara Souza', phone_number: '+55 11 90000-0002', company: null },
  { id: 3, name: 'Rafael Nunes', phone_number: '+55 11 90000-0003', company: { id: 2, name: 'Alvorada Tecnologia' } },
  { id: 4, name: 'Paulo Henrique', phone_number: '+55 11 90000-0004', company: null },
];
const STAGES = [
  { id: 'new', name: 'Novo', dot: 'bg-blue-600', rail: 'border-s-blue-600', criteria: 'Primeiro contato, antes da qualificação da necessidade.' },
  { id: 'working', name: 'Em atendimento', dot: 'bg-cyan-600', rail: 'border-s-cyan-600', criteria: 'Necessidade sendo entendida, antes de apresentar condições ao cliente.' },
  { id: 'proposal', name: 'Proposta', dot: 'bg-yellow-600', rail: 'border-s-yellow-600', criteria: 'Condições enviadas e cliente avaliando, sem confirmação de compra.' },
  { id: 'closing', name: 'Fechamento', dot: 'bg-green-600', rail: 'border-s-green-600', criteria: 'Cliente confirmou intenção de compra ou próximo passo de contratação.' },
  { id: 'lost', name: 'Perdido', dot: 'bg-red-600', rail: 'border-s-red-600', criteria: 'Recusa ou encerramento sem conversão; silêncio isolado não é suficiente.' },
];
const POST_STAGES = [
  { id: 'received', name: 'Recebido', dot: 'bg-blue-600', rail: 'border-s-blue-600', criteria: 'Solicitação recém-recebida.' },
  { id: 'support', name: 'Em resolução', dot: 'bg-cyan-600', rail: 'border-s-cyan-600', criteria: 'Equipe ou IA está tratando a solicitação.' },
  { id: 'done', name: 'Concluído', dot: 'bg-green-600', rail: 'border-s-green-600', criteria: 'Solicitação resolvida e confirmada.' },
];
const card = (id, stage, title, contactIndex, score, source, who, value = 0, due = null) => ({
  id, stage, title, contact: contactIndex === null ? null : PEOPLE[contactIndex], score,
  scoreSource: source, scoreReason: source === 'ai' ? 'O cliente pediu condições e aguarda uma resposta da equipe.' : source === 'manual' ? 'Prioridade definida pela equipe comercial.' : null,
  ownerId: who === 'Camila Rocha' ? 1 : who === 'João Lima' ? 2 : null,
  responsible: { type: who === 'Agente Gabriela' ? 'bot' : who ? 'agent' : 'none', name: who },
  value, inbox: who === 'Agente Gabriela' ? 'WhatsApp Comercial' : 'Email Comercial',
  lastMessageAt: id % 2 ? '2026-10-01T09:00:00-03:00' : '2026-09-30T16:00:00-03:00',
  nextFollowUpAt: due, nextFollowUpSource: due ? 'manual' : null,
});
const INITIAL = [
  card(1, 'new', 'Implantação do atendimento', 0, 82, 'ai', 'Camila Rocha', 18400),
  card(2, 'new', 'Plano anual', 1, 54, null, 'Agente Gabriela', 1290),
  card(3, 'new', 'Indicação recebida na feira', null, null, null, null),
  card(4, 'working', 'Expansão para a equipe', 2, 67, 'ai', 'Agente Gabriela', 12800),
  card(5, 'working', 'Consultoria inicial', 3, 32, null, 'Camila Rocha', 850),
  card(6, 'working', 'Renovação do suporte', 0, 75, 'manual', 'João Lima', 4500, '2026-10-01T15:00:00-03:00'),
  card(7, 'proposal', 'Licenças para 50 usuários', 2, 91, 'ai', 'Camila Rocha', 42000, '2026-09-30T15:00:00-03:00'),
  card(8, 'proposal', 'Seguro residencial', 3, 19, null, 'João Lima', 2400),
  card(9, 'proposal', 'Automação da operação', 0, 83, 'ai', 'Agente Gabriela', 18000, '2026-10-02T11:00:00-03:00'),
  card(10, 'closing', 'Operação com vários canais', 0, 85, 'manual', 'Camila Rocha', 26700),
  card(11, 'closing', 'Ampliação do plano', 1, 45, null, 'Agente Gabriela', 1800),
];
INITIAL[2].lastMessageAt = null;
INITIAL[0].scoreReason = 'O cliente respondeu há pouco e aguarda o primeiro atendimento.';
INITIAL[8].nextFollowUpSource = 'ai';
const app = {
  pipelines: [{ id: 1, name: 'Email Comercial', stages: STAGES, cards: structuredClone(INITIAL) }, { id: 2, name: 'Pós-venda', stages: POST_STAGES, cards: [card(21, 'received', 'Ajustar canais da equipe', 0, 64, null, 'João Lima'), card(22, 'support', 'Atualizar plano contratado', 1, 80, 'manual', 'Camila Rocha', 0, '2026-10-02T15:00:00-03:00')] }],
  pipelineId: 1, view: 'kanban', filter: 'all', companyId: null, overdueOnly: false, query: '', stageIndex: 0, demoState: 'normal', dragged: null,
};
const pipeline = () => app.pipelines.find(p => p.id === app.pipelineId);
const stage = id => pipeline().stages.find(s => s.id === id);
const findCard = id => pipeline().cards.find(c => c.id === Number(id));
const show = (el, visible) => el.classList.toggle('hidden', !visible);
const FILTERS = { all: 'Todos', mine: 'Minha carteira', unassigned: 'Sem responsável' };
const COMPANY_FILTERS = [{ id: 'all', name: 'Qualquer empresa' }, { id: '1', name: 'Norte Logística' }, { id: '2', name: 'Alvorada Tecnologia' }, { id: 'none', name: 'Sem empresa vinculada' }];
const filterCount = () => Number(app.filter !== 'all') + Number(app.companyId !== null) + Number(app.overdueOnly);
const money = value => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 }).format(value);
const dateLabel = iso => new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' }).format(new Date(iso));
const scoreLabel = c => `Atenção${c.scoreSource === 'ai' ? ' IA' : c.scoreSource === 'manual' ? ' manual' : ''} · ${c.score}`;
const followUpOrigin = c => c.nextFollowUpSource === 'ai' ? 'Retorno por IA' : c.nextFollowUpSource === 'manual' ? 'Retorno manual' : 'Retorno agendado';
const messageAge = c => {
  const hours = Math.max(0, Math.floor((NOW - new Date(c.lastMessageAt)) / 3600000));
  return hours < 24 ? `há ${hours} h` : `há ${Math.floor(hours / 24)} ${hours < 48 ? 'dia' : 'dias'}`;
};
const overdue = c => c.nextFollowUpAt && new Date(c.nextFollowUpAt) < NOW;
const responsible = c => c.responsible.type === 'bot' ? 'IA · Gabriela' : c.responsible.name || 'Sem responsável';
function identity(c) {
  if (!c.contact) return 'Sem contato vinculado';
  const person = c.title === c.contact.name || c.title === c.contact.phone_number ? '' : c.contact.name;
  return [person, c.contact.company?.name].filter(Boolean).join(' · ') || c.contact.phone_number;
}
function matches(criteria = app) {
  if (criteria.demoState === 'empty') return [];
  return pipeline().cards.filter(c => {
    const text = [c.title, c.contact?.name, c.contact?.company?.name, c.contact?.phone_number].filter(Boolean).join(' ').toLocaleLowerCase('pt-BR');
    const queryMatch = text.includes(criteria.query.toLocaleLowerCase('pt-BR'));
    const filterMatch = criteria.filter === 'all' || criteria.filter === 'mine' && c.ownerId === 1 || criteria.filter === 'unassigned' && c.responsible.type === 'none';
    const demoMatch = criteria.demoState !== 'b2c' || c.contact && !c.contact.company;
    const companyMatch = criteria.companyId === null || criteria.companyId === 'none' && !c.contact?.company || String(c.contact?.company?.id) === criteria.companyId;
    return queryMatch && filterMatch && companyMatch && (!criteria.overdueOnly || overdue(c)) && demoMatch;
  }).sort((a, b) => (b.score || 0) - (a.score || 0) || (b.lastMessageAt || '').localeCompare(a.lastMessageAt || '') || b.id - a.id);
}
function renderFiltered() {
  const cards = matches();
  const stages = pipeline().stages;
  if (cards.length && !cards.some(c => c.stage === stages[app.stageIndex].id)) {
    app.stageIndex = stages.findIndex(s => cards.some(c => c.stage === s.id));
  }
  render();
}
function signal(c) {
  if (overdue(c)) return `<span class="inline-flex items-center gap-1 rounded-md bg-rose-50 px-2 py-1 text-xs font-medium text-rose-700" title="${followUpOrigin(c)} · ${esc(dateLabel(c.nextFollowUpAt))}">${icon('clock')}Retorno atrasado</span>`;
  if (c.nextFollowUpAt) return `<span class="inline-flex items-center gap-1 rounded-md bg-amber-50 px-2 py-1 text-xs font-medium text-amber-800" title="${followUpOrigin(c)} · ${esc(dateLabel(c.nextFollowUpAt))}">${icon('calendar')}${c.nextFollowUpSource === 'ai' ? 'IA · ' : ''}Retorno ${new Date(c.nextFollowUpAt).getDate() === NOW.getDate() ? 'hoje' : 'amanhã'}</span>`;
  if (c.score === null) return '';
  const tone = c.scoreSource === 'manual' ? 'border border-slate-300 text-slate-700 bg-white' : !c.scoreSource ? 'bg-slate-100 text-slate-700' : c.score >= 84 ? 'bg-rose-50 text-rose-700' : c.score >= 55 ? 'bg-amber-50 text-amber-800' : 'bg-blue-50 text-blue-700';
  return `<span class="inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ${tone}" title="${esc(c.scoreReason || 'Origem não informada. Atenção não é chance de venda.')}">${esc(scoreLabel(c))}</span>`;
}
function renderCard(c) {
  const hasSignal = Boolean(c.value || c.score !== null || c.nextFollowUpAt);
  return `<article role="listitem" draggable="true" data-card="${c.id}" class="group relative rounded-xl border border-slate-200 border-s-[0.188rem] ${stage(c.stage).rail} bg-white px-3 pb-3 pt-1.5 shadow-sm transition-colors hover:shadow-md motion-reduce:transition-none" aria-label="${esc(c.title)}. Status ${stage(c.stage).name}. ${esc(identity(c))}. Responsável ${esc(responsible(c))}${c.score !== null ? `. ${esc(scoreLabel(c))}` : ''}">
    <div class="flex items-start gap-1"><button data-open="${c.id}" class="min-h-11 min-w-0 flex-1 rounded text-start text-sm font-semibold leading-5 focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600">${esc(c.title)}</button><button data-move="${c.id}" aria-label="Mover ${esc(c.title)} para outro status" class="flex h-11 shrink-0 items-center gap-1 rounded-lg px-2 text-xs font-medium text-slate-600 hover:bg-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600">Mover ${icon('chevron')}</button></div>
    <p class="mt-0.5 flex min-w-0 items-start gap-1.5 text-xs leading-5 text-slate-600">${icon(c.contact?.company ? 'building' : 'user')}<span class="min-w-0 break-words">${esc(identity(c))}</span></p>
    ${hasSignal ? `<div class="mt-3 flex min-h-7 flex-wrap items-center justify-between gap-1"><span class="text-sm font-medium tabular-nums">${c.value ? money(c.value) : ''}</span>${signal(c)}</div>` : ''}
    <div class="mt-3 flex items-center justify-between gap-2 border-t border-slate-100 pt-2 text-xs text-slate-600"><span class="flex min-w-0 items-center gap-1.5" title="Responsável: ${esc(responsible(c))}">${icon(c.responsible.type === 'bot' ? 'bot' : 'user')}<span class="truncate">${esc(responsible(c))}</span></span>${c.lastMessageAt ? `<span class="flex shrink-0 items-center gap-1" title="Última mensagem · ${esc(dateLabel(c.lastMessageAt))}">${icon('message')}${messageAge(c)}</span>` : ''}</div>
  </article>`;
}
function render() {
  const focused = document.activeElement;
  const focusKey = ['view', 'filter', 'step'].find(key => focused?.dataset[key]);
  const focusValue = focusKey && focused.dataset[focusKey];
  const p = pipeline();
  const cards = matches();
  app.stageIndex = Math.min(app.stageIndex, p.stages.length - 1);
  $('pipeline-label').textContent = p.name;
  $('results').textContent = app.demoState === 'loading' ? 'Carregando oportunidades…' : app.demoState === 'error' ? 'Quadro indisponível' : `${cards.length} ${cards.length === 1 ? 'oportunidade' : 'oportunidades'}${cards.length !== p.cards.length ? ` de ${p.cards.length} no funil` : ' no funil'}`;
  $('clear-button').textContent = filterCount() > 0 ? 'Limpar filtros' : app.query ? 'Limpar busca' : 'Limpar filtros';
  show($('clear-button'), Boolean(app.query || filterCount() > 0 || app.demoState === 'b2c' || app.demoState === 'empty'));
  show($('filter-badge'), filterCount() > 0);
  $('filter-badge').textContent = filterCount();
  $('filter-button').setAttribute('aria-pressed', String(filterCount() > 0));
  $('company-label').textContent = COMPANY_FILTERS.find(item => item.id === (app.companyId || 'all')).name;
  $('overdue-button').setAttribute('aria-pressed', String(app.overdueOnly));
  $('overdue-button').classList.toggle('bg-white', !app.overdueOnly);
  $('overdue-button').classList.toggle('border-slate-200', !app.overdueOnly);
  $('overdue-button').classList.toggle('bg-blue-50', app.overdueOnly);
  $('overdue-button').classList.toggle('text-blue-700', app.overdueOnly);
  $('overdue-button').classList.toggle('border-blue-600', app.overdueOnly);
  renderViews();
  $('filters-results').textContent = `Ver ${cards.length} ${cards.length === 1 ? 'oportunidade' : 'oportunidades'}`;
  const applied = [];
  if (app.companyId !== null) applied.push(['company', `Empresa: ${COMPANY_FILTERS.find(item => item.id === app.companyId).name}`]);
  if (app.filter !== 'all') applied.push(['owner', FILTERS[app.filter]]);
  if (app.overdueOnly) applied.push(['overdue', 'Retornos atrasados']);
  $('applied-filters').innerHTML = applied.map(([key, label]) => `<button data-remove-filter="${key}" aria-label="Remover filtro ${esc(label)}" class="flex min-h-11 items-center gap-2 rounded-lg border border-blue-100 bg-blue-50 px-3 text-xs font-medium text-blue-800 hover:bg-blue-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600">${esc(label)}${icon('x')}</button>`).join('');
  show($('applied-filters'), applied.length > 0);
  $('applied-filters').classList.toggle('flex', applied.length > 0);

  $('filter-options').innerHTML = Object.entries(FILTERS).map(([id, label]) => `<button type="button" data-filter="${id}" aria-pressed="${app.filter === id}" class="min-h-11 rounded-lg border px-3 text-sm ${app.filter === id ? 'border-blue-600 bg-blue-50 font-medium text-blue-700' : 'border-slate-200 bg-white text-slate-700 hover:bg-slate-100'} focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600">${label}</button>`).join('');
  const isState = ['loading', 'error', 'empty'].includes(app.demoState) || cards.length === 0;
  show($('state-panel'), isState);
  show($('board'), !isState && app.view === 'kanban');
  show($('list'), !isState && app.view === 'list');
  show($('calendar'), !isState && app.view === 'calendar');
  $('mobile-stages').classList.toggle('hidden', isState || app.view !== 'kanban');
  $('mobile-stages').classList.toggle('flex', !isState && app.view === 'kanban');
  $('mobile-stages').innerHTML = `<button data-step="-1" aria-label="Status anterior" ${app.stageIndex === 0 ? 'disabled' : ''} class="flex h-11 w-11 items-center justify-center rounded-lg hover:bg-slate-50 disabled:opacity-30">${icon('arrowLeft')}</button><div class="min-w-0 flex-1 text-center"><span class="text-sm font-medium">${p.stages[app.stageIndex].name}<span class="ms-2 rounded bg-slate-100 px-1.5 text-xs">${cards.filter(c => c.stage === p.stages[app.stageIndex].id).length}</span></span><p class="mt-0.5 text-xs text-slate-600">${app.stageIndex + 1} de ${p.stages.length} status</p></div><button data-criteria="${p.stages[app.stageIndex].id}" aria-label="Quando usar ${p.stages[app.stageIndex].name}" class="flex h-11 w-11 items-center justify-center rounded-lg text-slate-600 hover:bg-slate-50">${icon('help')}</button><button data-step="1" aria-label="Próximo status" ${app.stageIndex === p.stages.length - 1 ? 'disabled' : ''} class="flex h-11 w-11 items-center justify-center rounded-lg hover:bg-slate-50 disabled:opacity-30">${icon('arrowRight')}</button>`;
  $('board').innerHTML = p.stages.map((s, index) => {
    const stageCards = cards.filter(c => c.stage === s.id);
    return `<section data-stage="${s.id}" aria-labelledby="stage-${s.id}" class="${index === app.stageIndex ? 'flex' : 'hidden md:flex'} min-h-0 w-full shrink-0 flex-col rounded-xl bg-slate-100/80 md:w-[19rem]"><header class="hidden h-14 shrink-0 md:flex items-center justify-between gap-2 px-3"><h2 id="stage-${s.id}" class="flex items-center gap-2 text-sm font-semibold"><span class="h-2.5 w-2.5 rounded-sm ${s.dot}"></span>${s.name}</h2><div class="flex items-center gap-1"><span class="rounded-md bg-white px-2 py-1 text-xs font-medium tabular-nums text-slate-600" aria-label="${stageCards.length} oportunidades em ${s.name}">${stageCards.length}</span><button data-criteria="${s.id}" aria-label="Quando usar ${s.name}" class="flex h-11 w-11 items-center justify-center rounded-lg text-slate-600 hover:bg-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600">${icon('help')}</button></div></header><div data-drop="${s.id}" role="list" aria-label="Oportunidades em ${s.name}" class="min-h-0 flex-1 space-y-3 overflow-y-auto px-2 pb-3">${stageCards.length ? stageCards.map(renderCard).join('') : '<p class="flex min-h-32 items-center justify-center rounded-xl border border-dashed border-slate-300 px-4 text-center text-sm text-slate-600">Nenhuma oportunidade neste status</p>'}</div></section>`;
  }).join('');
  $('list').innerHTML = `<div class="overflow-x-auto rounded-xl border border-slate-200 bg-white"><table class="w-full text-start text-sm"><caption class="sr-only">Oportunidades do funil ${esc(p.name)}</caption><thead class="border-b bg-slate-50 text-xs text-slate-600"><tr>${['Oportunidade e contato', 'Status', 'Responsável', 'Valor', 'Ações'].map(t => `<th scope="col" class="px-4 py-3 text-start font-medium">${t}</th>`).join('')}</tr></thead><tbody>${cards.map(c => `<tr class="border-b last:border-0"><td class="min-w-60 px-4 py-3"><button data-open="${c.id}" class="min-h-11 text-start font-semibold text-blue-700">${esc(c.title)}</button><p class="text-xs text-slate-600">${esc(identity(c))}</p></td><td class="px-4 py-3">${stage(c.stage).name}</td><td class="px-4 py-3">${esc(responsible(c))}</td><td class="whitespace-nowrap px-4 py-3 tabular-nums">${c.value ? money(c.value) : '—'}</td><td class="px-4 py-3"><button data-move="${c.id}" class="${secondary}">Mover</button></td></tr>`).join('')}</tbody></table></div>`;
  renderCalendar(cards);
  if (isState) renderState();
  hydrate();
  if (focusKey) [...document.querySelectorAll(`[data-${focusKey}="${focusValue}"]`)].find(el => el.getClientRects().length > 0)?.focus({ preventScroll: true });
  requestAnimationFrame(updateColumnNavigation);
}
function updateColumnNavigation() {
  const area = $('board-area');
  const hasMore = area.scrollWidth > area.clientWidth + 1;
  $('columns-nav').classList.toggle('md:flex', app.view === 'kanban' && !$('board').classList.contains('hidden') && hasMore);
  $('previous-columns').disabled = area.scrollLeft <= 1;
  $('next-columns').disabled = area.scrollLeft + area.clientWidth >= area.scrollWidth - 1;
}
function renderViews() {
  const views = [['kanban', 'Kanban', 'board'], ['list', 'Lista', 'list'], ['calendar', 'Calendário', 'calendar']];
  for (const id of ['desktop-views', 'mobile-views']) $(id).innerHTML = views.map(([value, label, glyph]) => `<button data-view="${value}" aria-pressed="${app.view === value}" class="flex min-h-9 flex-1 items-center justify-center gap-1.5 rounded-md px-3 text-sm ${app.view === value ? 'bg-white font-medium text-slate-900 shadow-sm' : 'text-slate-600 hover:bg-white/60'} focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600">${icon(glyph)}${label}</button>`).join('');
}
function renderCalendar(cards) {
  const dueCards = cards.filter(c => c.nextFollowUpAt);
  $('calendar').innerHTML = `<div class="rounded-xl border border-slate-200 bg-white p-4"><h2 class="text-base font-semibold">Retornos agendados</h2><p class="mt-1 text-sm text-slate-600">${dueCards.length} ${dueCards.length === 1 ? 'retorno' : 'retornos'} neste funil</p><div class="mt-4 space-y-3">${dueCards.sort((a, b) => a.nextFollowUpAt.localeCompare(b.nextFollowUpAt)).map(c => `<button data-open="${c.id}" class="flex min-h-16 w-full flex-wrap items-center justify-between gap-2 rounded-lg border border-slate-200 px-4 py-3 text-start hover:bg-slate-50"><span><strong class="block text-sm">${esc(c.title)}</strong><span class="text-xs text-slate-600">${esc(identity(c))}</span></span><span class="text-sm ${overdue(c) ? 'font-medium text-rose-700' : 'text-slate-700'}">${dateLabel(c.nextFollowUpAt)}</span></button>`).join('') || '<p class="rounded-lg bg-slate-50 p-4 text-sm text-slate-600">Nenhum retorno agendado nas oportunidades exibidas.</p>'}</div></div>`;
}
function renderState() {
  const loading = app.demoState === 'loading';
  const error = app.demoState === 'error';
  $('state-panel').innerHTML = loading ? `<div aria-busy="true" class="grid grid-cols-1 gap-4 md:grid-cols-3">${[1, 2, 3].map(() => '<div class="h-80 rounded-xl border border-slate-200 bg-slate-100 p-4"><span class="block h-4 w-24 rounded bg-slate-200"></span><div class="mt-6 h-32 rounded-lg bg-white"></div><div class="mt-4 h-32 rounded-lg bg-white"></div></div>').join('')}</div><p class="mt-4 text-sm text-slate-600">Carregando oportunidades…</p>` : `<div class="mx-auto mt-12 max-w-md rounded-xl border border-slate-200 bg-white p-8 text-center">${icon(error ? 'refresh' : 'search')}<h2 class="mt-3 text-lg font-semibold">${error ? 'Não foi possível carregar o quadro' : filterCount() > 0 || app.query ? 'Nenhuma oportunidade com esses filtros' : 'Nenhuma oportunidade encontrada'}</h2><p class="mt-2 text-sm leading-6 text-slate-600">${error ? 'Tente novamente para continuar de onde parou.' : 'Você pode limpar a pesquisa e os filtros ou criar uma oportunidade.'}</p><button data-recover class="${primary} mt-5">${error ? 'Tentar novamente' : 'Limpar busca e filtros'}</button></div>`;
}
let returnFocus;
let returnCardId;
let returnAction;
function restoreFocus() {
  const current = returnCardId && [...document.querySelectorAll(`[data-${returnAction}="${returnCardId}"]`)].find(el => el.getClientRects().length > 0);
  (current || returnFocus)?.focus();
}
function openDrawer(title, subtitle, content, footer) {
  if (!$('drawer').open) {
    const active = document.activeElement;
    returnFocus = active?.closest('#config-menu') ? $('config-button') : active?.closest('#pipeline-menu') ? $('pipeline-button') : active?.closest('#company-menu') ? $('company-button') : active;
    returnCardId = returnFocus?.dataset.move || returnFocus?.dataset.open || null;
    returnAction = returnFocus?.dataset.open ? 'open' : 'move';
  }
  closeMenus();
  $('drawer-title').textContent = title;
  $('drawer-subtitle').textContent = subtitle;
  $('drawer-content').innerHTML = content;
  $('drawer-footer').innerHTML = footer || `<button data-close class="${secondary}">Voltar ao quadro</button>`;
  hydrate();
  if (!$('drawer').open) $('drawer').showModal();
}
function closeDrawer() { $('drawer').close(); restoreFocus(); }
function details(id) {
  const c = findCard(id);
  openDrawer(c.title, 'Oportunidade e relacionamento', `<div class="flex items-center gap-2 text-sm"><span class="h-2.5 w-2.5 rounded-sm ${stage(c.stage).dot}"></span>${stage(c.stage).name}</div><section class="mt-6"><h3 class="text-base font-semibold">Quem está nesta oportunidade?</h3><div class="mt-4 rounded-xl border border-slate-200 p-4"><p class="text-xs text-slate-600">Contato</p><p class="mt-1 font-medium">${esc(c.contact?.name || 'Sem contato vinculado')}</p>${c.contact ? `<p class="mt-1 text-sm text-slate-600">${esc(c.contact.phone_number)}</p>` : ''}${c.contact?.company ? `<div class="mt-4 border-t border-slate-100 pt-4"><p class="text-xs text-slate-600">Empresa vinculada</p><p class="mt-1 flex items-center gap-2 font-medium">${icon('building')}${esc(c.contact.company.name)}</p></div>` : ''}</div></section><section class="mt-6"><h3 class="text-base font-semibold">Atendimento</h3><dl class="mt-4 grid grid-cols-1 gap-4 rounded-xl bg-slate-50 p-4 sm:grid-cols-2"><div><dt class="text-xs text-slate-600">Responsável</dt><dd class="mt-1 text-sm font-medium">${esc(responsible(c))}</dd></div><div><dt class="text-xs text-slate-600">Caixa de entrada</dt><dd class="mt-1 text-sm font-medium">${esc(c.inbox)}</dd></div><div><dt class="text-xs text-slate-600">Valor estimado</dt><dd class="mt-1 text-sm font-medium">${c.value ? money(c.value) : 'Não informado'}</dd></div><div><dt class="text-xs text-slate-600">Última mensagem</dt><dd class="mt-1 text-sm font-medium">${c.lastMessageAt ? dateLabel(c.lastMessageAt) : 'Sem conversa vinculada'}</dd></div></dl></section>${c.score !== null ? `<section class="mt-6 rounded-xl border border-blue-100 bg-blue-50 p-4"><h3 class="text-sm font-semibold">${esc(scoreLabel(c))}</h3><p class="mt-2 text-sm leading-6 text-slate-700">${esc(c.scoreReason || 'A origem desta avaliação não foi informada.')}</p><p class="mt-2 text-xs text-slate-600">Indica atenção necessária. Não é chance de venda.</p></section>` : ''}${c.nextFollowUpAt ? `<section class="mt-6"><h3 class="text-sm font-semibold">${followUpOrigin(c)}</h3><p class="mt-2 text-sm">${dateLabel(c.nextFollowUpAt)}</p></section>` : ''}`, `<button data-close class="${secondary}">Fechar</button><button data-move="${c.id}" class="${primary}">Mover para ${icon('move')}</button>`);
}
function moveMenu(id) {
  const c = findCard(id);
  openDrawer('Mover oportunidade', c.title, `<p class="text-sm leading-6 text-slate-600">Escolha o status que representa o momento da conversa.</p><div class="mt-5 space-y-2">${pipeline().stages.map(s => `<button data-destination="${s.id}" data-card-id="${c.id}" ${c.stage === s.id ? 'disabled' : ''} class="flex min-h-16 w-full items-center justify-between gap-3 rounded-xl border ${c.stage === s.id ? 'border-blue-200 bg-blue-50 text-blue-800' : 'border-slate-200 hover:bg-slate-50'} px-4 py-3 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600"><span class="flex items-center gap-3"><span class="h-3 w-3 shrink-0 rounded-sm ${s.dot}"></span><span><strong class="block text-sm font-medium">${s.name}</strong><span class="mt-1 block text-xs leading-5 text-slate-600">${esc(s.criteria)}</span></span></span>${c.stage === s.id ? '<span class="text-xs">Atual</span>' : icon('move')}</button>`).join('')}</div>`);
}
function moveCard(id, destination) {
  const c = findCard(id);
  if (c.stage === destination) return;
  const previous = c.stage;
  c.stage = destination;
  app.stageIndex = pipeline().stages.findIndex(s => s.id === destination);
  if ($('drawer').open) closeDrawer();
  render();
  restoreFocus();
  toast(`${c.title} movida para ${stage(destination).name}.`, { id: c.id, previous });
}
let undoMove;
let toastTimer;
function toast(message, undo) {
  undoMove = undo || null;
  $('toast').innerHTML = `${esc(message)}${undo ? '<button id="undo-button" class="ms-3 min-h-11 rounded px-2 font-semibold underline">Desfazer</button><button id="dismiss-toast" aria-label="Fechar aviso" class="ms-1 min-h-11 rounded px-2">×</button>' : ''}`;
  show($('toast'), true);
  clearTimeout(toastTimer);
  if (!undo) toastTimer = setTimeout(() => show($('toast'), false), 7000);
}
function closeMenus() { show($('config-menu'), false); show($('pipeline-menu'), false); show($('company-menu'), false); $('company-button').setAttribute('aria-expanded', 'false'); $('config-button').setAttribute('aria-expanded', 'false'); $('pipeline-button').setAttribute('aria-expanded', 'false'); }
function menu(id, trigger) {
  const visible = $(id).classList.contains('hidden');
  closeMenus();
  show($(id), visible);
  $(trigger).setAttribute('aria-expanded', String(visible));
  if (visible) $(id).querySelector('button')?.focus();
}
function menus() {
  $('company-menu').innerHTML = `<label for="company-search" class="sr-only">Pesquisar empresa</label><input id="company-search" role="combobox" aria-expanded="true" aria-controls="company-options" placeholder="Pesquisar empresa" class="mb-2 h-11 w-full rounded-lg border border-slate-200 px-3 text-base outline-none focus:border-blue-600"/><div id="company-options" role="listbox" aria-label="Empresas"></div>`;
  $('company-search').addEventListener('input', renderCompanyOptions);
  renderCompanyOptions();
  $('pipeline-menu').innerHTML = app.pipelines.map(p => `<button role="menuitemradio" aria-checked="${p.id === app.pipelineId}" data-pipeline="${p.id}" class="flex min-h-11 w-full items-center justify-between rounded-lg px-3 text-start text-sm hover:bg-slate-50">${esc(p.name)}${p.id === app.pipelineId ? icon('check') : ''}</button>`).join('');
  $('config-menu').innerHTML = [['edit', 'Editar funil', 'Nome, status, critérios IA e caixas'], ['handoff', 'Responsáveis e repasse', 'Quem recebe e quando passar à equipe'], ['inboxes', 'Caixas de entrada', 'Gestão das caixas da conta'], ['booking', 'Página de agendamento', 'Como os clientes marcam horário']].map(([key, name, desc]) => `<button role="menuitem" data-config="${key}" class="block min-h-16 w-full rounded-lg px-3 py-3 text-start hover:bg-slate-50"><strong class="block text-sm font-medium">${name}</strong><span class="mt-1 block text-xs text-slate-600">${desc}</span></button>`).join('');
}
function renderCompanyOptions() {
  const query = $('company-search').value.toLocaleLowerCase('pt-BR');
  const items = COMPANY_FILTERS.filter(item => item.name.toLocaleLowerCase('pt-BR').includes(query));
  $('company-options').innerHTML = items.map(item => `<button role="option" aria-selected="${item.id === (app.companyId || 'all')}" data-company="${item.id}" class="flex min-h-11 w-full items-center justify-between gap-3 rounded-lg px-3 text-start text-sm hover:bg-slate-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600">${item.name}${item.id === (app.companyId || 'all') ? icon('check') : ''}</button>`).join('') || '<p class="px-3 py-4 text-sm text-slate-600">Nenhuma empresa encontrada.</p>';
}
const AI_DEMOS = {
  overdue: { text: 'Mostre os retornos atrasados da Alvorada Tecnologia.', companyId: '2', filter: 'all', overdueOnly: true, note: 'Buscar as oportunidades da Alvorada Tecnologia com retorno já vencido.' },
  mine: { text: 'Quero as oportunidades da Norte Logística sob meus cuidados.', companyId: '1', filter: 'mine', overdueOnly: false, note: 'Buscar as oportunidades da Norte Logística atribuídas a você.' },
  unassigned: { text: 'Quais oportunidades ainda estão sem responsável?', companyId: null, filter: 'unassigned', overdueOnly: false, note: 'Buscar as oportunidades que ainda não têm responsável.' },
};
let aiDemoId = null;
function aiFilters() {
  aiDemoId = null;
  openDrawer('Encontrar com IA', `Funil ${pipeline().name}`, `<p id="ai-demo-note" class="rounded-lg bg-slate-100 px-3 py-2 text-xs leading-5 text-slate-600">Prévia visual com exemplos. Nenhum modelo foi chamado.</p><p class="mt-4 text-sm leading-6 text-slate-700">Descreva o que procura. A IA sugere filtros para você conferir.</p><label for="ai-request" class="mt-4 block text-sm font-semibold">O que você quer encontrar?</label><textarea id="ai-request" rows="2" placeholder="Ex.: quero os retornos atrasados de uma empresa" class="mt-2 w-full rounded-xl border border-slate-300 px-4 py-3 text-base leading-6 outline-none focus:border-blue-600 focus:ring-1 focus:ring-blue-600"></textarea><div class="mt-2 flex justify-end"><button id="ai-understand" disabled class="${secondary} text-blue-700 disabled:opacity-40">${icon('sparkles')}Entender pedido</button></div><details id="ai-examples" open class="mt-2"><summary class="min-h-11 cursor-pointer text-sm leading-[2.75rem] text-blue-700">Experimente um exemplo</summary><div class="mt-2 space-y-2">${Object.entries(AI_DEMOS).map(([key, demo]) => `<button data-ai-example="${key}" class="min-h-11 w-full rounded-lg border border-slate-200 px-3 py-2 text-start text-sm leading-5 hover:bg-slate-50">${demo.text}</button>`).join('')}</div></details><div id="ai-result" class="mt-4"></div>`, `<button data-close class="${secondary}">Cancelar</button><button id="ai-apply" disabled class="${primary} disabled:opacity-40">Usar estes filtros</button>`);
  $('ai-request').addEventListener('input', () => { aiDemoId = null; $('ai-understand').disabled = true; show($('ai-examples'), true); $('ai-result').innerHTML = ''; $('ai-apply').disabled = true; $('ai-demo-note').textContent = 'A interpretação de texto livre será conectada ao GPT-6 Luna após aprovação. Nesta prévia, escolha um exemplo.'; });
  $('ai-understand').addEventListener('click', aiFilterSuggestion);
  $('ai-apply').addEventListener('click', () => {
    const demo = AI_DEMOS[aiDemoId];
    app.companyId = demo.companyId; app.filter = demo.filter; app.overdueOnly = demo.overdueOnly; app.query = ''; $('search').value = ''; app.demoState = 'normal';
    closeDrawer(); if ($('filters-drawer').open) $('filters-drawer').close(); show($('filter-panel'), false); $('filter-button').setAttribute('aria-expanded', 'false'); renderFiltered(); $('filter-button').focus();
  });
}
function aiFilterSuggestion() {
  if (!aiDemoId) return;
  const demo = AI_DEMOS[aiDemoId];
  show($('ai-examples'), false);
  const count = matches({ ...app, companyId: demo.companyId, filter: demo.filter, overdueOnly: demo.overdueOnly, query: '', demoState: 'normal' }).length;
  const chips = [demo.companyId && COMPANY_FILTERS.find(item => item.id === demo.companyId).name, demo.filter !== 'all' && FILTERS[demo.filter], demo.overdueOnly && 'Retornos atrasados'].filter(Boolean);
  $('ai-result').innerHTML = `<section class="rounded-xl border border-blue-200 bg-blue-50 p-4"><h3 class="flex items-center gap-2 text-sm font-semibold text-navy">${icon('sparkles')}A IA entendeu</h3><p class="mt-3 text-sm leading-6 text-slate-700">${demo.note}</p><div class="mt-3 flex flex-wrap gap-2">${chips.map(label => `<span class="rounded-lg border border-blue-100 bg-white px-3 py-2 text-xs font-medium text-blue-800">${label}</span>`).join('')}</div><p class="mt-4 text-sm font-semibold text-navy">${count} ${count === 1 ? 'oportunidade corresponde' : 'oportunidades correspondem'}</p><p class="mt-1 text-xs leading-5 text-slate-600">Ao confirmar, estes filtros substituirão os atuais. Você poderá ajustá-los no quadro.</p></section>`;
  $('ai-apply').disabled = false;
}
function createOpportunity() {
  openDrawer('Nova oportunidade', `Funil ${pipeline().name}`, `<form id="new-form"><label for="new-title" class="block text-sm font-medium">Nome da oportunidade</label><input id="new-title" name="title" required maxlength="100" placeholder="Ex.: Renovação do plano" class="mt-2 h-12 w-full rounded-lg border border-slate-300 px-3 text-base outline-none focus:border-blue-600 focus:ring-1 focus:ring-blue-600" /><fieldset class="mt-6"><legend class="text-sm font-medium">Contato</legend><div class="mt-3 space-y-2">${[null, ...PEOPLE.slice(0, 2)].map((person, index) => `<label class="flex min-h-14 cursor-pointer items-center gap-3 rounded-lg border border-slate-200 px-4 py-3"><input type="radio" name="contact" value="${person?.id || ''}" ${index === 0 ? 'checked' : ''} class="h-4 w-4 accent-blue-600"/><span class="text-sm">${esc(person?.name || 'Continuar sem contato vinculado')}${person?.company ? `<span class="mt-1 block text-xs text-slate-600">${esc(person.company.name)}</span>` : ''}</span></label>`).join('')}</div></fieldset><p class="mt-6 text-sm text-slate-600">Status inicial: <strong>${pipeline().stages[0].name}</strong></p></form>`, `<button data-close class="${secondary}">Cancelar</button><button type="submit" form="new-form" class="${primary}">Criar oportunidade</button>`);
  $('new-title').focus();
}
function configuration(key) {
  if (key === 'new-pipeline') {
    openDrawer('Criar funil', 'Organize um novo processo de atendimento.', '<form id="pipeline-form"><label for="new-pipeline-name" class="block text-sm font-medium">Nome do funil</label><input id="new-pipeline-name" required maxlength="60" class="mt-2 h-12 w-full rounded-lg border border-slate-300 px-3 text-base outline-none focus:border-blue-600" placeholder="Ex.: Pós-venda"/></form>', `<button data-close class="${secondary}">Cancelar</button><button type="submit" form="pipeline-form" class="${primary}">Criar funil</button>`);
    $('new-pipeline-name').focus();
    return;
  }
  const titles = { edit: 'Editar funil', handoff: 'Responsáveis e repasse', inboxes: 'Caixas de entrada', booking: 'Página de agendamento' };
  const body = key === 'edit' ? `<h3 class="text-base font-semibold">Status do funil</h3><p class="mt-2 text-sm leading-6 text-slate-600">As descrições orientam a IA a reconhecer o momento da conversa.</p><div class="mt-4 space-y-2">${pipeline().stages.map((s, i) => `<div class="flex items-start gap-3 rounded-xl border border-slate-200 p-4"><span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-blue-50 text-sm font-medium text-blue-700">${i + 1}</span><div><h4 class="text-sm font-semibold">${s.name}</h4><p class="mt-1 text-sm leading-6 text-slate-600">${esc(s.criteria)}</p></div></div>`).join('')}</div><section class="mt-6"><h3 class="text-base font-semibold">Caixas conectadas ao funil</h3><p class="mt-3 rounded-lg border border-slate-200 p-4 text-sm">WhatsApp Comercial · Email Comercial</p></section>` : key === 'handoff' ? '<h3 class="text-base font-semibold">Quem cuida das oportunidades?</h3><p class="mt-3 text-sm leading-6 text-slate-600">Atribuição define quem recebe cada oportunidade. Repasse define quando a IA chama a equipe para continuar o atendimento.</p><div class="mt-5 rounded-xl border border-slate-200 p-4"><p class="text-sm font-medium">Equipe comercial</p><p class="mt-2 text-sm text-slate-600">Camila Rocha · João Lima</p></div>' : key === 'inboxes' ? '<h3 class="text-base font-semibold">Caixas da conta</h3><div class="mt-4 space-y-3"><p class="rounded-xl border border-slate-200 p-4 text-sm">WhatsApp Comercial</p><p class="rounded-xl border border-slate-200 p-4 text-sm">Email Comercial</p></div><p class="mt-5 text-sm leading-6 text-slate-600">Para conectar mais de uma caixa ao mesmo funil, use a última etapa do Editar Funil.</p>' : '<h3 class="text-base font-semibold">Agendamento dos clientes</h3><p class="mt-3 text-sm leading-6 text-slate-600">Uma página para escolher um horário disponível e vincular o agendamento à oportunidade.</p><p class="mt-4 rounded-xl bg-slate-50 p-4 text-sm">Atendimento comercial · 30 minutos</p>';
  openDrawer(titles[key], pipeline().name, body);
}
document.addEventListener('click', event => {
  const button = event.target.closest('button');
  if (!button) return;
  const d = button.dataset;
  if (d.aiExample) { aiDemoId = d.aiExample; $('ai-examples').open = false; $('ai-request').value = AI_DEMOS[aiDemoId].text; $('ai-understand').disabled = false; $('ai-result').innerHTML = ''; $('ai-apply').disabled = true; $('ai-demo-note').textContent = 'Prévia visual com exemplos. Nenhum modelo foi chamado.'; }
  else if (d.open) details(d.open);
  else if (d.move) moveMenu(d.move);
  else if (d.destination) moveCard(d.cardId, d.destination);
  else if (d.view) { app.view = d.view; render(); }
  else if (d.filter) { app.filter = d.filter; renderFiltered(); }
  else if (d.removeFilter) { if (d.removeFilter === 'owner') app.filter = 'all'; else if (d.removeFilter === 'company') app.companyId = null; else app.overdueOnly = false; renderFiltered(); $('filter-button').focus(); }
  else if (d.company) { app.companyId = d.company === 'all' ? null : d.company; closeMenus(); renderFiltered(); $('company-button').focus(); }
  else if (d.pipeline) { app.pipelineId = Number(d.pipeline); app.query = ''; $('search').value = ''; app.filter = 'all'; app.companyId = null; app.overdueOnly = false; app.demoState = 'normal'; app.stageIndex = 0; closeMenus(); menus(); render(); $('pipeline-button').focus(); }
  else if (d.config) configuration(d.config);
  else if (d.step) { app.stageIndex += Number(d.step); render(); }
  else if (d.criteria) openDrawer(`Quando usar ${stage(d.criteria).name}`, 'Critério do status', `<p class="text-base leading-7">${esc(stage(d.criteria).criteria)}</p><p class="mt-6 rounded-xl bg-blue-50 p-4 text-sm leading-6 text-slate-700">Esta descrição orienta a IA. Você pode ajustá-la no Editar Funil.</p>`, `<button data-close class="${secondary}">Voltar ao quadro</button><button data-config="edit" class="${primary}">${icon('settings')}Editar funil</button>`);
  else if (d.close !== undefined) closeDrawer();
  else if (d.recover !== undefined) { if (app.demoState === 'error') { app.demoState = 'normal'; render(); } else resetFilters(); }
  else if (d.demoNav) toast('Navegação de contexto ilustrada. Este protótipo concentra a área CRM.');
  else if (d.scenario) { app.demoState = d.scenario; app.query = ''; $('search').value = ''; app.filter = 'all'; app.companyId = null; app.overdueOnly = false; closeDrawer(); render(); }
  else if (button.id === 'dismiss-toast') show($('toast'), false);
  else if (button.id === 'undo-button' && undoMove) { const c = findCard(undoMove.id); if (c) { c.stage = undoMove.previous; app.stageIndex = pipeline().stages.findIndex(s => s.id === c.stage); render(); } show($('toast'), false); undoMove = null; }
});
document.addEventListener('submit', event => {
  event.preventDefault();
  if (event.target.id === 'new-form') {
    const data = new FormData(event.target);
    const title = String(data.get('title')).trim();
    if (!title) return;
    const contactId = Number(data.get('contact'));
    const c = card(Date.now(), pipeline().stages[0].id, title, null, null, null, null);
    c.contact = PEOPLE.find(person => person.id === contactId) || null;
    c.lastMessageAt = null;
    pipeline().cards.push(c); closeDrawer(); resetFilters(); toast('Oportunidade criada nos dados fictícios.');
  } else if (event.target.id === 'pipeline-form') {
    const name = $('new-pipeline-name').value.trim();
    if (!name) return;
    const id = Date.now(); app.pipelines.push({ id, name, stages: structuredClone(STAGES), cards: [] }); app.pipelineId = id;
    closeDrawer(); menus(); resetFilters(); toast('Funil criado nos dados fictícios.');
  }
});
function resetFilters() { app.query = ''; $('search').value = ''; app.filter = 'all'; app.companyId = null; app.overdueOnly = false; app.demoState = 'normal'; app.stageIndex = 0; render(); }
window.addEventListener('resize', updateColumnNavigation);
$('board-area').addEventListener('scroll', updateColumnNavigation);
$('previous-columns').addEventListener('click', () => $('board-area').scrollBy({ left: -640, behavior: 'smooth' }));
$('next-columns').addEventListener('click', () => $('board-area').scrollBy({ left: 640, behavior: 'smooth' }));
$('search').addEventListener('input', event => { app.query = event.target.value; renderFiltered(); });
$('new-button').addEventListener('click', createOpportunity);
$('drawer-close').addEventListener('click', closeDrawer);
$('drawer').addEventListener('close', restoreFocus);
$('clear-button').addEventListener('click', () => {
  if (filterCount() > 0) { app.filter = 'all'; app.companyId = null; app.overdueOnly = false; renderFiltered(); }
  else resetFilters();
});
$('refresh-button').addEventListener('click', () => { if (['error', 'loading'].includes(app.demoState)) app.demoState = 'normal'; render(); toast('Quadro atualizado · demonstração local.'); });
const filterHome = $('filter-panel').parentElement;
$('filter-button').addEventListener('click', () => {
  if (window.matchMedia('(max-width: 767px)').matches) {
    $('filters-content').appendChild($('filter-panel'));
    show($('filter-panel'), true);
    $('filter-button').setAttribute('aria-expanded', 'true');
    $('filters-drawer').showModal();
  } else {
    const open = $('filter-panel').classList.contains('hidden'); show($('filter-panel'), open); $('filter-button').setAttribute('aria-expanded', String(open));
  }
});
$('ai-filter-button').addEventListener('click', aiFilters);
$('filters-close').addEventListener('click', () => $('filters-drawer').close());
$('filters-results').addEventListener('click', () => $('filters-drawer').close());
$('filters-drawer').addEventListener('close', () => { closeMenus(); filterHome.appendChild($('filter-panel')); show($('filter-panel'), false); $('filter-button').setAttribute('aria-expanded', 'false'); $('filter-button').focus(); });
window.addEventListener('resize', () => { if ($('filters-drawer').open && window.matchMedia('(min-width: 768px)').matches) $('filters-drawer').close(); });
$('config-button').addEventListener('click', () => menu('config-menu', 'config-button'));
$('company-button').addEventListener('click', () => { menus(); menu('company-menu', 'company-button'); if (!$('company-menu').classList.contains('hidden')) $('company-search').focus(); });
$('overdue-button').addEventListener('click', () => { app.overdueOnly = !app.overdueOnly; renderFiltered(); });
$('pipeline-button').addEventListener('click', () => { menus(); menu('pipeline-menu', 'pipeline-button'); });
$('demo-button').addEventListener('click', () => openDrawer('Cenários do protótipo', 'Dados fictícios. Nenhuma alteração no produto.', `<p class="text-sm leading-6 text-slate-600">Esta ferramenta de revisão fica fora da interface proposta do produto.</p><div class="mt-5 space-y-2">${[['normal', 'Quadro normal · B2B, B2C, IA e humano'], ['b2c', 'Contatos sem empresa'], ['loading', 'Carregando'], ['empty', 'Nenhum resultado'], ['error', 'Falha de carregamento']].map(([key, label]) => `<button data-scenario="${key}" class="${secondary} w-full justify-start">${label}</button>`).join('')}</div>`));
document.addEventListener('keydown', event => {
  const activeDialog = $('drawer').open ? $('drawer') : $('filters-drawer').open ? $('filters-drawer') : null;
  if (activeDialog && event.key === 'Tab') {
    const controls = [...activeDialog.querySelectorAll('button:not(:disabled), input:not(:disabled), textarea:not(:disabled), summary, a[href]')].filter(el => el.getClientRects().length > 0);
    const first = controls[0];
    const last = controls[controls.length - 1];
    if (event.shiftKey && document.activeElement === first || !event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      (event.shiftKey ? last : first)?.focus();
    }
  }
  if (event.key === 'Escape') {
    const trigger = !$('config-menu').classList.contains('hidden') ? $('config-button') : !$('pipeline-menu').classList.contains('hidden') ? $('pipeline-button') : !$('company-menu').classList.contains('hidden') ? $('company-button') : null;
    closeMenus();
    if (trigger) { event.preventDefault(); trigger.focus(); }
  }
  if (event.target.id === 'company-search' && event.key === 'ArrowDown') { event.preventDefault(); $('company-options').querySelector('button')?.focus(); }
  const parentMenu = event.target.closest('[role="menu"], [role="listbox"]');
  if (parentMenu && ['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
    event.preventDefault(); const buttons = Array.from(parentMenu.querySelectorAll('button')); const index = buttons.indexOf(event.target);
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length;
    buttons[next].focus();
  }
});
document.addEventListener('click', event => { if (!event.target.closest('#config-button, #config-menu, #pipeline-button, #pipeline-menu, #company-button, #company-menu')) closeMenus(); });
$('board').addEventListener('dragstart', event => { const el = event.target.closest('[data-card]'); if (!el) return; app.dragged = Number(el.dataset.card); event.dataTransfer.setData('text/plain', el.dataset.card); event.dataTransfer.effectAllowed = 'move'; el.classList.add('opacity-50'); });
$('board').addEventListener('dragover', event => { const drop = event.target.closest('[data-drop]'); if (drop && app.dragged) { event.preventDefault(); event.dataTransfer.dropEffect = 'move'; drop.classList.add('ring-2', 'ring-inset', 'ring-blue-400'); } });
$('board').addEventListener('dragleave', event => { const drop = event.target.closest('[data-drop]'); if (drop && !drop.contains(event.relatedTarget)) drop.classList.remove('ring-2', 'ring-inset', 'ring-blue-400'); });
$('board').addEventListener('drop', event => { const drop = event.target.closest('[data-drop]'); if (drop && app.dragged) { event.preventDefault(); moveCard(app.dragged, drop.dataset.drop); app.dragged = null; } });
$('board').addEventListener('dragend', () => { app.dragged = null; document.querySelectorAll('[data-card]').forEach(el => el.classList.remove('opacity-50')); document.querySelectorAll('[data-drop]').forEach(el => el.classList.remove('ring-2', 'ring-inset', 'ring-blue-400')); });
$('sidebar-links').innerHTML = [['list', 'Primeiros passos'], ['inbox', 'Caixa de Entrada'], ['message', 'Conversas'], ['phone', 'Chamadas'], ['bot', 'Agentes'], ['users', 'Relacionamentos']].map(([glyph, label]) => `<button data-demo-nav="${label}" class="flex h-11 w-full items-center gap-3 rounded-lg px-3 text-start text-white/90 hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white">${icon(glyph)}${label}</button>`).join('');
menus(); render(); hydrate();
