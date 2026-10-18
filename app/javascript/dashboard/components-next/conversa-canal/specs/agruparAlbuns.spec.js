import {
  JANELA_DO_ALBUM_EM_SEGUNDOS,
  JANELA_DO_ENVIO_EM_SEGUNDOS,
  agruparAlbuns,
  agruparDaConversa,
  eMarcadorDeAlbum,
  podeEntrarNoAlbum,
  quadrosDoMosaico,
  tiqueDoAlbum,
} from '../album/agruparAlbuns';

const FUSO = 'America/Sao_Paulo';
// 16/10/2026 15:00 em São Paulo.
const BASE = Date.UTC(2026, 9, 16, 18, 0) / 1000;

let proximoId = 0;
const novoId = () => {
  proximoId += 1;
  return proximoId;
};
const foto = (extras = {}) => ({
  id: novoId(),
  messageType: 0,
  senderId: 7,
  senderType: 'Contact',
  createdAt: BASE,
  status: 'sent',
  content: null,
  contentAttributes: {},
  attachments: [{ fileType: 'image', dataUrl: 'https://x.test/a.jpg' }],
  ...extras,
});
const video = (extras = {}) =>
  foto({
    attachments: [{ fileType: 'video', dataUrl: 'https://x.test/a.mp4' }],
    ...extras,
  });
const texto = (extras = {}) =>
  foto({ content: 'oi', attachments: [], ...extras });
// O "pai" do álbum que a Cloud entrega como não suportada, logo antes das fotos.
const marcador = (extras = {}) =>
  texto({
    content: null,
    contentAttributes: { isUnsupported: true, unsupportedKind: 'unknown' },
    ...extras,
  });
// Mandada pela plataforma (atendente 1).
const daAna = (extras = {}) =>
  foto({ messageType: 1, senderId: 1, senderType: 'User', ...extras });

const ids = albuns => [...albuns.values()].map(itens => itens.map(m => m.id));

describe('podeEntrarNoAlbum (#1702)', () => {
  it('foto e vídeo entram, com ou sem legenda (WhatsApp 2026)', () => {
    expect(podeEntrarNoAlbum(foto())).toBe(true);
    expect(podeEntrarNoAlbum(video())).toBe(true);
    expect(podeEntrarNoAlbum(foto({ content: 'olha' }))).toBe(true);
  });

  it('citação, falha, nota, apagada ou outro anexo ficam de fora', () => {
    expect(
      podeEntrarNoAlbum(
        foto({ contentAttributes: { deletedByContactAt: '2026-10-16T18:00Z' } })
      )
    ).toBe(false);
    expect(
      podeEntrarNoAlbum(foto({ contentAttributes: { inReplyTo: 3 } }))
    ).toBe(false);
    expect(podeEntrarNoAlbum(foto({ status: 'failed' }))).toBe(false);
    expect(podeEntrarNoAlbum(foto({ private: true }))).toBe(false);
    expect(
      podeEntrarNoAlbum(foto({ contentAttributes: { deleted: true } }))
    ).toBe(false);
    expect(
      podeEntrarNoAlbum(foto({ attachments: [{ fileType: 'audio' }] }))
    ).toBe(false);
    expect(
      podeEntrarNoAlbum(
        foto({ attachments: [{ fileType: 'image' }, { fileType: 'image' }] })
      )
    ).toBe(false);
  });
});

describe('podeEntrarNoAlbum: o que não se encaminha fica solto', () => {
  it('visualização única, modelo/campanha e atividade não entram', () => {
    expect(
      podeEntrarNoAlbum(
        foto({ attachments: [{ fileType: 'image', isViewOnce: true }] })
      )
    ).toBe(false);
    expect(
      podeEntrarNoAlbum(
        foto({
          messageType: 1,
          additionalAttributes: { templateParams: { name: 'x' } },
        })
      )
    ).toBe(false);
    expect(
      podeEntrarNoAlbum(
        foto({ messageType: 1, additionalAttributes: { campaignId: 3 } })
      )
    ).toBe(false);
    expect(podeEntrarNoAlbum(foto({ messageType: 2 }))).toBe(false);
    expect(podeEntrarNoAlbum(foto({ messageType: 3 }))).toBe(false);
  });

  it('foto de visualização única no meio corta o álbum', () => {
    const lista = [
      marcador(),
      foto(),
      foto({ createdAt: BASE + 1 }),
      foto({
        createdAt: BASE + 2,
        attachments: [{ fileType: 'image', isViewOnce: true }],
      }),
      foto({ createdAt: BASE + 3 }),
    ];
    const albuns = agruparAlbuns(lista, { fuso: FUSO });
    expect(ids(albuns)).toEqual([[lista[1].id, lista[2].id]]);
  });

  it('fotos de modelo da empresa não viram álbum', () => {
    const modelo = extras =>
      foto({
        messageType: 1,
        senderType: 'User',
        additionalAttributes: { templateParams: { name: 'x' } },
        ...extras,
      });
    const lista = [modelo(), modelo({ createdAt: BASE + 1 })];
    expect(agruparAlbuns(lista, { fuso: FUSO }).size).toBe(0);
  });
});

