// ---------- dados reais: conta Hub2you (16), produção, consulta só leitura em 05/10/2026 ----------
// Série diária de respostas/passagens (eventos replied / handoff) dos últimos 30 dias.
const SERIE_CLARA = { '2026-09-10': [2, 0], '2026-09-21': [7, 1], '2026-09-23': [1, 0], '2026-09-24': [3, 1], '2026-09-28': [4, 1], '2026-09-29': [10, 3] };
const SERIE_LIA = {
  '2026-09-08': [10, 0], '2026-09-09': [6, 0], '2026-09-10': [11, 0], '2026-09-11': [12, 0], '2026-09-12': [15, 0], '2026-09-13': [4, 0],
  '2026-09-14': [3, 0], '2026-09-18': [18, 0], '2026-09-19': [20, 2], '2026-09-20': [25, 4], '2026-09-21': [25, 5], '2026-09-22': [18, 0],
  '2026-09-23': [44, 14], '2026-09-24': [19, 2], '2026-09-25': [12, 0], '2026-09-26': [16, 1],
};
const HOJE = new Date('2026-10-05T12:00:00');

function serie(map, dias) {
  const out = [];
  for (let i = dias - 1; i >= 0; i -= 1) {
    const d = new Date(HOJE); d.setDate(d.getDate() - i);
    const k = d.toISOString().slice(0, 10);
    out.push({ date: k, r: (map[k] || [0, 0])[0], h: (map[k] || [0, 0])[1] });
  }
  return out;
}

const CHANNELS = [
  { id: 43, name: 'WhatsApp (11) 94454-7873', icon: 'message-circle', busyBy: 'clara' },
  { id: 57, name: 'WhatsApp (51) 99656-9128', icon: 'message-circle', busyBy: 'lia' },
  { id: 109, name: 'Chat do site hub2you', icon: 'globe', busyBy: null },
  { id: 3, name: 'E-mail Comercial', icon: 'mail', busyBy: null },
];

const PDF_CLARA = {
  id: 's1', kind: 'knowledge', name: 'hub2you_base_conhecimento_agente_vendas_v1.pdf', type: 'pdf', state: 'accepted',
  nota: 8, label: 'Boa', conf: 'alta', resumo: 'Base comercial da Hub2You: Chat2You, Protege, integrações e como cada solução ajuda a corretora.',
};

const AGENTS = [
  {
    id: 'clara', name: 'Clara', color: 'blue', type: 'custom', actuation: 'external', status: 'on', mode: 'guided',
    channels: [43],
    card: 'Atende corretores de seguros, tira dúvidas comerciais sobre a Hub2You e entende se a solução faz sentido para a corretora.',
    greeting: 'Oi, eu sou a Clara, da Hub2You. Posso te ajudar com uma dúvida sobre a plataforma ou entender se alguma solução faz sentido para a sua corretora.',
    fallback: 'Não tenho informação confiável o suficiente para responder esse ponto por aqui. Posso encaminhar para o time humano, que atende de segunda a sexta, das 09h às 18h.',
    tone: 'consultivo, claro e objetivo', handoff: 'low_confidence', threshold: 0.6, window: 'always', audience: null,
    starters: ['Sua dúvida hoje é sobre a Hub2You, o Chat2You, o Protege ou integrações?', 'Você quer só tirar uma dúvida específica ou entender se a solução faz sentido para a sua corretora?', 'Qual é o principal desafio da sua corretora nesse tema hoje?'],
    base: 71, faqOn: true, faq: [], versions: [], files: [PDF_CLARA], media: [],
    stats: {
      7: { conv: 3, replies: 14, handed: 4, conf: 97, know: 82, reasons: [['Pediu uma pessoa', 2], ['Outro motivo', 2]] },
      30: { conv: 6, replies: 27, handed: 6, conf: 98, know: 74, reasons: [['Pediu uma pessoa', 3], ['Outro motivo', 3]] },
    },
    serie: SERIE_CLARA, created: '06/07/2026',
  },
  {
    id: 'lia', name: 'Lia', color: 'teal', type: 'insurance_quote', actuation: 'external', status: 'on', mode: 'guided',
    channels: [57],
    card: 'Agente de Cotação. Identifica o ramo, coleta só os dados necessários e cota nas seguradoras da conta AGGER.',
    greeting: '', fallback: '', tone: '', handoff: 'low_confidence', threshold: 0.6, window: 'always', audience: null,
    starters: [], base: null, faqOn: false, faq: [], versions: [], files: [], media: [],
    ramos: ['Cotação de automóvel', 'Cotação empresarial', 'Cotação residencial'], behavior: 'consultivo',
    stats: {
      7: { conv: 0, replies: 0, handed: 0, conf: null, know: null, reasons: [] },
      30: { conv: 29, replies: 258, handed: 28, conf: 99, know: 98, reasons: [['Pediu uma pessoa', 22], ['Outro motivo', 6]] },
    },
    serie: SERIE_LIA, created: '08/09/2026',
  },
];

