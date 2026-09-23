// Roteiro do vídeo de trajeto do artigo 10.10 — "Handoff da IA: conceito,
// gatilho, destino e por etapa". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json e em
// app/javascript/dashboard/routes/dashboard/settings/assignmentPolicy/pages/components/HandoffRuleFields.vue.
// Não dispara IA de verdade: só configura a regra de transferência e salva.
//
// Servidor :3001 (CRM_AI_ENABLED=true).
//
// Trajeto: barra lateral → CRM → Kanban (funil de teste) → Atribuição e
// handoff → Passar para um humano neste estágio → Quando transferir →
// Convite → Salvar.

export const id = '10.10';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3001';

const NOME_FUNIL = 'Funil Vídeo IA 10.10';

// Funil próprio deste vídeo. position: -3 (mais baixo que os outros vídeos
// de IA já gravados) garante que fica selecionado por padrão ao abrir o
// Kanban, mesmo com os funis de teste dos vídeos anteriores (10.07 pos=-1,
// 10.09 pos=-2) ainda na conta. Idempotente.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.crm_pipelines.where(name: ${JSON.stringify(NOME_FUNIL)}).find_each do |p|
  p.destroy if p.cards.count.zero?
end
pipeline = conta.crm_pipelines.create!(
  name: ${JSON.stringify(NOME_FUNIL)},
  description: "Funil de teste do vídeo 10.10",
  position: -3
)
pipeline.stages.create!(account: conta, name: "Novo", color: "#2563eb", position: 0)
pipeline.stages.create!(account: conta, name: "Fechamento", color: "#16a34a", position: 1)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Transferir a conversa para um humano',
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
  },
  {
    legenda: 'Clique em Atribuição e handoff',
    acao: 'mover e clicar',
    alvo: { texto: 'Atribuição e handoff' },
    zoom: 1.8,
  },
  {
    legenda: 'Ligue Passar para um humano',
    acao: 'mover e clicar',
    alvo: { texto: 'Passar para um humano neste estágio' },
    zoom: 1.6,
  },
  {
    legenda: 'Escreva quando transferir',
    acao: 'digitar',
    alvo: {
      seletor: 'textarea[placeholder*="IA deve atribuir a um atendente"]',
    },
    texto: ['Quando o cliente pedir para falar com uma pessoa.'],
    zoom: 1.6,
  },
  {
    legenda: 'Escolha Convite',
    acao: 'mover e clicar',
    alvo: { texto: 'Convite' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Salvar',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