describe('agruparAlbuns: recebido só com o marcador da Cloud (#1702)', () => {
  it('o marcador "unknown" do cliente é o sinal; outros tipos e o nosso não', () => {
    expect(eMarcadorDeAlbum(marcador())).toBe(true);
    expect(
      eMarcadorDeAlbum(
        marcador({
          contentAttributes: { isUnsupported: true, unsupportedKind: 'poll' },
        })
      )
    ).toBe(false);
    expect(eMarcadorDeAlbum(marcador({ messageType: 1 }))).toBe(false);
    expect(eMarcadorDeAlbum(foto())).toBe(false);
  });

  it('marcador + 3 fotos viram um álbum e o marcador some da lista', () => {
    const pai = marcador();
    const fotos = [0, 1, 2].map(i => foto({ createdAt: BASE + i }));
    const { albuns, marcadores } = agruparDaConversa([pai, ...fotos], {
      fuso: FUSO,
    });
    expect(ids(albuns)).toEqual([fotos.map(m => m.id)]);
    expect(albuns.has(fotos[0].id)).toBe(true);
    expect([...marcadores]).toEqual([pai.id]);
  });

  it('sem marcador, cada foto fica solta (produção: 2 fotos com 20 s, uma a uma)', () => {
    const lista = [foto(), foto({ createdAt: BASE + 20 })];
    expect(agruparAlbuns(lista, { fuso: FUSO }).size).toBe(0);
    const tres = [0, 1, 2].map(i => foto({ createdAt: BASE + i }));
    expect(agruparAlbuns(tres, { fuso: FUSO }).size).toBe(0);
  });

  it('vídeo 30 s depois da última foto não entra (conta 16, conversa 20)', () => {
    const pai = marcador();
    const fotos = [1, 2, 3, 4].map(i => foto({ createdAt: BASE + i }));
    const tarde = video({ createdAt: BASE + 4 + JANELA_DO_ALBUM_EM_SEGUNDOS });
    const { albuns, marcadores } = agruparDaConversa([pai, ...fotos, tarde], {
      fuso: FUSO,
    });
    expect(ids(albuns)).toEqual([fotos.map(m => m.id)]);
    expect([...marcadores]).toEqual([pai.id]);
  });

  it('a janela de 30 s conta do marcador, não de um item para o seguinte', () => {
    const pai = marcador();
    const dentro = foto({ createdAt: BASE + JANELA_DO_ALBUM_EM_SEGUNDOS - 1 });
    const noLimite = foto({ createdAt: BASE + JANELA_DO_ALBUM_EM_SEGUNDOS });
    const fora = foto({ createdAt: BASE + JANELA_DO_ALBUM_EM_SEGUNDOS + 1 });
    expect(
      ids(agruparAlbuns([pai, dentro, noLimite, fora], { fuso: FUSO }))
    ).toEqual([[dentro.id, noLimite.id]]);
  });

  it('para no 1º item que não entra (texto no meio, outra pessoa)', () => {
    const pai = marcador();
    const a = foto();
    const b = foto({ createdAt: BASE + 1, content: 'essa' });
    const meio = texto({ createdAt: BASE + 2 });
    const c = foto({ createdAt: BASE + 3 });
    expect(ids(agruparAlbuns([pai, a, b, meio, c], { fuso: FUSO }))).toEqual([
      [a.id, b.id],
    ]);
    const outro = foto({ createdAt: BASE + 1, senderId: 8 });
    expect(agruparAlbuns([pai, a, outro], { fuso: FUSO }).size).toBe(0);
  });

  it('marcador com uma foto só não abre álbum e continua à vista', () => {
    const pai = marcador();
    const { albuns, marcadores } = agruparDaConversa([pai, foto()], {
      fuso: FUSO,
    });
    expect(albuns.size).toBe(0);
    expect(marcadores.size).toBe(0);
  });

  it('dois álbuns seguidos, cada um com o seu marcador', () => {
    const pai1 = marcador();
    const a = [0, 1].map(i => foto({ createdAt: BASE + i }));
    const pai2 = marcador({ createdAt: BASE + 5 });
    const b = [6, 7].map(i => foto({ createdAt: BASE + i }));
    const { albuns, marcadores } = agruparDaConversa([pai1, ...a, pai2, ...b], {
      fuso: FUSO,
    });
    expect(ids(albuns)).toEqual([a.map(m => m.id), b.map(m => m.id)]);
    expect([...marcadores]).toEqual([pai1.id, pai2.id]);
  });

  it('virada do dia quebra o álbum', () => {
    // 23:59:50 e 00:00:05 em São Paulo.
    const noite = Date.UTC(2026, 9, 17, 2, 59, 50) / 1000;
    const lista = [
      marcador({ createdAt: noite }),
      foto({ createdAt: noite }),
      foto({ createdAt: noite + 15 }),
    ];
    expect(agruparAlbuns(lista, { fuso: FUSO }).size).toBe(0);
  });

  it('a 1ª não lida no meio fecha o álbum (a etiqueta não some dentro dele)', () => {
    const pai = marcador();
    const fotos = [0, 1, 2, 3].map(i => foto({ createdAt: BASE + i }));
    const albuns = agruparAlbuns([pai, ...fotos], {
      fuso: FUSO,
      abreBloco: mensagem => mensagem.id === fotos[2].id,
    });
    expect(ids(albuns)).toEqual([[fotos[0].id, fotos[1].id]]);
  });
});

