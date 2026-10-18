import {
  JANELA_DO_ALBUM_EM_SEGUNDOS,
  VAGA,
  agruparDaConversa,
  quadrosDoAlbum,
} from '../album/agruparAlbuns';

// #1831: o álbum aparece de uma vez, como no app, enquanto as fotos chegam uma a uma.
const FUSO = 'America/Sao_Paulo';
// 18/10/2026 14:03:26 em São Paulo (caixa 118, conta 1).
const BASE = Date.UTC(2026, 9, 18, 17, 3, 26) / 1000;

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
const texto = (extras = {}) =>
  foto({ content: 'oi', attachments: [], ...extras });
// O marcador real: {"unsupported_kind":"unknown","unsupported_type":"album",…}.
const marcador = (extras = {}) =>
  texto({
    content: null,
    contentAttributes: {
      isUnsupported: true,
      unsupportedKind: 'unknown',
      unsupportedType: 'album',
      unsupportedErrorCode: 131051,
    },
    ...extras,
  });
// Mandada pela plataforma (atendente 1).
const daAna = (extras = {}) =>
  foto({ messageType: 1, senderId: 1, senderType: 'User', ...extras });

const agrupar = (lista, agora) =>
  agruparDaConversa(lista, { fuso: FUSO, agora });
const FIM = BASE + JANELA_DO_ALBUM_EM_SEGUNDOS;

describe('álbum chegando: o marcador já abre o álbum (#1831)', () => {
  it('marcador sozinho: o balão do álbum é o do marcador, sem foto e à vista', () => {
    const pai = marcador();
    const { albuns, marcadores, chegadas, emQuadrados } = agrupar(
      [pai],
      BASE + 2
    );
    expect(albuns.get(pai.id)).toEqual([]);
    expect(marcadores.size).toBe(0);
    expect(chegadas.get(pai.id)).toEqual({ noMarcador: true, ate: FIM });
    expect(emQuadrados.has(pai.id)).toBe(true);
  });

  it('marcador + 1 foto: a foto já é o álbum (nunca solta) e o marcador some', () => {
    const pai = marcador();
    const primeira = foto({ createdAt: BASE + 11 });
    const { albuns, marcadores, chegadas } = agrupar(
      [pai, primeira],
      BASE + 12
    );
    expect(albuns.get(primeira.id)).toEqual([primeira]);
    expect([...marcadores]).toEqual([pai.id]);
    expect(chegadas.get(primeira.id).noMarcador).toBe(false);
  });

  it('as fotos que chegam continuam no mesmo balão (a chave não muda)', () => {
    const pai = marcador();
    const fotos = [11, 12, 19].map(s => foto({ createdAt: BASE + s }));
    const { albuns, chegadas } = agrupar([pai, ...fotos], BASE + 20);
    expect([...albuns.keys()]).toEqual([fotos[0].id]);
    expect(albuns.get(fotos[0].id)).toEqual(fotos);
    expect(chegadas.has(fotos[0].id)).toBe(true);
  });

  it('sem a hora de agora, nada está chegando: regra de sempre', () => {
    const pai = marcador();
    const { albuns, marcadores, chegadas } = agruparDaConversa([pai, foto()], {
      fuso: FUSO,
    });
    expect(albuns.size).toBe(0);
    expect(marcadores.size).toBe(0);
    expect(chegadas.size).toBe(0);
  });
});

describe('álbum chegando: fim da janela (#1831)', () => {
  it('janela fechada sem foto: o marcador volta a ser o aviso de sempre', () => {
    const pai = marcador();
    const { albuns, marcadores, chegadas } = agrupar([pai], FIM + 1);
    expect(albuns.size).toBe(0);
    expect(marcadores.size).toBe(0);
    expect(chegadas.size).toBe(0);
  });

  it('janela fechada com 1 foto: como hoje, o aviso e a foto ficam à vista', () => {
    const pai = marcador();
    const { albuns, marcadores } = agrupar(
      [pai, foto({ createdAt: BASE + 11 })],
      FIM + 1
    );
    expect(albuns.size).toBe(0);
    expect(marcadores.size).toBe(0);
  });

  it('janela fechada com 3 fotos: o mesmo álbum, em quadrados, sem "Recebendo"', () => {
    const pai = marcador();
    const fotos = [11, 12, 19].map(s => foto({ createdAt: BASE + s }));
    const { albuns, marcadores, chegadas, emQuadrados } = agrupar(
      [pai, ...fotos],
      FIM + 1
    );
    expect(albuns.get(fotos[0].id)).toEqual(fotos);
    expect([...marcadores]).toEqual([pai.id]);
    expect(chegadas.size).toBe(0);
    expect(emQuadrados.has(fotos[0].id)).toBe(true);
  });

  it('no limite exato da janela ainda está chegando', () => {
    expect(agrupar([marcador()], FIM).chegadas.size).toBe(1);
  });

  it('mensagem que corta a sequência encerra a chegada antes da janela', () => {
    const pai = marcador();
    const primeira = foto({ createdAt: BASE + 11 });
    const corte = texto({ createdAt: BASE + 12 });
    const { albuns, marcadores, chegadas } = agrupar(
      [pai, primeira, corte],
      BASE + 13
    );
    expect(chegadas.size).toBe(0);
    expect(albuns.size).toBe(0);
    expect(marcadores.size).toBe(0);
  });

  it('álbum enviado pela plataforma segue no mosaico de sempre', () => {
    const lista = [daAna(), daAna({ createdAt: BASE + 1 })];
    const { albuns, emQuadrados, chegadas } = agrupar(lista, BASE + 2);
    expect(albuns.size).toBe(1);
    expect(emQuadrados.size).toBe(0);
    expect(chegadas.size).toBe(0);
  });
});

describe('quadrosDoAlbum: nenhum quadro muda de lugar (#1831)', () => {
  const itens = n => Array.from({ length: n }, (_, i) => ({ id: i + 1 }));
  const ids = quadros => quadros.map(quadro => quadro?.id ?? VAGA);
  const chegando = { emQuadrados: true, chegando: true };
  const pronto = { emQuadrados: true, chegando: false };

  it('chegando: quadrados de 2 em 2 que só crescem no fim', () => {
    const passos = [0, 1, 2, 3, 4, 6].map(n =>
      quadrosDoAlbum(itens(n), chegando)
    );
    expect(passos.map(passo => ids(passo.quadros))).toEqual([
      [VAGA, VAGA],
      [1, VAGA],
      [1, 2],
      [1, 2, 3, VAGA],
      [1, 2, 3, 4],
      [1, 2, 3, 4],
    ]);
    expect(passos.every(passo => passo.emQuadrados)).toBe(true);
    expect(passos.map(passo => passo.escondidos)).toEqual([0, 0, 0, 0, 0, 3]);
  });

  it.each([2, 3, 4, 6])(
    'com %i fotos, fechar a janela só tira o reservado: os quadros ficam iguais',
    n => {
      const antes = quadrosDoAlbum(itens(n), chegando);
      const depois = quadrosDoAlbum(itens(n), pronto);
      expect(depois.emQuadrados).toBe(true);
      expect(ids(depois.quadros)).toEqual(
        ids(antes.quadros).filter(id => id !== VAGA)
      );
      expect(depois.escondidos).toBe(antes.escondidos);
    }
  );

  it('enviado pela plataforma: o mosaico de sempre', () => {
    expect(quadrosDoAlbum(itens(3))).toEqual({
      quadros: itens(3),
      escondidos: 0,
      emQuadrados: false,
    });
  });
});
