// Falhas do lettersanitizer 1.0.8 que o CSS do remetente consegue provocar (#1891):
// 1. CSS com "<" escapado (`\3c /style\3e`) volta como "</style>" de verdade quando o
//    sanitizador regrava a folha (cssText do CSSOM). Lido de novo, o resto vira marcação.
// 2. Ele só limpa as regras de estilo do 1º nível (e de um @media): o que vem aninhado mais
//    fundo (@supports, @media dentro de @media, CSS aninhado) sai sem escopo nem filtro.
// 3. Com a reescrita de endereços (moldura isolada, #1884), url() com "%" quebrado faz o
//    decodeURI dele lançar, e o e-mail não abre: com `conferirUrls`, essas regras também saem.
// Antes de sanitizar, as regras com esses defeitos saem; o resto do CSS fica. Lê a
// estrutura (CSSOM e DOM), sem regex.

import { regraDaMoldura, semUnidadeDaTela } from './cssDaMoldura';

const INICIO_DE_URL = 'url(';

const urlsDoCss = texto => {
  const urls = [];
  let inicio = texto.indexOf(INICIO_DE_URL);
  while (inicio >= 0) {
    const fim = texto.indexOf(')', inicio);
    if (fim < 0) break;
    urls.push(texto.slice(inicio + INICIO_DE_URL.length, fim));
    inicio = texto.indexOf(INICIO_DE_URL, fim);
  }
  return urls;
};

const decodifica = endereco => {
  try {
    decodeURI(endereco);
    return true;
  } catch {
    return false;
  }
};

// O texto já normalizado pelo navegador (cssText): é o que o sanitizador vai regravar.
// Dentro de <style>, só "</" fecha o bloco; "<" sozinho (`width < 600px`) é CSS válido.
const FECHA_TAG = '</';
const cssSeguro = (texto, conferirUrls) =>
  !texto.includes(FECHA_TAG) &&
  (!conferirUrls || urlsDoCss(texto.toLowerCase()).every(decodifica));

// Só o que o sanitizador sabe limpar: regra de estilo sem regra aninhada, ou @media só com
// regras assim. O resto ele não descartaria por inteiro, e sairia sem escopo.
const semAninhadas = regra => !regra.cssRules?.length;
const regraLimpavel = regra => {
  if (regra instanceof CSSStyleRule) return semAninhadas(regra);
  if (regra instanceof CSSMediaRule) {
    return [...regra.cssRules].every(
      filha => filha instanceof CSSStyleRule && semAninhadas(filha)
    );
  }
  return false;
};

const regrasSeguras = (folha, conferirUrls, tela) => {
  try {
    return [...folha.cssRules]
      .filter(regraLimpavel)
      .map(regra => (tela ? regraDaMoldura(regra, tela) : regra.cssText))
      .filter(texto => texto && cssSeguro(texto, conferirUrls))
      .join('\n');
  } catch (erro) {
    // Sem conferir, nenhuma regra passa: o e-mail sai sem o CSS dele, nunca com CSS sem filtro.
    // eslint-disable-next-line no-console
    console.error(
      'E-mail: CSS do remetente não pôde ser conferido',
      erro?.message
    );
    return '';
  }
};

// `tela`: na moldura isolada, as medidas da tela da moldura passam a ser as do painel
// (cssDaMoldura.js).
export const prepararEstilos = (
  doc,
  { conferirUrls = false, tela = null } = {}
) => {
  doc.querySelectorAll('style').forEach(estilo => {
    if (!estilo.sheet) {
      estilo.remove();
      return;
    }
    estilo.textContent = regrasSeguras(estilo.sheet, conferirUrls, tela);
  });
  doc.querySelectorAll('[style]').forEach(elemento => {
    const texto = elemento.style.cssText;
    if (!cssSeguro(texto, conferirUrls)) {
      elemento.removeAttribute('style');
    } else if (tela) {
      elemento.setAttribute('style', semUnidadeDaTela(texto, tela));
    }
  });
};

// Nunca no corpo do e-mail, venha de onde vier.
// svg e math relidos pelo sanitizador viram <style> sem folha, e ele lança: saem antes.
const RELIDOS_COM_PERIGO = ['svg', 'math'].join(',');
const PROIBIDOS = [
  'script',
  'noscript',
  'template',
  'meta',
  'base',
  'link',
  'title',
  'iframe',
  'frame',
  'frameset',
  'object',
  'embed',
  'applet',
  'input',
  'svg',
  'math',
].join(',');
// Saem só as tags: o texto de dentro fica (como o sanitizador sempre fez).
const SO_A_TAG = ['form', 'button', 'select', 'textarea'].join(',');

export const semMarcacaoPerigosa = raiz => {
  raiz.querySelectorAll(PROIBIDOS).forEach(no => no.remove());
  raiz
    .querySelectorAll(SO_A_TAG)
    .forEach(no => no.replaceWith(...no.childNodes));
  raiz.querySelectorAll('*').forEach(elemento => {
    elemento
      .getAttributeNames()
      .filter(nome => nome.toLowerCase().startsWith('on'))
      .forEach(nome => elemento.removeAttribute(nome));
  });
};

// Na entrada do vue-letter, em todo lugar que mostra HTML de remetente: as regras de CSS
// defeituosas saem antes de o sanitizador regravar a folha. O resto do e-mail fica igual.
export const htmlComCssSeguro = html => {
  if (!html) return html;
  const doc = new DOMParser().parseFromString(String(html), 'text/html');
  // O resto da limpeza do balão antigo continua com o sanitizador, como sempre.
  doc.querySelectorAll(RELIDOS_COM_PERIGO).forEach(no => no.remove());
  prepararEstilos(doc);
  return doc.documentElement.outerHTML;
};
