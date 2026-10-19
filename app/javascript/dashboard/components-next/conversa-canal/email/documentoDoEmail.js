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
import { imagemSegura, linkSeguro } from './enderecoDoEmail';

// Nunca allow-scripts: com allow-same-origin junto, o e-mail sairia da moldura.
export const SANDBOX_DO_EMAIL =
  'allow-same-origin allow-popups allow-popups-to-escape-sandbox';

export const CSS_PERMITIDO = [
  ...allowedCssProperties,
  'transform',
  'transform-origin',
];

// Só na moldura (recortada, isolada do painel): comuns em e-mail de hoje e mantidos pelo
// Gmail. No Letter, que fica no documento do painel, uma sombra poderia pintar fora.
const CSS_DA_MOLDURA = [
  ...CSS_PERMITIDO,
  'justify-content',
  'align-items',
  'gap',
  'box-shadow',
  'text-shadow',
  'visibility',
];

export const CSP_DO_EMAIL = [
  "default-src 'none'",
  'img-src http: https: data: blob:',
  "style-src 'unsafe-inline'",
  'font-src data:',
  "script-src 'none'",
  "object-src 'none'",
  "frame-src 'none'",
  "child-src 'none'",
  "form-action 'none'",
  "connect-src 'none'",
  "media-src 'none'",
  "base-uri 'none'",
].join('; ');

export const MARCA_DA_PROPORCAO = 'data-proporcao';

// O padrão de um leitor de e-mail para o que o remetente não definiu (como o Gmail):
// sem a margem do navegador, letra sem serifa. Vem antes do CSS do remetente, que ganha.
const PADRAO_DO_LEITOR = [
  ':root{color-scheme:light}',
  'body{margin:0;font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#222}',
  ':where(a){color:#15c}',
  'img{max-width:100%}',
  // Imagem estreitada mantém a proporção dos atributos (manterProporcao); peso zero: o
  // remetente ganha.
  `:where(img[${MARCA_DA_PROPORCAO}]){height:auto}`,
  'img:not(a img){cursor:zoom-in}',
  'a:focus-visible{outline:2px solid #2563eb;outline-offset:2px;border-radius:2px}',
].join('\n');

// No atributo style do <html>: com !important, nenhuma regra do remetente ganha dele
// (nem `:root:root{height:…!important}`). A altura sai do conteúdo (a moldura cresce
// com ele), sem rolagem de cima para baixo. Largo demais, rola de lado, como hoje.
const DA_MOLDURA =
  'height:auto!important;min-height:0!important;max-height:none!important;overflow-y:hidden!important;overflow-x:auto!important';

// Na impressão o CSS do remetente volta a ter escopo (como no balão antigo): não alcança
// o cabeçalho da impressão (Assunto, De, Para) nem a página.
const ESCOPO_DA_IMPRESSAO = 'email_impresso';

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

// Imagem estreitada (max-width) fica com a proporção que o remetente desenhou nos
// atributos (espaçador 1×20 continua 1×20), não com a do arquivo. O CSS do remetente
// que fixa a altura continua ganhando.
const PROPORCAO = 'aspect-ratio';
const tamanho = valor => {
  const numero = Number(String(valor || '').trim());
  return Number.isFinite(numero) && numero > 0 ? numero : 0;
};
// Só com os dois atributos em número (`width="100%"` fica com a altura do atributo).
const manterProporcao = imagem => {
  const largura = tamanho(imagem.getAttribute('width'));
  const alturaDaImagem = tamanho(imagem.getAttribute('height'));
  const estilo = imagem.getAttribute('style') || '';
  if (!largura || !alturaDaImagem || estilo.includes(PROPORCAO)) return;
  const antes = estilo.trim() ? `${estilo.trim()};` : '';
  imagem.setAttribute(
    'style',
    `${antes}${PROPORCAO}:${largura} / ${alturaDaImagem}`
  );
  imagem.setAttribute(MARCA_DA_PROPORCAO, '');
};

// Atributos antigos de tabela que o sanitizador descarta viram o estilo equivalente,
// como o Gmail mostra: fundo de célula, altura de tabela e de linha, nowrap. O endereço
// do fundo passa pela mesma limpeza de url() do CSS.
const medida = valor => {
  const texto = String(valor || '').trim();
  return tamanho(texto) ? `${texto}px` : texto;
};
const ATRIBUTOS_DE_TABELA = [
  [
    'table[background], td[background], th[background]',
    'background-image',
    elemento => `url("${elemento.getAttribute('background')}")`,
  ],
  [
    'table[height], tr[height]',
    'height',
    elemento => medida(elemento.getAttribute('height')),
  ],
  ['td[nowrap], th[nowrap]', 'white-space', () => 'nowrap'],
];
const atributosDeTabelaComoEstilo = doc => {
  ATRIBUTOS_DE_TABELA.forEach(([seletor, propriedade, valor]) => {
    doc.body.querySelectorAll(seletor).forEach(elemento => {
      if (elemento.style.getPropertyValue(propriedade)) return;
      elemento.style.setProperty(propriedade, valor(elemento));
    });
  });
};

