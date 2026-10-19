import { htmlComCssSeguro } from '../email/estiloSeguroDoEmail';

// O CSS do remetente não pode escapar do <style> quando o vue-letter regrava a folha.
// O jsdom não monta a folha (CSSOM) de um documento do DOMParser: aqui se prova o estilo
// inline e a saída segura sem folha. As regras do <style> são provadas num Chrome de verdade.
const corpo = html =>
  new DOMParser().parseFromString(htmlComCssSeguro(html), 'text/html');

describe('htmlComCssSeguro', () => {
  it('tira o style inline com "<" e mantém o inline comum', () => {
    const doc = corpo(
      '<p id="a" style="font-family:\'a<b\'">x</p><p id="b" style="color:red">y</p>'
    );
    expect(doc.getElementById('a').hasAttribute('style')).toBe(false);
    expect(doc.getElementById('b').getAttribute('style')).toContain('red');
  });

  it('tira o style inline com url() que o sanitizador não consegue decodificar', () => {
    const doc = corpo(
      '<p id="a" style="background:url(%E0%A4%A)">x</p><p id="b" style="background:url(https://x.test/a.png)">y</p>'
    );
    expect(doc.getElementById('a').hasAttribute('style')).toBe(false);
    expect(doc.getElementById('b').getAttribute('style')).toContain('x.test');
  });

  it('sem folha de estilo legível, o <style> sai inteiro (nunca passa sem conferir)', () => {
    const doc = corpo(
      '<style>p{font-family:"\\3c /style\\3e \\3c img src=x onerror=alert(1)\\3e "}</style><p>oi</p>'
    );
    expect(doc.querySelector('[onerror]')).toBeNull();
    expect(doc.querySelector('p').textContent).toBe('oi');
  });

  it('não mexe no e-mail sem CSS defeituoso', () => {
    const doc = corpo(
      '<table width="600"><tr><td bgcolor="#eee">oi</td></tr></table>'
    );
    expect(doc.querySelector('td').getAttribute('bgcolor')).toBe('#eee');
    expect(doc.querySelector('table').getAttribute('width')).toBe('600');
  });

  it('vazio continua vazio', () => {
    expect(htmlComCssSeguro('')).toBe('');
    expect(htmlComCssSeguro(null)).toBe(null);
  });
});
