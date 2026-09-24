// Roteiro do vídeo de trajeto do artigo 16.01 — "Montar e rodar uma busca de
// leads". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/en/prospecting.json (a Central usa o
// arquivo "en" como locale pt-BR deste fork — ver CLAUDE.md do projeto) e em
// ProspectingSearchPage.vue.
//
// NUNCA roda a busca de verdade (chama Google Places, API paga). O vídeo
// monta o formulário inteiro e PARA antes de clicar em "Buscar" — não existe
// cena que clique nesse botão.
//
// A Prospecção só liga com `Autonomia::Prospecting::Config.enable_for!`
// (banco de dev) — nunca em produção, nunca fora do preparar.
//
// Sem chave do Google Places configurada (de propósito: configurar uma
// chave de verdade faria o campo Localização chamar a API do Google ao
// digitar), a Localização não mostra sugestão — o vídeo mostra esse estado
// real ("Configure a chave do Google Places para ativar sugestões."), o
// mesmo aviso que o próprio artigo documenta em "O que dá errado".
//
// ACHADO DE PRODUTO: "Área de busca" e "Forma de pesquisa" são `<select>`
// nativos (ProspectingSearchPage.vue) — proibido pela regra do Rodrigo
// (18/09/2026). Este vídeo usa a ação `selecionar` do motor no primeiro
// (Área de busca); "Forma de pesquisa" só aparece na tela, sem seleção, por
// não haver seletor CSS que distinga dois `<select>` sem texto vizinho
// exclusivo.
//
// Trajeto: barra lateral → Prospecção → Buscar leads → Nova busca → Termo →
// Localização → Área → raio/limite → Forma de pesquisa → Expandir raio
// automaticamente → parar antes de Buscar.

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
    texto: ['30'],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha a Forma de pesquisa',
    acao: 'parar',
    alvo: { texto: 'Forma de pesquisa', blocoRolagem: 'start' },
    zoom: 1.5,
    duracaoMs: 1400,
  },
  {
    legenda: 'Marque Expandir raio automaticamente',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[type="checkbox"]' },
    zoom: 1.8,
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
