import { previaDeLink } from '../previaDeLink';

const base = {
  linkPreview: {
    url: 'https://www.exemplo.com.br/seguro',
    title: 'Seguro auto',
    description: 'Cotação online',
    siteName: 'Exemplo Seguros',
    imageUrl: '/rails/active_storage/blobs/redirect/abc/previa-1',
  },
};

describe('previaDeLink', () => {
  it('monta o cartão com o domínio sem www', () => {
    expect(previaDeLink(base)).toEqual({
      url: 'https://www.exemplo.com.br/seguro',
      titulo: 'Seguro auto',
      descricao: 'Cotação online',
      dominio: 'exemplo.com.br',
      site: 'Exemplo Seguros',
      imagem: '/rails/active_storage/blobs/redirect/abc/previa-1',
    });
  });

  it('sem prévia ou sem título não mostra nada', () => {
    expect(previaDeLink({})).toBeNull();
    expect(previaDeLink(undefined)).toBeNull();
    expect(
      previaDeLink({ linkPreview: { ...base.linkPreview, title: '' } })
    ).toBeNull();
  });

  it('mensagem apagada não mostra a prévia', () => {
    expect(previaDeLink({ ...base, deleted: true })).toBeNull();
  });

  it('endereço que não é web não vira link', () => {
    ['ftp://exemplo.com.br/x', 'data:text/html,oi'].forEach(url => {
      expect(
        previaDeLink({ linkPreview: { ...base.linkPreview, url } })
      ).toBeNull();
    });
  });

  it('imagem de fora do nosso servidor não é mostrada', () => {
    const deFora = previaDeLink({
      linkPreview: {
        ...base.linkPreview,
        imageUrl: 'https://rastreador.exemplo/pixel.png',
      },
    });
    const semEsquema = previaDeLink({
      linkPreview: { ...base.linkPreview, imageUrl: '//rastreador.exemplo/p' },
    });

    expect(deFora.imagem).toBe('');
    expect(semEsquema.imagem).toBe('');
  });

  it('caminho com barra invertida (o navegador lê como outro site) não é mostrado', () => {
    ['/\\rastreador.exemplo/p.png', '/\\/rastreador.exemplo/p.png'].forEach(
      imageUrl => {
        const previa = previaDeLink({
          linkPreview: { ...base.linkPreview, imageUrl },
        });
        expect(previa.imagem).toBe('');
      }
    );
    const relativo = previaDeLink({
      linkPreview: { ...base.linkPreview, imageUrl: '/a.png' },
    });
    expect(relativo.imagem).toBe('/a.png');
  });

  it('sem nome do site, usa o domínio', () => {
    const previa = previaDeLink({
      linkPreview: { ...base.linkPreview, siteName: undefined },
    });

    expect(previa.site).toBe('exemplo.com.br');
  });
});
