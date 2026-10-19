import {
  imagemSegura,
  linkSeguro,
  urlsDoValor,
} from '../email/enderecoDoEmail';

// #1884: endereço do HTML do remetente, lido como o navegador grava o CSS.
describe('enderecoDoEmail', () => {
  it('lê os endereços de um valor de CSS, com ")" e aspas escapadas dentro', () => {
    expect(urlsDoValor('url("/X)y")')).toEqual(['/X)y']);
    expect(urlsDoValor('url("a\\"b"), url(https://x.test/c)')).toEqual([
      'a"b',
      'https://x.test/c',
    ]);
    expect(
      urlsDoValor('image-set(url("/a") 1x, URL("https://ok.test/b") 2x)')
    ).toEqual(['/a', 'https://ok.test/b']);
    expect(urlsDoValor('red')).toEqual([]);
  });

  it('imagem só completa web ou embutida; link só web, e-mail e telefone', () => {
    expect(imagemSegura('/X)y')).toBe('');
    expect(imagemSegura('//cdn.test/x.png')).toBe('https://cdn.test/x.png');
    ['http:/X)x', 'http:X)x', 'http:\\X', 'HTTP:/X', 'https:/rota?a=)'].forEach(
      endereco => expect(imagemSegura(endereco)).toBe('')
    );
    expect(linkSeguro('https:/rota')).toBe('');
    // eslint-disable-next-line no-script-url
    expect(imagemSegura('javascript:alert(1)')).toBe('');
    expect(imagemSegura('https://ok.test/a.png')).toBe('https://ok.test/a.png');
    expect(imagemSegura('data:image/png;base64,AAA')).toContain('data:image');
    // eslint-disable-next-line no-script-url
    expect(linkSeguro('javascript:alert(1)')).toBe('');
    expect(linkSeguro('mailto:a@b.test')).toBe('mailto:a@b.test');
  });
});
