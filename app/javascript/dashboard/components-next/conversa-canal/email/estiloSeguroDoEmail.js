// Falhas do lettersanitizer 1.0.8 que o CSS do remetente consegue provocar (#1891):
// 1. CSS com "<" escapado (`\3c /style\3e`) volta como "</style>" de verdade quando o
//    sanitizador regrava a folha (cssText do CSSOM). Lido de novo, o resto vira marcação.
// 2. Ele só limpa as regras de estilo do 1º nível (e de um @media): o que vem aninhado mais
//    fundo (@supports, @media dentro de @media, CSS aninhado) sai sem escopo nem filtro.
// Antes de sanitizar, as regras com esses defeitos saem; o resto do CSS fica. Lê a
// estrutura (CSSOM e DOM), sem regex.

// O texto já normalizado pelo navegador (cssText): é o que o sanitizador vai regravar.
// Dentro de <style>, só "</" fecha o bloco; "<" sozinho (`width < 600px`) é CSS válido.
const FECHA_TAG = '</';
const cssSeguro = texto => !texto.includes(FECHA_TAG);

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

const regrasSeguras = folha => {
  try {
    return [...folha.cssRules]
      .filter(regraLimpavel)
      .map(regra => regra.cssText)
      .filter(cssSeguro)
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

// Na entrada do vue-letter, em todo lugar que mostra HTML de remetente: as regras de CSS
// defeituosas saem antes de o sanitizador regravar a folha. O resto do e-mail fica igual.
export const htmlComCssSeguro = html => {
  if (!html) return html;
  const doc = new DOMParser().parseFromString(String(html), 'text/html');
  prepararEstilos(doc);
  return doc.documentElement.outerHTML;
};
