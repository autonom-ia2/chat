// Roteiro do vídeo de trajeto do artigo 10.09 — "Follow-up automático da
// IA". Rótulos conferidos em app/javascript/dashboard/i18n/locale/pt_BR/crm.json
// e em app/javascript/dashboard/routes/dashboard/crm/components/CrmAiSettingsPanel.vue.
// Não dispara IA de verdade: só liga a automação e salva a configuração —
// nenhuma mensagem é enviada de fato (o funil de teste não tem card nem
// conversa vinculados).
//
// Servidor :3001 (mesmo banco do :3000, com CRM_AI_ENABLED=true — o :3000
// não tem essa env, por isso as telas de IA só existem aqui).
//
// Trajeto: barra lateral → CRM → Kanban (funil de teste) → Editar funil →
// Follow-up automático → Ativar → escolher modo → Número de follow-ups →
// Instruções para a IA → Salvar IA.

export const id = '10.09';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3001';

const NOME_FUNIL = 'Funil Vídeo IA 10.09';

// Funil próprio deste vídeo, criado direto no banco. position: -2 (mais
// baixo que o -1 do 10.07) o deixa selecionado por padrão ao abrir o Kanban
// — na 1ª tentativa usei -1 igual ao 10.07 e, no empate, o desempate por id
// escolheu o funil errado (editei o 10.07 por engano). Idempotente.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.crm_pipelines.where(name: ${JSON.stringify(NOME_FUNIL)}).find_each do |p|
  p.destroy if p.cards.count.zero?
end
pipeline = conta.crm_pipelines.create!(
  name: ${JSON.stringify(NOME_FUNIL)},
  description: "Funil de teste do vídeo 10.09",
  position: -2
)
pipeline.stages.create!(account: conta, name: "Novo", color: "#2563eb", position: 0)
pipeline.stages.create!(account: conta, name: "Fechamento", color: "#16a34a", position: 1)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ligar o follow-up automático da IA',
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
    legenda: 'Role até Follow-up automático',
    acao: 'parar',
    alvo: { texto: 'Follow-up automático', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1400,
  },
  {
    legenda: 'Ative o follow-up automático',
    acao: 'mover e clicar',
    alvo: { texto: 'Ativar follow-up automático neste funil' },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha IA cria lembrete para a equipe',
    acao: 'mover e clicar',
    alvo: { texto: 'IA cria lembrete para a equipe' },
    zoom: 1.6,
  },
  {
    legenda: 'Escreva o tom da marca',
    acao: 'digitar',
    alvo: {
      seletor: 'textarea[placeholder*="informal, trate por você"]',
    },
    texto: ['Tom informal, trate o cliente por você.'],
    zoom: 1.6,
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
