import { BALOES, balaoDoInstagram } from '../balaoDoInstagram';

const anexo = (fileType, dataUrl = 'https://lookaside.fbsbx.com/x') => ({
  id: Math.random(),
  fileType,
  dataUrl,
});

describe('balaoDoInstagram', () => {
  it('texto puro', () => {
    expect(balaoDoInstagram({ content: 'Oi', attachments: [] })).toBe(
      BALOES.TEXTO
    );
  });

  it('foto e vídeo avulsos são mídia; vários juntos, álbum', () => {
    expect(balaoDoInstagram({ attachments: [anexo('image')] })).toBe(
      BALOES.MIDIA
    );
    expect(balaoDoInstagram({ attachments: [anexo('video')] })).toBe(
      BALOES.MIDIA
    );
    expect(
      balaoDoInstagram({
        attachments: [anexo('image'), anexo('video'), anexo('image')],
      })
    ).toBe(BALOES.ALBUM);
  });

  it('áudio é voz e reel é reel', () => {
    expect(balaoDoInstagram({ attachments: [anexo('audio')] })).toBe(
      BALOES.VOZ
    );
    expect(balaoDoInstagram({ attachments: [anexo('ig_reel')] })).toBe(
      BALOES.REEL
    );
  });

  it('imagem do Giphy é figurinha; outro endereço parecido não é', () => {
    expect(
      balaoDoInstagram({
        attachments: [anexo('image', 'https://media0.giphy.com/a.gif')],
      })
    ).toBe(BALOES.FIGURINHA);
    expect(
      balaoDoInstagram({
        attachments: [anexo('image', 'https://giphy.com.exemplo.net/a.gif')],
      })
    ).toBe(BALOES.MIDIA);
    expect(
      balaoDoInstagram({ attachments: [anexo('image', 'endereço inválido')] })
    ).toBe(BALOES.MIDIA);
  });

  it('servida da nossa cópia, a figurinha é reconhecida pela origem (externalUrl)', () => {
    const nossa =
      'https://app.exemplo.com/rails/active_storage/blobs/redirect/x/a.gif';
    expect(
      balaoDoInstagram({
        attachments: [
          {
            ...anexo('image', nossa),
            externalUrl: 'https://media0.giphy.com/a.gif',
          },
        ],
      })
    ).toBe(BALOES.FIGURINHA);
    expect(
      balaoDoInstagram({
        attachments: [
          {
            ...anexo('image', nossa),
            externalUrl: 'https://lookaside.fbsbx.com/ig_messaging_cdn/x',
          },
        ],
      })
    ).toBe(BALOES.MIDIA);
  });

  it('post e story pelo image_type gravado no recebimento', () => {
    expect(
      balaoDoInstagram({
        contentAttributes: { imageType: 'ig_post' },
        attachments: [anexo('image')],
      })
    ).toBe(BALOES.POST);
    ['story_mention', 'ig_story', 'ig_story_reply'].forEach(imageType => {
      expect(
        balaoDoInstagram({ contentAttributes: { imageType }, attachments: [] })
      ).toBe(BALOES.STORY);
    });
  });

  it('apagada vence tudo; não suportada e arquivo seguem no balão de sempre', () => {
    expect(
      balaoDoInstagram({
        content: 'Esta mensagem foi excluída',
        contentAttributes: { deleted: true },
      })
    ).toBe(BALOES.APAGADA);
    expect(
      balaoDoInstagram({
        contentAttributes: { isUnsupported: true },
        attachments: [],
      })
    ).toBeNull();
    expect(balaoDoInstagram({ attachments: [anexo('file')] })).toBeNull();
    expect(
      balaoDoInstagram({ attachments: [anexo('image'), anexo('file')] })
    ).toBeNull();
    expect(balaoDoInstagram({ content: '', attachments: [] })).toBeNull();
  });

  it('pesquisa de satisfação, opções e formulário de robô e chamada de vídeo ficam no balão próprio', () => {
    ['input_csat', 'input_select', 'form'].forEach(contentType => {
      expect(
        balaoDoInstagram({ content: 'Avalie', contentType, attachments: [] })
      ).toBeNull();
    });
    expect(
      balaoDoInstagram({
        content: 'Chamada',
        contentAttributes: { type: 'dyte' },
        attachments: [],
      })
    ).toBeNull();
    expect(
      balaoDoInstagram({
        content: 'Escolha',
        contentType: 'text',
        contentAttributes: { richMessage: { type: 'options' } },
        attachments: [],
      })
    ).toBeNull();
    expect(
      balaoDoInstagram({ content: 'Oi', contentType: 'text', attachments: [] })
    ).toBe(BALOES.TEXTO);
  });
});
