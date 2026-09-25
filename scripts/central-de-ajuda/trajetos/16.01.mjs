// Roteiro do vídeo de trajeto do artigo 16.01 — "Montar e rodar uma busca de
// leads". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/en/prospecting.json (a Central usa o
// arquivo "en" como locale pt-BR deste fork — ver CLAUDE.md do projeto) e nos
// componentes de components/search/ (tela do #677: selo de modo, "Sua jogada",
// Tipo de decisor e gaveta de filtros com Aplicar).
//
// NUNCA roda a busca de verdade (chama Google Places, API paga). O vídeo
// monta o formulário inteiro e PARA antes de clicar em "Buscar" — não existe
// cena que clique nesse botão.
//
// A Prospecção só liga com `Autonomia::Prospecting::Config.enable_for!`
// (banco de dev) — nunca em produção, nunca fora do preparar.
//
// Sem chave do Google Places configurada (de propósito: uma chave de verdade
// faria o campo Localização chamar a API do Google ao digitar), a Localização
// não mostra sugestão — o vídeo mostra esse estado real, o mesmo aviso que o
// próprio artigo documenta em "O que dá errado".
//
// Trajeto (a ordem do "Como faz" do artigo): barra lateral → Prospecção →
// Buscar leads → Nova busca → selo de modo → Termo → Localização → Área →
// Forma de pesquisa → Sua jogada → raio/limite → Tipo de decisor → Expandir
// raio → Filtros avançados (gaveta, Telefone, Aplicar) → parar antes de Buscar.

export const id = '16.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
Autonomia::Prospecting::Config.enable_for!(conta)
# O vídeo mostra o uso do dia a dia: sem o balão de apresentação do Guia (#697).
usuario = conta.users.find_by!(name: '${login.usuarioNome}')
usuario.update!(ui_settings: (usuario.ui_settings || {}).merge('autonomia_guide_intro_seen' => true, 'autonomia_guide_opened' => true))
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Montar uma busca de leads',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Abra Prospecção na barra lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'Prospecção' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Buscar leads',
    acao: 'mover e clicar',
    alvo: { texto: 'Buscar leads' },
    aguardarTextoDepois: 'Nova busca',
    zoom: 2,
  },
  {
    legenda: 'Clique em Nova busca',
    acao: 'mover e clicar',
    alvo: { texto: 'Nova busca' },
    aguardarTextoDepois: 'Termo',
    zoom: 1.8,
  },
  {
    legenda: 'O selo no topo mostra o modo da busca',
    acao: 'passar o mouse',
    alvo: { seletor: '[data-test="search-mode-badge"]' },
    zoom: 1.8,
    duracaoMs: 2400,
  },
  {
    legenda: 'Preencha o Termo',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Segmento ou termo"]' },
    texto: ['clínica odontológica'],
    zoom: 1.8,
  },
  {
    legenda: 'Digite a Localização',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Cidade, bairro ou região"]' },
    texto: ['Porto Alegre, RS'],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha Raio ou Área visível',
    acao: 'selecionar',
    alvo: { seletor: '[role="combobox"][aria-label="Área de busca"]' },
    valor: 'viewport',
    zoom: 1.8,
  },
  {
    legenda: 'Área visível usa o mapa na hora de buscar',
    acao: 'parar',
    alvo: {
      texto:
        'Mova ou aplique zoom no mapa. A busca usará a área visível no momento de executar.',
    },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Volte para Raio',
    acao: 'selecionar',
    alvo: { seletor: '[role="combobox"][aria-label="Área de busca"]' },
    valor: 'radius',
    zoom: 1.8,
  },
  {
    legenda: 'Escolha a Forma de pesquisa',
    acao: 'selecionar',
    alvo: { seletor: '[role="combobox"][aria-label="Forma de pesquisa"]' },
    valor: 'gbp',
    zoom: 1.8,
  },
  {
    legenda: 'Em Sua jogada, escolha uma estratégia pronta',
    acao: 'mover e clicar',
    alvo: { texto: 'Vender site' },
    zoom: 1.6,
  },
  {
    legenda: 'A jogada preenche os filtros por você',
    acao: 'parar',
    alvo: { seletor: '[data-test="search-preset-grid"]' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Ajuste o raio',
    acao: 'digitar',
    alvo: { seletor: 'input[min="0.1"]' },
    limparAntes: true,
    texto: ['5'],
    zoom: 1.8,
  },
  {
    legenda: 'Defina o Limite de resultados',
    acao: 'digitar',
    alvo: { seletor: 'input[max="60"]' },
    limparAntes: true,
    texto: ['15'],
    zoom: 1.8,
  },
  {
    legenda: 'Tipo de decisor: fica Proprietário',
    acao: 'parar',
    alvo: { seletor: '[role="combobox"][aria-label="Tipo de decisor"]' },
    zoom: 1.8,
    duracaoMs: 1600,
  },
  {
    legenda: 'Marque Expandir raio automaticamente',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[type="checkbox"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Filtros avançados',
    acao: 'mover e clicar',
    alvo: { texto: 'Filtros avançados' },
    aguardarTextoDepois: 'Dor do lead',
    zoom: 1.8,
  },
  {
    legenda: 'O topo mostra a jogada base e o modo',
    acao: 'parar',
    alvo: { seletor: '[data-test="filters-base"]' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    legenda: 'Ajuste um filtro, como Telefone',
    acao: 'selecionar',
    alvo: { seletor: '[role="combobox"][aria-label="Telefone"]' },
    valor: 'yes',
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Aplicar para valer',
    acao: 'mover e clicar',
    alvo: { texto: 'Aplicar' },
    zoom: 1.6,
  },
  {
    legenda: 'Pare aqui antes de clicar em Buscar',
    acao: 'parar',
    alvo: { seletor: 'button[type="submit"]' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
