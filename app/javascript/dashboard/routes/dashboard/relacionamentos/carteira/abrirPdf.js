// #2897 — "Ver PDF". O link que o servidor dá vale um minuto: é pedido no
// clique, aberto na hora e nunca guardado. A aba nasce em branco DENTRO do
// clique (depois da espera pelo link, o navegador a trataria como pop-up e
// bloquearia) e vai ao PDF quando o link chega. Aberta sem endereço, a aba é
// nossa: dá para tirar dela o caminho de volta a esta tela (`opener`) antes de
// ela receber o arquivo.
// `pedirLink` é a leitura da fonte (`fonte.pdf(id)`). Devolve a falha quando o
// link não veio (e fecha a aba em branco), ou `null` quando o PDF abriu.
export { openSignedFile as abrirPdf } from 'shared/helpers/openSignedFile';
