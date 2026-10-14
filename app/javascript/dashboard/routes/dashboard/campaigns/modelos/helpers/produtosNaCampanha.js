// Produtos do catálogo na campanha (#1418), lidos da estrutura do modelo da
// Meta (`modelo.template`), nunca do texto. Sem expressão regular.
//   um        → topo PRODUCT e botão SPM ("Ver"): 1 produto;
//   varios    → botão MPM ("Ver itens"): até 30 produtos numa lista; a foto da
//               mensagem é a do primeiro;
//   carrossel → cartões com topo PRODUCT: de 2 a 10 produtos, um por cartão
//               (o modelo aprovado com 2 cartões manda até 10).
// Limites da Meta, lidos em 14/10/2026: developers.facebook.com/documentation/
// business-messaging/whatsapp/catalogs/{spm,mpm,product-card-carousel}-template-messages
const maiusculo = valor => String(valor || '').toUpperCase();
const componente = (template, tipo) =>
  (template?.components || []).find(item => maiusculo(item?.type) === tipo);
const tiposDosBotoes = template =>
  (componente(template, 'BUTTONS')?.buttons || []).map(botao =>
    maiusculo(botao?.type)
  );

export const LIMITES_DE_PRODUTOS = {
  um: { minimo: 1, maximo: 1 },
  varios: { minimo: 1, maximo: 30 },
  carrossel: { minimo: 2, maximo: 10 },
};

const topoDeProduto = cartao =>
  (cartao?.components || []).some(
    item =>
      maiusculo(item?.type) === 'HEADER' &&
      maiusculo(item?.format) === 'PRODUCT'
  );

const tipoDeProdutos = template => {
  const tipos = tiposDosBotoes(template);
  if (tipos.includes('MPM')) return 'varios';
  if (tipos.includes('SPM')) return 'um';
  const cartoes = componente(template, 'CAROUSEL')?.cards || [];
  if (cartoes.length && cartoes.every(topoDeProduto)) return 'carrossel';
  return '';
};

// { tipo, minimo, maximo } quando o modelo leva produtos do catálogo; senão null.
export const pedidoDeProdutos = template => {
  const tipo = tipoDeProdutos(template);
  return tipo ? { tipo, ...LIMITES_DE_PRODUTOS[tipo] } : null;
};

export const levaProdutos = template => Boolean(tipoDeProdutos(template));

// Faltando produto, sobrando ou um que acabou depois de escolhido.
export const produtosPendentes = (pedido, escolhidos = []) => {
  if (!pedido) return false;
  const lista = escolhidos || [];
  return (
    lista.length < pedido.minimo ||
    lista.length > pedido.maximo ||
    lista.some(produto => !produto.disponivel)
  );
};

// O que vai no `processed_params` da campanha: os códigos dos produtos, na
// ordem escolhida. O servidor monta o resto (catálogo da conta do WhatsApp da
// caixa, seção do MPM, cartões do carrossel) e confere de novo no disparo.
// Os nomes vão junto só para a campanha dizer qual produto acabou, se parar.
export const produtosParaEnvio = escolhidos => {
  const lista = escolhidos || [];
  return {
    products: {
      retailer_ids: lista.map(produto => produto.id),
      names: Object.fromEntries(
        lista.map(produto => [produto.id, produto.nome])
      ),
    },
  };
};