describe('agruparAlbuns: enviado pela plataforma (#1702)', () => {
  it('fotos do mesmo envio (até 3 s uma da outra) viram álbum', () => {
    const lista = [
      daAna(),
      daAna({ createdAt: BASE + 1 }),
      video({
        messageType: 1,
        senderId: 1,
        senderType: 'User',
        createdAt: BASE + 1 + JANELA_DO_ENVIO_EM_SEGUNDOS,
      }),
    ];
    const { albuns, marcadores } = agruparDaConversa(lista, { fuso: FUSO });
    expect(ids(albuns)).toEqual([lista.map(m => m.id)]);
    expect(marcadores.size).toBe(0);
  });

  it('mandadas uma a uma (mais de 3 s) ficam soltas', () => {
    const lista = [
      daAna(),
      daAna({ createdAt: BASE + JANELA_DO_ENVIO_EM_SEGUNDOS + 1 }),
    ];
    expect(agruparAlbuns(lista, { fuso: FUSO }).size).toBe(0);
  });

  it('outro atendente ou foto do cliente no meio separam', () => {
    const lista = [
      daAna(),
      daAna({ createdAt: BASE + 1, senderId: 2 }),
      daAna({ createdAt: BASE + 1 }),
      foto({ createdAt: BASE + 1 }),
      daAna({ createdAt: BASE + 2 }),
    ];
    expect(agruparAlbuns(lista, { fuso: FUSO }).size).toBe(0);
  });

  it('sem marcador, a foto do cliente não pega carona no envio rápido', () => {
    const lista = [foto(), foto({ createdAt: BASE + 1 })];
    expect(agruparAlbuns(lista, { fuso: FUSO }).size).toBe(0);
  });
});

describe('mosaico e tique (#1702)', () => {
  it('até 4 quadros sem "+N"; mais de 4 mostra 4 e esconde o resto atrás do 4º', () => {
    const quatro = [1, 2, 3, 4];
    expect(quadrosDoMosaico(quatro)).toEqual({
      quadros: quatro,
      escondidos: 0,
    });
    expect(quadrosDoMosaico([1, 2, 3, 4, 5, 6, 7])).toEqual({
      quadros: [1, 2, 3, 4],
      escondidos: 4,
    });
  });

  it('o tique é o do item mais atrasado', () => {
    expect(
      tiqueDoAlbum([{ status: 'read' }, { status: 'sent' }, { status: 'read' }])
    ).toBe('sent');
    expect(tiqueDoAlbum([{ status: 'read' }, { status: 'delivered' }])).toBe(
      'delivered'
    );
    expect(tiqueDoAlbum([])).toBeUndefined();
  });
});
