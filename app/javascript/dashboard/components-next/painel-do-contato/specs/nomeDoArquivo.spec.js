import { nomeDoArquivo } from '../nomeDoArquivo';

// #2138 — o nome do arquivo na lista "Arquivos desta conversa".
describe('nomeDoArquivo', () => {
  it('tira o caminho e o que vem depois do "?", e decodifica', () => {
    expect(
      nomeDoArquivo({
        data_url:
          'https://x.test/rails/blob/abc/or%C3%A7amento%20final.pdf?v=1',
      })
    ).toBe('orçamento final.pdf');
  });

  it('nome com % solto não quebra: fica o nome cru', () => {
    expect(nomeDoArquivo({ data_url: 'https://x.test/a/50%.pdf' })).toBe(
      '50%.pdf'
    );
    expect(nomeDoArquivo({ data_url: 'https://x.test/a/%E0%A4%A.png' })).toBe(
      '%E0%A4%A.png'
    );
  });

  it('sem endereço, vazio', () => {
    expect(nomeDoArquivo({})).toBe('');
    expect(nomeDoArquivo({ data_url: null })).toBe('');
  });
});
