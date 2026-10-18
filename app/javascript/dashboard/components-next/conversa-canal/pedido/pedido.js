// Pedido do catálogo (#1702): o cliente monta o carrinho no WhatsApp e manda tudo numa
// mensagem só. O servidor guarda em content_attributes.order:
// { catalogId, items: [{ productRetailerId, quantity, itemPrice, currency }], text }
// (webhook `order` da Cloud API). Aqui só se soma o que veio, para o cartão.
// O WhatsApp pelo WAHA (#1709) não traz os itens: `items` vem vazio e o resumo chega
// pronto em { orderId, itemCount, totalAmount ("150.00", texto), currency, title }.

const numero = valor => {
  const convertido = Number(valor);
  return Number.isFinite(convertido) ? convertido : 0;
};

export const itensDoPedido = pedido =>
  (Array.isArray(pedido?.items) ? pedido.items : [])
    .filter(item => item && item.productRetailerId)
    .map(item => ({
      codigo: String(item.productRetailerId),
      quantidade: Math.max(0, numero(item.quantity)),
      preco: numero(item.itemPrice),
      moeda: item.currency || '',
    }));

// Pedido sem itens (WAHA): o resumo que o celular do cliente mandou. Total que não é
// número fica de fora, em vez de virar zero.
const resumoSemItens = pedido => {
  // Number e não parseFloat: "150,00" ou "R$ 150" não viram 150 por engano.
  const texto = String(pedido?.totalAmount ?? '').trim();
  const total = texto ? Number(texto) : Number.NaN;
  const temTotal = Number.isFinite(total) && Boolean(pedido?.currency);
  return {
    itens: [],
    unidades: Math.max(0, Math.trunc(numero(pedido?.itemCount))),
    total: temTotal ? total : null,
    moeda: temTotal ? String(pedido.currency) : '',
  };
};

// Quantidade de unidades, total e moeda. Com moedas misturadas (não deveria acontecer
// num catálogo), o total não é mostrado.
export const resumoDoPedido = pedido => {
  const itens = itensDoPedido(pedido);
  if (!itens.length) return resumoSemItens(pedido);
  const moedas = [...new Set(itens.map(item => item.moeda).filter(Boolean))];
  const unidades = itens.reduce((soma, item) => soma + item.quantidade, 0);
  const total = itens.reduce(
    (soma, item) => soma + item.quantidade * item.preco,
    0
  );
  return {
    itens,
    unidades,
    total: moedas.length === 1 ? total : null,
    moeda: moedas.length === 1 ? moedas[0] : '',
  };
};

// Com itens (Cloud) ou só com o resumo (WAHA, que sempre manda o orderId).
export const ehPedido = atributos =>
  itensDoPedido(atributos?.order).length > 0 ||
  Boolean(atributos?.order?.orderId);

export const valorEmDinheiro = (valor, moeda, idioma) => {
  if (!moeda) return String(valor);
  try {
    return new Intl.NumberFormat(idioma, {
      style: 'currency',
      currency: moeda,
    }).format(valor);
  } catch (erro) {
    // Código de moeda que o navegador não conhece: o número e o código, sem formatar.
    return `${moeda} ${valor}`;
  }
};
