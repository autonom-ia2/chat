import { renderizar, refDoLink } from '../helpers/markdown';

describe('markdown da Central de Ajuda', () => {
  it('reconhece o link para outro artigo da Central', () => {
    expect(refDoLink('plataforma-02-04')).toBe('02-04');
    expect(refDoLink('https://exemplo.com')).toBeNull();
    expect(refDoLink(null)).toBeNull();
  });

  it('não quebra o parágrafo nas linhas do arquivo', () => {
    const html = renderizar('Uma frase que\ncontinua na linha de baixo.');

    expect(html).toBe('<p>Uma frase que\ncontinua na linha de baixo.</p>\n');
    expect(html).not.toContain('<br');
  });

  it('abre link de fora em outra aba e mantém o link da Central na mesma tela', () => {
    const html = renderizar(
      'Veja [Sua assinatura](plataforma-02-04) e [o site](https://exemplo.com).'
    );

    expect(html).toContain('<a href="plataforma-02-04">Sua assinatura</a>');
    expect(html).toContain(
      '<a href="https://exemplo.com" target="_blank" rel="noopener noreferrer">o site</a>'
    );
  });

  it('não deixa passar HTML cru', () => {
    expect(renderizar('<script>alert(1)</script>')).not.toContain('<script>');
  });

  it('transforma os títulos das seções em h2', () => {
    expect(renderizar('## O que é')).toBe('<h2>O que é</h2>\n');
  });
});
