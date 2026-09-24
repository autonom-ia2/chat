// Roteiro do vídeo de trajeto do artigo 10.06 — "Filtrar o quadro e
// trabalhar na Visão Lista". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json (CRM_KANBAN.VIEWS,
// CRM_KANBAN.FILTERS, CRM_KANBAN.LIST.COLUMN_SETTINGS/SAVED_VIEWS) e em
// app/javascript/dashboard/routes/dashboard/crm/pages/CrmKanbanPage.vue.
//
// Trajeto: CRM → Kanban (funil "Funil Comercial", meu, criado no P1) →
// Busca + Enter → Filtros → Prioridade → Aplicar → Lista → Colunas.
// Não toca em Seguro Auto/Vida/Renovações — só no meu próprio funil.
//
// O select de Prioridade dentro do painel Filtros é um <select> nativo do
// produto (não criado por nós) — usa a ação "selecionar", como manda a
// regra "sem <select> nativo" quando o achado já existe no código.
// Achado de produto: registrado na resposta final, não corrigido aqui.

export const id = '10.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const PIPELINE_ID = 12; // Funil Comercial — meu, criado no vídeo 10.01 (P1)
const STAGE_NOVO = 26;
const STAGE_EM_ATENDIMENTO = 27;
const STAGE_PROPOSTA = 28;
const STAGE_FECHAMENTO = 29;

// Cards fictícios de demonstração para filtrar/listar — só no meu funil.
// Idempotente: apaga os títulos antigos (por nome exato) antes de recriar,
// nunca mexe em card de outro funil.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
pipeline = conta.crm_pipelines.find(${PIPELINE_ID})
raise "pipeline errado (não é Funil Comercial)" unless pipeline.name == "Funil Comercial"

titulos = [
  "Seguro auto — Fernanda Lima",
  "Seguro residencial — Marcos Aurélio",
  "Seguro vida — Patrícia Nogueira",
  "Seguro auto — Eduardo Castro",
  "Seguro frota — Transportes Vale Ltda",
]
pipeline.cards.where(title: titulos).destroy_all

nina = conta.users.find_by(name: "Nina Admin")
bia = conta.users.find_by(name: "Bia Vendas")
caio = conta.users.find_by(name: "Caio Sinistro")

def novo_card(pipeline, conta, titulo, stage_id, priority, owner)
  pipeline.cards.create!(
    account: conta,
    title: titulo,
    stage_id: stage_id,
    priority: priority,
    owner: owner,
    value_cents: rand(2_000..15_000) * 100
  )
end

novo_card(pipeline, conta, "Seguro auto — Fernanda Lima", ${STAGE_NOVO}, "urgent", nina)
novo_card(pipeline, conta, "Seguro residencial — Marcos Aurélio", ${STAGE_EM_ATENDIMENTO}, "high", bia)
novo_card(pipeline, conta, "Seguro vida — Patrícia Nogueira", ${STAGE_PROPOSTA}, "medium", nil)
novo_card(pipeline, conta, "Seguro auto — Eduardo Castro", ${STAGE_FECHAMENTO}, "low", nina)
novo_card(pipeline, conta, "Seguro frota — Transportes Vale Ltda", ${STAGE_NOVO}, "medium", caio)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Filtrar o quadro e usar a Visão Lista',
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
    // O Kanban lembra o último funil visitado por esta usuária (não é
    // sempre o funil padrão) — escolhe o meu explicitamente antes de
    // seguir, em vez de supor qual carrega sozinho.
    legenda: 'Escolha o Funil Comercial',
    acao: 'selecionar',
    alvo: { seletor: '.flex.flex-wrap.items-end.gap-3 > label:nth-of-type(1) select' },
    valor: 'Funil Comercial',
    zoom: 1.8,
    aguardarTextoDepois: 'Fernanda Lima',
  },
  {
    legenda: 'Digite no campo Busca',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[placeholder="Buscar card"]' },
    zoom: 1.8,
  },
  {
    // Segunda linha vazia dispara o Enter que aplica a busca (ver
    // digitarLinhas em lib/pagina.mjs — pressiona Enter entre linhas).
    legenda: 'Pressione Enter para aplicar',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Buscar card"]' },
    texto: ['Seguro auto', ''],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Filtros',
    acao: 'mover e clicar',
    alvo: { texto: 'Filtros' },
    zoom: 1.6,
  },
  {
    legenda: 'Escolha a Prioridade',
    acao: 'selecionar',
    alvo: { seletor: '.flex.w-80.flex-col.gap-3.p-4 > label:nth-of-type(3) select' },
    valor: 'urgent',
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Aplicar',
    acao: 'mover e clicar',
    alvo: { texto: 'Aplicar' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Lista',
    acao: 'mover e clicar',
    alvo: { texto: 'Lista' },
    zoom: 1.8,
    aguardarTextoDepois: 'Card',
  },
  {
    legenda: 'Clique em Colunas',
    acao: 'mover e clicar',
    alvo: { texto: 'Colunas' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
