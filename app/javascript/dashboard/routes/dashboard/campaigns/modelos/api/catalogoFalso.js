// PROTÓTIPO #1418 — adaptador FALSO do catálogo de produtos do WhatsApp.
// Só para a jornada em tela real ser aprovada antes do backend. Trocar pelo
// endpoint é uma linha em modelosWhatsapp.js. As fotos moram só na demo
// (public/demo-1418/, fora do git).
//
// Contrato (o mesmo que o endpoint real vai devolver):
// obterCatalogo(caixa) → { nome, produtos: n } | null  (null = a conta do
//   WhatsApp da caixa não tem catálogo conectado)
// listarProdutos(caixa, { busca }) → [Produto]  (só os aprovados pelo WhatsApp;
//   o esgotado vem junto, para a pessoa entender por que não dá para escolher)
//   Produto = { id (o código do produto no catálogo, retailer_id), nome,
//               preco: { valor, moeda }, foto, disponivel }
const FOTOS = '/demo-1418';

const PRODUTOS = [
  ['camiseta-branca', 'Camiseta básica branca', 59.9, 'camiseta'],
  ['tenis-corrida-preto', 'Tênis de corrida preto', 299.9, 'tenis'],
  ['fone-sem-fio', 'Fone de ouvido sem fio', 249, 'fone-sem-fio'],
  ['relogio-branco', 'Relógio branco', 189, 'relogio'],
  ['mochila-azul', 'Mochila azul-marinho', 219.9, 'mochila'],
  ['oculos-de-sol', 'Óculos de sol preto', 159.9, 'oculos'],
  ['poncho-trico', 'Poncho de tricô', 129.9, 'poncho'],
  ['fone-com-fio', 'Fone de ouvido com fio', 99.9, 'fone-com-fio'],
  ['relogio-inteligente', 'Relógio inteligente', 899, 'relogio-inteligente'],
].map(([id, nome, valor, foto]) => ({
  id,
  nome,
  preco: { valor, moeda: 'BRL' },
  foto: `${FOTOS}/${foto}.jpg`,
  disponivel: id !== 'relogio-inteligente',
}));

// `?demo=sem-catalogo` mostra a conta sem catálogo conectado.
const semCatalogo = () =>
  typeof window !== 'undefined' &&
  new URLSearchParams(window.location.search).get('demo') === 'sem-catalogo';

// Busca sem acento e sem diferença de maiúscula (método de string, sem regex).
const ACENTOS_INICIO = 0x300;
const ACENTOS_FIM = 0x36f;
const simples = texto =>
  [...String(texto || '').normalize('NFD')]
    .filter(letra => {
      const codigo = letra.charCodeAt(0);
      return codigo < ACENTOS_INICIO || codigo > ACENTOS_FIM;
    })
    .join('')
    .toLowerCase()
    .trim();

const espera = () =>
  new Promise(resolve => {
    setTimeout(resolve, 250);
  });

const obterCatalogo = async () => {
  await espera();
  if (semCatalogo()) return null;
  return { nome: 'Loja Hub2you', produtos: PRODUTOS.length };
};

const listarProdutos = async (_caixa, { busca = '' } = {}) => {
  await espera();
  if (semCatalogo()) return [];
  const termo = simples(busca);
  return PRODUTOS.filter(produto => simples(produto.nome).includes(termo));
};

export default { obterCatalogo, listarProdutos };
