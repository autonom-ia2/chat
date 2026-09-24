// Roteiro do vídeo de trajeto do artigo 10.08 — "Aceitar a sugestão da IA e
// o lembrete de retorno". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json (CRM_KANBAN.AI_CARD,
// CRM_KANBAN.CALENDAR.CALLBACK) e em
// app/javascript/dashboard/routes/dashboard/crm/components/CrmCardAiPanel.vue.
//
// Regra do lote: a sugestão da IA nasce pelo `preparar` (um registro
// Crm::AiStageSuggestion pendente) — o vídeo NUNCA chama a IA de verdade
// (nem "Analisar agora" é clicado). Aceitar a sugestão só move o card pela
// própria API do produto, sem serviço externo.
//
// Trajeto: CRM Kanban → card com sugestão pendente → abrir → Aceitar →
// Calendário do CRM → alternar o atalho "Lembrete de retorno".

export const id = '10.08';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const PIPELINE_ID = 12; // Funil Comercial — meu
const STAGE_EM_ATENDIMENTO = 27;
const STAGE_PROPOSTA = 28;
const CARD_TITLE = 'Seguro residencial — Marcos Aurélio';

// Idempotente: apaga qualquer sugestão pendente antiga do mesmo card antes
// de criar uma nova — nunca mexe em outro card nem em outro funil.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
pipeline = conta.crm_pipelines.find(${PIPELINE_ID})
card = pipeline.cards.find_by(title: ${JSON.stringify(CARD_TITLE)})
raise "card #{${JSON.stringify(CARD_TITLE)}} não existe — rode o preparar de 10.06 antes" unless card

# Garante o card de volta no estágio de origem (Em atendimento), caso uma
# gravação anterior já tenha aceitado a sugestão e movido o card.
card.update!(stage_id: ${STAGE_EM_ATENDIMENTO})

Crm::AiStageSuggestion.where(card_id: card.id, status: :pending).destroy_all
Crm::AiStageSuggestion.create!(
  account: conta,
  card: card,
  from_stage_id: ${STAGE_EM_ATENDIMENTO},
  to_stage_id: ${STAGE_PROPOSTA},
  status: :pending,
  confidence: 0.82,
  model_used: "preparo-do-video",
  reasoning: "Cliente confirmou interesse e pediu orçamento por escrito."
)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Aceitar a sugestão da IA no card',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra CRM no menu lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'CRM' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Kanban',
    acao: 'mover e clicar',
    alvo: { texto: 'Kanban' },
    zoom: 1.8,
    aguardarTextoDepois: 'Novo card',
  },
  {
    // O Kanban lembra o último funil visitado por esta usuária — escolhe o
    // meu explicitamente, em vez de supor qual carrega sozinho.
    legenda: 'Escolha o Funil Comercial',
    acao: 'selecionar',
    alvo: { seletor: '.flex.flex-wrap.items-end.gap-3 > label:nth-of-type(1) select' },
    valor: 'Funil Comercial',
    zoom: 1.8,
    aguardarTextoDepois: 'Marcos Aurélio',
  },
  {
    legenda: 'Abra o card com sugestão',
    acao: 'mover e clicar',
    alvo: { texto: CARD_TITLE },
    zoom: 1.6,
    aguardarTextoDepois: 'Sugestão de estágio',
  },
  {
    legenda: 'Veja o selo de estágio sugerido',
    acao: 'parar',
    alvo: { texto: 'Analisar agora' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Aceitar',
    acao: 'mover e clicar',
    alvo: { texto: 'Aceitar' },
    zoom: 1.8,
  },
  {
    // Achado na 1ª gravação: o card fica aberto por cima de qualquer tela
    // (não é preso à rota do Kanban) — sem fechar aqui, ele continuava
    // aberto em cima do Calendário na cena seguinte, misturando as duas
    // telas no mesmo quadro.
    legenda: 'Feche o card',
    acao: 'mover e clicar',
    alvo: { texto: 'Cancelar' },
    zoom: 1.6,
  },
  {
    legenda: 'Abra o Calendário do CRM',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/crm/calendar`,
    aguardarTexto: 'Lembrete de retorno',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Ligue o Lembrete de retorno',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[role="switch"][aria-label="Lembrete de retorno"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
