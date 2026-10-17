import {
  JANELA_DO_ALBUM_EM_SEGUNDOS,
  agruparAlbuns,
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

describe('agruparAlbuns (#1702)', () => {
  it('3 fotos do cliente em segundos viram um álbum só (o teste com a Meta)', () => {
    const lista = [
      foto(),
      foto({ createdAt: BASE + 1 }),
      foto({ createdAt: BASE + 2 }),
    ];
    const albuns = agruparAlbuns(lista, { fuso: FUSO });
    expect(ids(albuns)).toEqual([lista.map(m => m.id)]);
    expect(albuns.has(lista[0].id)).toBe(true);
  });

  it('2 itens já formam álbum; 1 sozinho não', () => {
    const dupla = [foto(), video({ createdAt: BASE + 3 })];
    expect(ids(agruparAlbuns(dupla, { fuso: FUSO }))).toEqual([
      dupla.map(m => m.id),
    ]);
    expect(agruparAlbuns([foto()], { fuso: FUSO }).size).toBe(0);
  });

  it('espera maior que a janela quebra o álbum', () => {
    const lista = [
      foto(),
      foto({ createdAt: BASE + 1 }),
      foto({ createdAt: BASE + 1 + JANELA_DO_ALBUM_EM_SEGUNDOS + 1 }),
    ];
    expect(ids(agruparAlbuns(lista, { fuso: FUSO }))).toEqual([
      [lista[0].id, lista[1].id],
    ]);
  });

  it('a janela conta de um item para o seguinte, não do primeiro', () => {
    const passo = JANELA_DO_ALBUM_EM_SEGUNDOS;
    const lista = [0, 1, 2, 3].map(i => foto({ createdAt: BASE + i * passo }));
    expect(ids(agruparAlbuns(lista, { fuso: FUSO }))).toEqual([
      lista.map(m => m.id),
    ]);
  });

  it('texto no meio ou outra pessoa separam; foto com legenda junta', () => {
    const a = foto();
    const b = foto({ createdAt: BASE + 1 });
    const meio = texto({ createdAt: BASE + 2 });
    const c = foto({ createdAt: BASE + 3 });
    const legenda = foto({ createdAt: BASE + 4, content: 'essa' });
    const d = foto({ createdAt: BASE + 5 });
    const atendente = foto({
      createdAt: BASE + 6,
      messageType: 1,
      senderId: 1,
      senderType: 'User',
    });
    const lista = [a, b, meio, c, legenda, d, atendente];
    expect(ids(agruparAlbuns(lista, { fuso: FUSO }))).toEqual([
      [a.id, b.id],
      [c.id, legenda.id, d.id],
    ]);
  });

  it('a empresa também manda álbum', () => {
    const daAna = extras =>
      foto({ messageType: 1, senderId: 1, senderType: 'User', ...extras });
    const lista = [daAna(), daAna({ createdAt: BASE + 2 })];
    expect(agruparAlbuns(lista, { fuso: FUSO }).size).toBe(1);
  });

  it('virada do dia quebra o álbum', () => {
    // 23:59:50 e 00:00:05 em São Paulo.
    const noite = Date.UTC(2026, 9, 17, 2, 59, 50) / 1000;
    const lista = [foto({ createdAt: noite }), foto({ createdAt: noite + 15 })];
    expect(agruparAlbuns(lista, { fuso: FUSO }).size).toBe(0);
  });

  it('a 1ª não lida abre bloco novo (a etiqueta não some dentro do álbum)', () => {
    const lista = [0, 1, 2, 3].map(i => foto({ createdAt: BASE + i }));
    const albuns = agruparAlbuns(lista, {
      fuso: FUSO,
      abreBloco: mensagem => mensagem.id === lista[2].id,
    });
    expect(ids(albuns)).toEqual([
      [lista[0].id, lista[1].id],
      [lista[2].id, lista[3].id],
    ]);
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
