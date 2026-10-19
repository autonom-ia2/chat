// Duas falhas do lettersanitizer 1.0.8 que o e-mail do remetente consegue provocar (#1884):
// 1. CSS com "<" escapado (`\3c /style\3e`) volta como "</style>" de verdade quando o
//    sanitizador regrava a folha. Lido de novo, o resto vira marcação (meta refresh,
//    atributos on*), fora da lista do sanitizador.
// 2. url() com "%" quebrado faz o decodeURI do sanitizador lançar, e o e-mail não abre.
// Antes de sanitizar, as regras de CSS com esses defeitos saem (o resto do CSS fica). Depois,
// por garantia, sai o que nunca pode estar no corpo. Lê a estrutura (CSSOM e DOM), sem regex.

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
const cssSeguro = texto =>
  !texto.includes('<') && urlsDoCss(texto.toLowerCase()).every(decodifica);

const regrasSeguras = folha => {
  try {
    return [...folha.cssRules]
      .map(regra => regra.cssText)
      .filter(cssSeguro)
      .join('\n');
  } catch {
    return '';
  }
};

export const prepararEstilos = doc => {
  doc.querySelectorAll('style').forEach(estilo => {
    if (!estilo.sheet) {
      estilo.remove();
      return;
    }
    estilo.textContent = regrasSeguras(estilo.sheet);
  });
  doc.querySelectorAll('[style]').forEach(elemento => {
    if (!cssSeguro(elemento.style.cssText)) elemento.removeAttribute('style');
  });
};

// Nunca no corpo do e-mail, venha de onde vier.
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
  'form',
  'input',
  'textarea',
  'select',
  'button',
  'svg',
  'math',
].join(',');

export const semMarcacaoPerigosa = raiz => {
  raiz.querySelectorAll(PROIBIDOS).forEach(no => no.remove());
  raiz.querySelectorAll('*').forEach(elemento => {
    elemento
      .getAttributeNames()
      .filter(nome => nome.toLowerCase().startsWith('on'))
      .forEach(nome => elemento.removeAttribute(nome));
  });
};
