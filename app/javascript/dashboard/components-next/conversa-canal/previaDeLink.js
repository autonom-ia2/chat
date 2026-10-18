// Prévia de link (#1702): o servidor lê a página e grava em
// content_attributes.link_preview { url, title, description, siteName, imageUrl }.
// Aqui só se decide o que mostrar. A imagem é sempre a cópia no nosso servidor
// (caminho que começa com "/"): endereço de fora nunca vira <img>, para o site
// não saber quem leu nem quando.
const ESQUEMAS_WEB = ['https://', 'http://'];
const PREFIXO_WWW = 'www.';

const enderecoWeb = url =>
  typeof url === 'string' &&
  ESQUEMAS_WEB.some(esquema => url.toLowerCase().startsWith(esquema));

// Caminho do nosso servidor: começa com "/" e o segundo caractere não é "/" nem "\"
// (o navegador lê "/\host" como "//host", outro site).
const BARRAS = ['/', '\\'];
const imagemNossa = caminho =>
  typeof caminho === 'string' &&
  caminho.startsWith('/') &&
  !BARRAS.includes(caminho.charAt(1));

const dominioDe = url => {
  try {
    const { hostname } = new URL(url);
    return hostname.startsWith(PREFIXO_WWW)
      ? hostname.slice(PREFIXO_WWW.length)
      : hostname;
  } catch {
    return '';
  }
};

// null quando não há o que mostrar (sem prévia, sem título, endereço que não é web
// ou mensagem apagada).
export const previaDeLink = contentAttributes => {
  const previa = contentAttributes?.linkPreview;
  if (contentAttributes?.deleted || !previa?.title) return null;
  if (!enderecoWeb(previa.url)) return null;

  return {
    url: previa.url,
    titulo: previa.title,
    descricao: previa.description || '',
    dominio: dominioDe(previa.url),
    site: previa.siteName || dominioDe(previa.url),
    imagem: imagemNossa(previa.imageUrl) ? previa.imageUrl : '',
  };
};