const MODELS = [
  { id: 'support', t: 'Tirar dúvidas', d: 'Responde perguntas comuns e resolve pedidos simples.', ex: 'Ex.: horário, preços, como funciona', icon: 'life-buoy', tone: 't-teal' },
  { id: 'sdr', t: 'Qualificar contatos', d: 'Conversa com quem chega, entende o interesse e passa os bons para a equipe.', ex: 'Ex.: quem pediu orçamento no site', icon: 'target', tone: 't-blue' },
  { id: 'reception', t: 'Receber e encaminhar', d: 'Dá boas-vindas, entende o assunto e manda para a pessoa certa.', ex: 'Ex.: vendas, financeiro, suporte', icon: 'concierge-bell', tone: 't-amber' },
  { id: 'onboarding', t: 'Acompanhar depois da venda', d: 'Ajuda o cliente novo nos primeiros passos e tira dúvidas de uso.', ex: 'Ex.: boas-vindas e primeiro acesso', icon: 'heart-handshake', tone: 't-ruby' },
  { id: 'scheduler', t: 'Marcar horários', d: 'Pergunta o melhor dia e horário e deixa tudo pronto para confirmar.', ex: 'Ex.: reunião, visita, demonstração', icon: 'calendar-clock', tone: 't-violet' },
  { id: 'reactivation', t: 'Trazer cliente de volta', d: 'Fala com quem sumiu e reabre a conversa com a equipe.', ex: 'Ex.: quem não responde há 30 dias', icon: 'refresh-cw', tone: 't-slate' },
];
const MODEL_TEAM = { id: 'internal', t: 'Ajudar minha equipe', d: 'Fica dentro das conversas e ajuda quem atende. Nunca fala com clientes.', icon: 'users', tone: 't-slate' };
const MODEL_FREE = { id: 'custom', t: 'Outro trabalho', d: 'Você descreve com suas palavras o que ele deve fazer.', icon: 'pencil', tone: 't-slate' };

// Roteiro de exemplo da etapa "Conte" (respostas com dados reais da Hub2You).
const SCRIPT = {
  sdr: [
    { ask: 'Vamos montar seu agente para qualificar contatos. Primeiro: o que sua empresa vende? Uma frase basta.', key: 'negocio', label: 'O que a empresa vende', ex: 'A Hub2You tem o Chat2You, plataforma de atendimento para corretoras de seguros. Site: hub2you.ai/chat2you' },
    { ask: 'Entendi. Quem vai conversar com ele?', key: 'publico', label: 'Com quem ele fala', ex: 'Donos e gestores de corretoras que chegam pelo site.' },
    { ask: 'Quando ele deve chamar alguém da equipe?', key: 'equipe', label: 'Quando chama a equipe', ex: 'Quando a pessoa pedir preço, demonstração ou quiser falar com um vendedor.' },
    { ask: 'Ótimo. Qual vai ser o nome dele? O cliente vê esse nome.', key: 'nome', label: 'Nome', ex: 'Bia' },
  ],
  internal: [
    { ask: 'Vamos montar um ajudante para a sua equipe. Ele aparece ao lado de cada conversa. No que ele mais deve ajudar?', key: 'negocio', label: 'No que ajuda', ex: 'Resumir a conversa e sugerir a próxima resposta para quem está atendendo.' },
    { ask: 'Quem vai usar?', key: 'publico', label: 'Quem usa', ex: 'O time comercial e o suporte da Hub2You.' },
    { ask: 'Tem algo que ele nunca deve sugerir?', key: 'equipe', label: 'O que ele evita', ex: 'Prometer prazo ou desconto sem falar com o gestor.' },
    { ask: 'Qual vai ser o nome dele? A equipe vê esse nome.', key: 'nome', label: 'Nome', ex: 'Apoio' },
  ],
};

const TEST_ANSWERS = {
  'O que vocês fazem?': { a: ['Oi! Que bom falar com você. O Chat2You é a plataforma de atendimento da Hub2You.', 'Junta WhatsApp, Instagram e o chat do site num lugar só, e tem agentes que respondem seus clientes.', 'Sua corretora atende hoje por WhatsApp?'], conf: 92, used: true },
  'Quanto custa?': { a: ['O valor depende do tamanho da sua corretora.', 'Vou chamar alguém do comercial para te passar os planos certinhos, tudo bem?'], conf: 88, flag: 'A pessoa pediu preço.', used: true },
  'Quero ver uma demonstração': { a: ['Ótimo! Vou chamar alguém da equipe para marcar com você. Qual o melhor dia?'], conf: 95, flag: 'A pessoa pediu uma demonstração.' },
  'Vocês atendem no sábado?': { a: ['Não tenho certeza sobre isso.', 'Vou passar para alguém da equipe confirmar com você.'], conf: 34, flag: 'Pouca certeza na resposta.' },
  // Ajudante da equipe: conversa de exemplo como contexto, sem passagem (D26)
  'Resuma esta conversa': { a: ['O cliente quer saber o preço do plano para 3 atendentes e pediu uma demonstração.', 'Ainda não disse o nome da corretora.'], conf: 90 },
  'Sugira uma resposta': { a: ['"Oi, Marcos! Posso marcar a demonstração para amanhã às 10h? Me diz o nome da sua corretora para eu já deixar pronto."'], conf: 86 },
  'O que falta perguntar?': { a: ['O nome da corretora e quantas pessoas atendem hoje.'], conf: 80 },
};
const TEAM_QUESTIONS = ['Resuma esta conversa', 'Sugira uma resposta', 'O que falta perguntar?'];
const CLIENT_QUESTIONS = ['O que vocês fazem?', 'Quanto custa?', 'Quero ver uma demonstração', 'Vocês atendem no sábado?'];
