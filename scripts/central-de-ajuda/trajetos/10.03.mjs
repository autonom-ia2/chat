// Roteiro do vídeo de trajeto do artigo 10.03 — "Mover card, a gaveta e a
// timeline". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json e em
// app/javascript/dashboard/routes/dashboard/crm/pages/CrmKanbanPage.vue
// (Draggable/vuedraggable, onDragChange).
//
// Ficou pendente nas primeiras rodadas: arrastar um card é drag-and-drop
// (sortable.js), que a ação "mover e clicar" (clique simples) não simula.
// Motor ganhou a ação "arrastar" (pressiona, move em passos com o botão
// preso, solta) — agora dá pra gravar.
//
// Trajeto: barra lateral → CRM → Kanban → arraste o card de "Novo Lead"
// para "Cotação enviada" → abra a gaveta → aba Timeline.

export const id = '10.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const TITULO_CARD = 'Cotação urbana — Diego Aquino';

// Cria um card avulso próprio deste vídeo, sempre em "Novo Lead" (primeira
// etapa) do funil Seguro Auto (funil já existente — é o que o Kanban abre
// por padrão). Idempotente: apaga o card anterior com esse título antes de
// recriar, para sempre começar na mesma etapa.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.crm_cards.where(title: ${JSON.stringify(TITULO_CARD)}).destroy_all
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
    legenda: 'Mover um card entre etapas',
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
    // destino mira o aviso "Solte cards aqui..." (dentro da lista
    // arrastável de verdade), não o título da etapa: o título fica no
    // <header> da coluna, FORA do container do vuedraggable — soltar ali
    // não conta como "dentro" da lista de destino, e o card volta sozinho
    // (testado nesta gravação: 1ª tentativa mirou o título e o card não se
    // moveu). "Cotação enviada" é a 1ª etapa vazia na ordem do quadro, then
    // é a única com esse aviso visível nesse ponto do vídeo.
    legenda: 'Arraste o card para a próxima etapa',
    acao: 'arrastar',
    alvo: { texto: TITULO_CARD },
    destino: { texto: 'Solte cards aqui ou crie um novo card nesta etapa.' },
    zoom: 1.4,
    duracaoArrastoMs: 1000,
  },
  {
    legenda: 'O card mudou de etapa',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique no card para abrir a gaveta',
    acao: 'mover e clicar',
    alvo: { texto: TITULO_CARD },
    zoom: 1.8,
  },
  {
    legenda: 'Clique na aba Timeline',
    acao: 'mover e clicar',
    alvo: { texto: 'Timeline' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
