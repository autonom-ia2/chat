// O HTML que o remetente mandou, como ele desenhou (#1884). Vai inteiro para uma
// moldura isolada (CorpoIsoladoDoEmail.vue): os <style> do <head>, o @media de celular,
// o fundo e o estilo do <body> e o !important continuam valendo. O CSS do painel não
// entra no e-mail, e o do e-mail não sai dele.
// Segurança em camadas: o lettersanitizer limpa tags, atributos e CSS; os links ficam
// só web, e-mail e telefone; a moldura não tem allow-scripts e o documento traz uma CSP
// que bloqueia script, formulário, moldura, objeto e conexão. Lê a estrutura (DOM), sem
// regex.
import { allowedCssProperties, sanitize } from 'lettersanitizer';
import {
  EmailQuoteExtractor,
  QUOTE_INDICATORS,
} from 'dashboard/helper/emailQuoteExtractor.js';
import { cortarCitacaoDosLeitores } from './citacaoDosLeitores';
import { prepararEstilos, semMarcacaoPerigosa } from './estiloSeguroDoEmail';

// Nunca allow-scripts: com allow-same-origin junto, o e-mail sairia da moldura.
export const SANDBOX_DO_EMAIL =
  'allow-same-origin allow-popups allow-popups-to-escape-sandbox';

export const CSS_PERMITIDO = [
  ...allowedCssProperties,
  'transform',
  'transform-origin',
];

const CSP = [
  "default-src 'none'",
  'img-src http: https: data: blob:',
  "style-src 'unsafe-inline'",
  'font-src http: https: data:',
  "script-src 'none'",
  "object-src 'none'",
  "frame-src 'none'",
  "child-src 'none'",
  "form-action 'none'",
  "connect-src 'none'",
  "media-src 'none'",
  "base-uri 'none'",
].join('; ');

const PROTOCOLOS_DE_LINK = ['http:', 'https:', 'mailto:', 'tel:'];
const PROTOCOLOS_DE_IMAGEM = ['http:', 'https:'];
const IMAGEM_EMBUTIDA = 'data:image/';

// O padrão de um leitor de e-mail para o que o remetente não definiu (como o Gmail):
// sem a margem do navegador, letra sem serifa. Vem antes do CSS do remetente, que ganha.
const PADRAO_DO_LEITOR = [
  ':root{color-scheme:light}',
  'body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;font-size:14px;color:#1f1f1f}',
  'img{max-width:100%}',
  'img:not(a img){cursor:zoom-in}',
  'a:focus-visible{outline:2px solid #2563eb;outline-offset:2px;border-radius:2px}',
].join('\n');

// Vem depois do CSS do remetente: a altura sai do conteúdo (a moldura cresce com ele),
// sem rolagem de cima para baixo. Largo demais, rola de lado, como hoje.
export const MARCA_DA_MOLDURA = 'data-moldura-do-email';
const DA_MOLDURA = [
  'html{height:auto!important;min-height:0!important;max-height:none!important;overflow-y:hidden!important;overflow-x:auto!important}',
].join('\n');

const lerDocumento = html =>
  new DOMParser().parseFromString(String(html || ''), 'text/html');

const comoTexto = doc => `<!doctype html>${doc.documentElement.outerHTML}`;

// O extrator do Chatwoot (classes de citação, blockquote no fim, "On ... wrote:"),
// aplicado no body do documento. Devolve se tirou alguma coisa.
const cortarCitacaoDoChatwoot = raiz => {
  let achou = false;
  QUOTE_INDICATORS.forEach(seletor => {
    raiz.querySelectorAll(seletor).forEach(elemento => {
      achou = true;
      elemento.remove();
    });
  });
  const blocoNoFim = EmailQuoteExtractor.findTrailingBlockquote(raiz);
  if (blocoNoFim) {
    achou = true;
    blocoNoFim.remove();
  }
  EmailQuoteExtractor.findTextNodeQuotes(raiz).forEach(bloco => {
    achou = true;
    bloco.remove();
  });
  return achou;
};

// O documento inteiro sem a citação, e se havia. `leitores: false` usa só o extrator do
// Chatwoot (o balão antigo), para não mudar o que ele considera citação.
export const citacaoDoDocumento = (html, { leitores = true } = {}) => {
  const doc = lerDocumento(html);
  const achouDosLeitores = leitores
    ? cortarCitacaoDosLeitores(doc.body)
    : false;
  const achouDoChatwoot = cortarCitacaoDoChatwoot(doc.body);
  return {
    html: comoTexto(doc),
    achou: achouDosLeitores || achouDoChatwoot,
  };
};

// Só endereço completo: relativo resolveria contra o painel (pedido com a sessão do atendente).
const enderecoCom = protocolos => endereco => {
  try {
    const url = new URL(String(endereco || '').trim());
    return protocolos.includes(url.protocol) ? url.href : '';
  } catch {
    return '';
  }
};
const linkSeguro = enderecoCom(PROTOCOLOS_DE_LINK);
const imagemWeb = enderecoCom(PROTOCOLOS_DE_IMAGEM);

const imagemSegura = endereco => {
  const texto = String(endereco || '').trim();
  if (texto.toLowerCase().startsWith(IMAGEM_EMBUTIDA)) return texto;
  return imagemWeb(texto);
};

