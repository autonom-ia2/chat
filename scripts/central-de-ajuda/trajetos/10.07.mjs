// Roteiro do vídeo de trajeto do artigo 10.07 — "IA do funil: ligar,
// critérios e extração de campos". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json e em
// app/javascript/dashboard/routes/dashboard/crm/components/CrmAiSettingsPanel.vue.
// Não dispara IA de verdade: só liga interruptores e salva configuração.
//
// Trajeto: barra lateral → CRM → Kanban (funil de teste) → Editar funil →
// IA habilitada → Mover automaticamente → critério da etapa → Salvar IA.

export const id = '10.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

// Segundo servidor, só para os vídeos de IA do CRM: mesmo banco, mesmo
// Vite, CRM_AI_ENABLED=true (o :3000 continua sem essa env, para as outras
// frentes).
export const baseUrl = 'http://localhost:3001';

const NOME_FUNIL = 'Funil Vídeo IA 10.07';

// Funil próprio deste vídeo, criado direto no banco (não pela tela — a
// criação em si já é o vídeo 10.01). position: -1 o deixa em primeiro na
// ordenação (position, id) da tela de Kanban, então já vem selecionado ao
// abrir, sem precisar operar o <select> nativo de funil. Idempotente: apaga
// o funil anterior com esse nome (só se não tiver card) antes de recriar.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.crm_pipelines.where(name: ${JSON.stringify(NOME_FUNIL)}).find_each do |p|
  p.destroy if p.cards.count.zero?
end
pipeline = conta.crm_pipelines.create!(
  name: ${JSON.stringify(NOME_FUNIL)},
  description: "Funil de teste do vídeo 10.07",
  position: -1
)
pipeline.stages.create!(account: conta, name: "Qualificação", color: "#2563eb", position: 0)
pipeline.stages.create!(account: conta, name: "Fechamento", color: "#16a34a", position: 1)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ligar a IA no funil',
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
    legenda: 'Clique em Editar funil',
    acao: 'mover e clicar',
    alvo: { texto: 'Editar funil' },
    zoom: 1.8,
  },
  {
    // Não clica: "IA habilitada neste funil" já nasce marcada por padrão
    // (form.enabled = payload.enabled !== false, em CrmAiSettingsPanel.vue)
    // — cliquei nela na primeira gravação achando que precisava ligar, e o
    // resultado salvo veio com enabled:false (desliguei sem querer). Só
    // mostra o estado já ligado.
    legenda: 'A IA já vem habilitada',
    acao: 'parar',
    alvo: { texto: 'IA habilitada neste funil' },
    zoom: 1.8,
    duracaoMs: 1400,
  },
  {
    legenda: 'Marque Mover automaticamente',
    acao: 'mover e clicar',
    alvo: { texto: 'Mover automaticamente' },
    zoom: 1.8,
  },
  {
    legenda: 'Escreva o critério da etapa',
    acao: 'digitar',
    alvo: {
      seletor:
        'textarea[placeholder="Descreva quando um card deve estar neste estágio"]',
    },
    texto: ['Cliente confirmou interesse e pediu cotação.'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Salvar IA',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar IA' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
