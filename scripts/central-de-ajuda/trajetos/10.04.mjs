// Roteiro do vídeo de trajeto do artigo 10.04 — "Ganhar, perder, reabrir e
// arquivar". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json e em
// app/javascript/dashboard/routes/dashboard/crm/components/CrmCardDrawer.vue.
//
// Trajeto: barra lateral → CRM → Kanban → abra um card → Ganhar → confirme o
// valor → Marcar como ganho. Os botões "Ganhar" e "Marcar como ganho" ficam
// no corpo do drawer/num diálogo central (não no rodapé fixo), fora da área
// da bolha "Guia da Plataforma" — não precisa do contorno por ícone usado no
// 10.01/10.02.

export const id = '10.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const TITULO_CARD = 'Renovação residencial — Paulo Reis';
const TITULO_ANTIGO = 'Card para marcar ganho';

// Cria (de novo, do zero) um card avulso próprio deste vídeo, sempre em
// aberto, na primeira etapa do funil "Seguro Auto" (funil já existente da
// conta — só ganha um card novo, nada nele é alterado; fica em Seguro Auto,
// não em Renovações, porque é o funil que a tela do Kanban abre por padrão
// — Renovações e Seguro Vida empatam em position com ele e perderiam o
// desempate por id). Idempotente: apaga qualquer card anterior com esse
// título (ganho, perdido ou aberto) e também o do nome antigo (1ª versão
// deste vídeo).
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.crm_cards.where(title: [${JSON.stringify(TITULO_CARD)}, ${JSON.stringify(TITULO_ANTIGO)}]).destroy_all
pipeline = conta.crm_pipelines.find_by!(name: "Seguro Auto")
stage = pipeline.stages.order(:position).first!
conta.crm_cards.create!(
  pipeline: pipeline,
  stage: stage,
  title: ${JSON.stringify(TITULO_CARD)},
  status: :open
)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ganhar, perder e arquivar um negócio',
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
    legenda: 'Clique no card',
    acao: 'mover e clicar',
    alvo: { texto: TITULO_CARD },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Ganhar',
    acao: 'mover e clicar',
    alvo: { texto: 'Ganhar' },
    zoom: 1.8,
  },
  {
    legenda: 'Confira o valor do negócio',
    acao: 'parar',
    alvo: { texto: 'Valor do negócio' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Marcar como ganho',
    acao: 'mover e clicar',
    alvo: { texto: 'Marcar como ganho' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