// O estilo e a direção do <body> vão para uma div por cima de tudo, que o sanitizador
// limpa como qualquer outro elemento; depois voltam ao <body> da moldura.
const envolverOCorpo = doc => {
  const corpo = doc.body;
  const envoltorio = doc.createElement('div');
  envoltorio.setAttribute('style', corpo.getAttribute('style') || '');
  const direcao =
    corpo.getAttribute('dir') || doc.documentElement.getAttribute('dir');
  if (direcao) envoltorio.setAttribute('dir', direcao);
  envoltorio.append(...corpo.childNodes);
  corpo.append(envoltorio);
};

// As cores antigas do <body> (bgcolor, text, link…) ficam como atributo, com a mesma
// prioridade baixa de sempre: o CSS do remetente continua ganhando delas.
const CORES_DO_CORPO = ['bgcolor', 'text', 'link', 'vlink', 'alink'];
const atributosDoCorpo = (doc, semRastreio) => {
  const corpo = doc.body;
  const atributos = CORES_DO_CORPO.map(nome => [
    nome,
    String(corpo.getAttribute(nome) || '').trim(),
  ]).filter(([, valor]) => valor);
  const imagem = corpo.getAttribute('background');
  const fundo = imagem && imagemSegura(semRastreio(imagem));
  return fundo ? [...atributos, ['background', fundo]] : atributos;
};

const limparLinksEImagens = doc => {
  doc.querySelectorAll('a').forEach(link => {
    const endereco = linkSeguro(link.getAttribute('href') || '');
    if (endereco) link.setAttribute('href', endereco);
    else link.removeAttribute('href');
    link.setAttribute('target', '_blank');
    link.setAttribute('rel', 'noopener noreferrer');
  });
  doc.querySelectorAll('img').forEach(imagem => {
    const endereco = imagemSegura(imagem.getAttribute('src'));
    if (endereco) imagem.setAttribute('src', endereco);
    else imagem.removeAttribute('src');
  });
};

// A div do envoltório devolve ao <body> o que era dele.
const devolverAoCorpo = (doc, atributos) => {
  const corpo = doc.body;
  atributos.forEach(([nome, valor]) => corpo.setAttribute(nome, valor));
  const envoltorio = corpo.firstElementChild;
  if (!envoltorio || envoltorio.tagName !== 'DIV') return;
  const estilo = envoltorio.getAttribute('style');
  if (estilo) corpo.setAttribute('style', estilo);
  const direcao = envoltorio.getAttribute('dir');
  if (direcao) corpo.setAttribute('dir', direcao);
  envoltorio.replaceWith(...envoltorio.childNodes);
};

const elemento = (doc, nome, atributos = {}, texto = '') => {
  const no = doc.createElement(nome);
  Object.entries(atributos).forEach(([chave, valor]) =>
    no.setAttribute(chave, valor)
  );
  if (texto) no.textContent = texto;
  return no;
};

const montarCabeca = doc => {
  doc.head.replaceChildren(
    elemento(doc, 'meta', { charset: 'utf-8' }),
    elemento(doc, 'meta', {
      'http-equiv': 'Content-Security-Policy',
      content: CSP,
    }),
    elemento(doc, 'meta', { name: 'color-scheme', content: 'light' }),
    elemento(doc, 'base', { target: '_blank' }),
    elemento(doc, 'style', {}, PADRAO_DO_LEITOR)
  );
};

const semMudar = endereco => endereco;

// O documento que vai no srcdoc da moldura. `semRastreio` troca endereço de imagem e
// de link (o mesmo de hoje: tira o pixel e o clique rastreado das Campanhas).
export const documentoIsolado = (html, { semRastreio = semMudar } = {}) => {
  const original = lerDocumento(html);
  const atributos = atributosDoCorpo(original, semRastreio);
  envolverOCorpo(original);
  prepararEstilos(original);
  const limpo = sanitize(comoTexto(original), '', {
    noWrapper: true,
    preserveCssPriority: true,
    allowedCssProperties: CSS_PERMITIDO,
    rewriteExternalLinks: semRastreio,
    rewriteExternalResources: semRastreio,
  });
  const doc = lerDocumento(`<!doctype html><html><body>${limpo}</body></html>`);
  devolverAoCorpo(doc, atributos);
  semMarcacaoPerigosa(doc.body);
  limparLinksEImagens(doc);
  montarCabeca(doc);
  doc.body.append(
    elemento(doc, 'style', { [MARCA_DA_MOLDURA]: '' }, DA_MOLDURA)
  );
  return comoTexto(doc);
};

// Para Imprimir: o corpo já limpo, com o estilo do <body> numa div, sem o CSS da moldura.
export const corpoParaImprimir = srcdoc => {
  const doc = lerDocumento(srcdoc);
  doc.querySelectorAll(`[${MARCA_DA_MOLDURA}]`).forEach(no => no.remove());
  const div = doc.createElement('div');
  const estilo = doc.body.getAttribute('style');
  if (estilo) div.setAttribute('style', estilo);
  const fundo = doc.body.getAttribute('bgcolor');
  if (fundo && !div.style.backgroundColor) div.style.backgroundColor = fundo;
  div.append(...doc.body.childNodes);
  return div.outerHTML;
};
