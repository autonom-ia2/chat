// Roteiro do vídeo de trajeto do artigo 09.02 — "Buscar e filtrar
// contatos, salvar segmento". Rótulos conferidos ao vivo no painel local
// (login Rafa Admin, conta 9) em 2026-09-23.
//
// Trajeto: Contatos → busca no cabeçalho → volta para Todos os Contatos →
// ícone de funil → valor do filtro → Aplicar filtros → ícone de salvar →
// nome do segmento → Salvar filtro.

export const id = '09.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_SEGMENTO = 'Clientes de auto';
// Este vídeo filtra pelo nome do contato "Carla Mendes", criado e mantido
// pelo vídeo 09.03 — não apaga nem edita esse contato, só o usa como
// exemplo de busca/filtro.
const VALOR_FILTRO = 'Carla Mendes';

// Roda antes de gravar: apaga o segmento de teste deste vídeo se uma
// gravação anterior o deixou para trás — idempotente, mexe só no segmento
// que este vídeo cria (CustomFilter é por usuária, não afeta outros
// agentes logados com outras usuárias).
export async function preparar({ rodarRails }) {
  await rodarRails(`
usuaria = Account.find(${login.contaId}).users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
usuaria.custom_filters.where(name: ${JSON.stringify(NOME_SEGMENTO)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Buscar e filtrar contatos',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 800,
  },
  {
    legenda: 'Abra Contatos',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Contacts"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Digite no campo Pesquisar',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar..."]' },
    texto: ['Pedro'],
    zoom: 1.8,
  },
  {
    legenda: 'A lista já filtra enquanto digita',
    acao: 'parar',
    alvo: { texto: 'Pesquisar contatos' },
    zoom: 1.6,
    duracaoMs: 700,
  },
  {
    legenda: 'Volte para Todos os Contatos',
    acao: 'mover e clicar',
    alvo: { texto: 'Todos os Contatos' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra Filtrar contatos',
    acao: 'mover e clicar',
    alvo: { seletor: '#toggleContactsFilterButton' },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha campo, operador e valor',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Inserir valor"]' },
    texto: [VALOR_FILTRO],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Aplicar filtros',
    acao: 'mover e clicar',
    alvo: { texto: 'Aplicar filtros' },
    zoom: 1.6,
  },
  {
    legenda: 'Veja o resultado filtrado',
    acao: 'parar',
    alvo: { seletor: 'main footer' },
    zoom: 1.6,
    duracaoMs: 800,
  },
  {
    legenda: 'Salve o filtro como segmento',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-save' },
    zoom: 1.8,
  },
  {
    legenda: 'Dê um nome para esse filtro',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Informe o nome para esse filtro"]' },
    texto: [NOME_SEGMENTO],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Salvar filtro',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar filtro' },
    zoom: 1.6,
    // O clique fecha o diálogo na hora — mesmo ajuste de pausas usado no
    // 09.03 para não passar dos 40s (ver nota lá).
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    // Confirma pelo nome do segmento, que fica visível na tela (cabeçalho
    // e barra lateral) em vez do toast, que esvanece antes da cena chegar.
    legenda: 'Segmento salvo',
    acao: 'parar',
    alvo: { texto: NOME_SEGMENTO },
    zoom: 1.4,
    duracaoMs: 1000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 800,
  },
];
