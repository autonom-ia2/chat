// Roteiro do vídeo de trajeto do artigo 10.05 — "Follow-up manual e
// automático". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json e em
// app/javascript/dashboard/routes/dashboard/crm/components/CrmCardDrawer.vue.
//
// 3ª versão deste roteiro. A 1ª tentou digitar a Data e horário
// (input[type="datetime-local"]) com "digitar" (Input.insertText) — o campo
// ficava vazio, então pivotei para o aviso de follow-up vencido (2ª
// versão, ainda gravável e válida). Agora o motor ganhou a ação
// "definirValor" (setter nativo do input, dispara input/change como o Vue
// espera), então volta a cobrir o trecho principal do artigo: criar o
// follow-up manual de verdade.

export const id = '10.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const TITULO_CARD = 'Seguro vida — Marcos Tavares';
const TITULOS_ANTIGOS = ['Card com follow-up vencido', 'Card para follow-up manual'];

// Cria um card avulso próprio deste vídeo, sempre em aberto e sem
// follow-up (o vídeo cria um de verdade na gravação), no funil Seguro Auto
// (funil já existente da conta — é o que o Kanban abre por padrão; não em
// Seguro Vida, mesmo o título citando seguro de vida, pra não depender do
// <select> nativo de funil). Idempotente: apaga o card anterior com esse
// título e os dos nomes antigos (versões anteriores deste vídeo).
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.crm_cards.where(title: [${JSON.stringify(TITULO_CARD)}, ${TITULOS_ANTIGOS.map(t => JSON.stringify(t)).join(', ')}]).destroy_all
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
    legenda: 'Criar um follow-up manual',
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
    legenda: 'Abra a aba Follow-ups',
    acao: 'mover e clicar',
    alvo: { texto: 'Follow-ups' },
    zoom: 1.8,
  },
  {
    legenda: 'Preencha Data e horário',
    acao: 'definirValor',
    alvo: { seletor: 'input[type="datetime-local"]' },
    valor: '2026-10-01T09:00',
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar follow-up',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar follow-up' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
