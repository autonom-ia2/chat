// Os parâmetros da tela para onde o Guia leva a pessoa (#590): o id da caixa,
// da conversa, do agente — o que o modelo leu da conta.
//
// O id da conta nunca vem daqui. `accountScopedRoute` espalha estes parâmetros
// DEPOIS do id da conta aberta, então um `accountId` vindo da resposta trocaria
// a conta do botão. O servidor já o descarta; o painel não confia nisso.
const DA_SESSAO = 'accountId';
const TIPOS_ACEITOS = ['string', 'number'];

export const guideRouteParams = params =>
  Object.fromEntries(
    Object.entries(params || {}).filter(
      ([nome, valor]) =>
        nome !== DA_SESSAO && TIPOS_ACEITOS.includes(typeof valor)
    )
  );
