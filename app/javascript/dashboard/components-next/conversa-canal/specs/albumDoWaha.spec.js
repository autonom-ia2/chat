import {
  JANELA_DO_ALBUM_EM_SEGUNDOS,
  VAGA,
  agruparDaConversa,
  quadrosDoAlbum,
} from '../album/agruparAlbuns';
import {
  contagemDoWaha,
  eMarcadorDoWaha,
  paraOBalao,
} from '../album/albumDoWaha';

// #1831: o marcador do WAHA traz waha_album = { expected_images, expected_videos }.
const FUSO = 'America/Sao_Paulo';
const BASE = Date.UTC(2026, 9, 18, 17, 3, 26) / 1000;
const CONTATO = { id: 7, name: 'Cliente' };

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
  sender: { id: 7, type: 'contact' },
  createdAt: BASE,
  status: 'sent',
  content: null,
  contentAttributes: {},
  attachments: [{ fileType: 'image', dataUrl: 'https://x.test/a.jpg' }],
  ...extras,
});
const texto = (extras = {}) =>
  foto({ content: 'oi', attachments: [], ...extras });
// Com a flag do #1741: atividade escondida, sem remetente. Sem ela: recebida comum.
const doWaha = (formato, extras = {}) =>
  texto({
    content: null,
    messageType: formato === 'atividade' ? 2 : 0,
    senderId: formato === 'atividade' ? null : 7,
    senderType: formato === 'atividade' ? null : 'Contact',
    sender: formato === 'atividade' ? null : { id: 7, type: 'contact' },
    contentAttributes: {
      wahaAlbum: { expectedImages: 3, expectedVideos: 1 },
      ...(formato === 'atividade' ? { c2yHidden: true } : {}),
    },
    ...extras,
  });
// Como a MessageList entrega a lista: o marcador já como balão do contato.
const agrupar = (lista, agora) =>
  agruparDaConversa(
    lista.map(mensagem => paraOBalao(mensagem, CONTATO)),
    { fuso: FUSO, agora }
  );
const ids = quadros => quadros.map(quadro => quadro?.id ?? VAGA);

describe('marcador do WAHA (#1831)', () => {
  it('a contagem soma fotos e vídeos; 1 só ou sem a chave não é marcador', () => {
    expect(contagemDoWaha(doWaha('recebida'))).toBe(4);
    expect(eMarcadorDoWaha(doWaha('recebida'))).toBe(true);
    expect(eMarcadorDoWaha(doWaha('atividade'))).toBe(true);
    expect(eMarcadorDoWaha(texto())).toBe(false);
    expect(eMarcadorDoWaha(doWaha('recebida', { private: true }))).toBe(false);
    const umSo = doWaha('recebida', {
      contentAttributes: {
        wahaAlbum: { expectedImages: 1, expectedVideos: 0 },
      },
    });
    expect(contagemDoWaha(umSo)).toBeNull();
  });

  it('na tela, a atividade vira o balão do contato com o aviso da Cloud', () => {
    const balao = paraOBalao(doWaha('atividade'), CONTATO);
    expect(balao).toMatchObject({
      messageType: 0,
      senderId: 7,
      senderType: 'Contact',
      sender: { id: 7, type: 'contact' },
    });
    expect(balao.contentAttributes).toMatchObject({
      isUnsupported: true,
      unsupportedKind: 'unknown',
    });
    const comum = texto();
    expect(paraOBalao(comum, CONTATO)).toBe(comum);
  });
});

describe('álbum do WAHA chegando, com a contagem (#1831)', () => {
  it.each(['recebida', 'atividade'])(
    'marcador %s com contagem parcial: o mosaico final já nasce e espera o resto',
    formato => {
      const pai = doWaha(formato);
      const fotos = [1, 2].map(s => foto({ createdAt: BASE + s }));
      const { albuns, marcadores, chegadas, emQuadrados } = agrupar(
        [pai, ...fotos],
        BASE + 3
      );
      expect(albuns.get(fotos[0].id)).toEqual(fotos);
      expect([...marcadores]).toEqual([pai.id]);
      expect(emQuadrados.size).toBe(0);
      const chegada = chegadas.get(fotos[0].id);
      expect(chegada.esperados).toBe(4);
      const mosaico = quadrosDoAlbum(fotos, {
        chegando: true,
        esperados: chegada.esperados,
      });
      expect(ids(mosaico.quadros)).toEqual([
        fotos[0].id,
        fotos[1].id,
        VAGA,
        VAGA,
      ]);
    }
  );

  it('o marcador sozinho abre o álbum com a contagem, no próprio balão', () => {
    const pai = doWaha('atividade');
    const { albuns, chegadas } = agrupar([pai], BASE + 1);
    expect(albuns.get(pai.id)).toEqual([]);
    expect(chegadas.get(pai.id)).toMatchObject({
      esperados: 4,
      noMarcador: true,
    });
  });

  it('chegou tudo antes da janela: pronto, no mesmo mosaico, sem reservado', () => {
    const pai = doWaha('atividade');
    const fotos = [1, 2, 3, 4].map(s => foto({ createdAt: BASE + s }));
    const { albuns, chegadas, emQuadrados } = agrupar(
      [pai, ...fotos],
      BASE + 5
    );
    expect(albuns.get(fotos[0].id)).toEqual(fotos);
    expect(chegadas.size).toBe(0);
    expect(emQuadrados.size).toBe(0);
    const antes = quadrosDoAlbum(fotos.slice(0, 3), {
      chegando: true,
      esperados: 4,
    });
    const depois = quadrosDoAlbum(fotos);
    expect(antes.quadros).toHaveLength(depois.quadros.length);
  });

  it('com 5 anunciadas, o reservado do 4º quadro entra no "+N"', () => {
    const mosaico = quadrosDoAlbum([foto(), foto()], {
      chegando: true,
      esperados: 5,
    });
    expect(mosaico.quadros).toHaveLength(4);
    expect(mosaico.escondidos).toBe(2);
  });

  it('janela fechada antes de chegar tudo: sai o "Recebendo"', () => {
    const pai = doWaha('recebida');
    const fotos = [1, 2].map(s => foto({ createdAt: BASE + s }));
    const { albuns, chegadas } = agrupar(
      [pai, ...fotos],
      BASE + JANELA_DO_ALBUM_EM_SEGUNDOS + 1
    );
    expect(albuns.get(fotos[0].id)).toEqual(fotos);
    expect(chegadas.size).toBe(0);
  });
});
