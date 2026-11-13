// #2897 — "Ver PDF". O link que o servidor dá vale um minuto: é pedido no
// clique, aberto na hora e nunca guardado. A aba nasce em branco DENTRO do
// clique (depois da espera pelo link, o navegador a trataria como pop-up e
// bloquearia) e vai ao PDF quando o link chega. Aberta sem endereço, a aba é
// nossa: dá para tirar dela o caminho de volta a esta tela (`opener`) antes de
// ela receber o arquivo.
// `pedirLink` é a leitura da fonte (`fonte.pdf(id)`). Devolve a falha quando o
// link não veio (e fecha a aba em branco), ou `null` quando o PDF abriu.
export const abrirPdf = async (pedirLink, janela = window) => {
  const aba = janela.open('', '_blank');
  if (aba) aba.opener = null;
  try {
    const link = await pedirLink();
    // Sem aba (o navegador bloqueou a nova): o PDF abre nesta, como um link. A
    // pessoa sai da tela, mas nunca fica sem ver o PDF que pediu.
    if (aba) aba.location.replace(link);
    else janela.location.assign(link);
    return null;
  } catch (falha) {
    aba?.close();
    return falha;
  }
};