// O srcdoc herda o endereço do painel: endereço relativo (no <img> ou no url() do CSS)
// viraria pedido ao painel com a sessão do atendente.
export const imagemSemRastreio = semRastreio => endereco =>
  imagemSegura(semRastreio(endereco));
// Link só web, e-mail e telefone (nunca javascript:), também no Letter.
export const linkSemRastreio = semRastreio => endereco =>
  linkSeguro(semRastreio(endereco));

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
    manterProporcao(imagem);
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
      content: CSP_DO_EMAIL,
    }),
    elemento(doc, 'meta', { name: 'color-scheme', content: 'light' }),
    elemento(doc, 'meta', { name: 'referrer', content: 'no-referrer' }),
    elemento(doc, 'base', { target: '_blank' }),
    elemento(doc, 'style', {}, PADRAO_DO_LEITOR)
  );
};

const semMudar = endereco => endereco;
// Sem janela (teste): uma tela de notebook comum.
const TELA_PADRAO = { altura: 800, largura: 1280, combina: () => false };

const montarDocumento = (html, semRastreio, tela) => {
  const original = lerDocumento(html);
  const raizOriginal = original.documentElement;
  const lingua = raizOriginal.getAttribute('lang');
  const direcao = raizOriginal.getAttribute('dir');
  const atributos = atributosDoCorpo(original, semRastreio);
  envolverOCorpo(original);
  atributosDeTabelaComoEstilo(original);
  // Antes do sanitizador: svg e math relidos viram <style> sem folha, e ele lança.
  semMarcacaoPerigosa(original.documentElement);
  prepararEstilos(original, { conferirUrls: true, tela });
  const limpo = sanitize(comoTexto(original), '', {
    noWrapper: true,
    preserveCssPriority: true,
    allowedCssProperties: CSS_DA_MOLDURA,
    rewriteExternalLinks: semRastreio,
    rewriteExternalResources: imagemSemRastreio(semRastreio),
  });
  const doc = lerDocumento(`<!doctype html><html><body>${limpo}</body></html>`);
  devolverAoCorpo(doc, atributos);
  semMarcacaoPerigosa(doc.body);
  limparLinksEImagens(doc);
  montarCabeca(doc);
  doc.documentElement.setAttribute('style', DA_MOLDURA);
  if (lingua) doc.documentElement.setAttribute('lang', lingua);
  if (direcao) doc.documentElement.setAttribute('dir', direcao);
  return comoTexto(doc);
};

// Se o HTML derrubar a limpeza, o e-mail aparece como texto, nunca some da conversa.
const documentoSoTexto = html => {
  const original = lerDocumento(html);
  original.querySelectorAll('style, script, title').forEach(no => no.remove());
  const doc = lerDocumento('<!doctype html><html><body></body></html>');
  montarCabeca(doc);
  doc.documentElement.setAttribute('style', DA_MOLDURA);
  doc.body.append(
    elemento(
      doc,
      'div',
      { style: 'white-space:pre-wrap;padding:8px' },
      original.body?.textContent?.trim() || ''
    )
  );
  return comoTexto(doc);
};

// O documento que vai no srcdoc da moldura. `semRastreio` troca endereço de imagem e
// de link (o mesmo de hoje: tira o pixel e o clique rastreado das Campanhas).
// `tela`: a janela do painel (cssDaMoldura.js), onde valem vh e @media de altura.
export const documentoIsolado = (
  html,
  { semRastreio = semMudar, tela = TELA_PADRAO } = {}
) => {
  try {
    return montarDocumento(html, semRastreio, tela);
  } catch (erro) {
    // eslint-disable-next-line no-console
    console.error(
      'E-mail: o HTML do remetente não pôde ser limpo',
      erro?.message
    );
    return documentoSoTexto(html);
  }
};

// Para Imprimir: o corpo já limpo, com o estilo do <body> numa div, e o CSS do remetente
// com escopo de novo.
export const corpoParaImprimir = srcdoc => {
  const doc = lerDocumento(srcdoc);
  const div = doc.createElement('div');
  const estilo = doc.body.getAttribute('style');
  if (estilo) div.setAttribute('style', estilo);
  const fundo = doc.body.getAttribute('bgcolor');
  if (fundo && !div.style.backgroundColor) div.style.backgroundColor = fundo;
  div.append(...doc.body.childNodes);
  doc.body.replaceChildren(div);
  prepararEstilos(doc, { conferirUrls: true });
  const limpo = sanitize(comoTexto(doc), '', {
    id: ESCOPO_DA_IMPRESSAO,
    preserveCssPriority: true,
    allowedCssProperties: CSS_DA_MOLDURA,
    // Como na tela: imagem embutida (data:image) fica, endereço relativo sai.
    rewriteExternalResources: imagemSemRastreio(semMudar),
  });
  // O sanitizador tira a proporção da imagem: volta, como na tela.
  const impresso = lerDocumento(limpo);
  impresso.querySelectorAll('img').forEach(manterProporcao);
  return impresso.body.innerHTML;
};
