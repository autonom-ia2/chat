import {
  FORMAS,
  IDADE_DO_MARCADOR_RECENTE_EM_SEGUNDOS,
  JANELA_DO_ALBUM_EM_SEGUNDOS,
  VAGA,
  agruparDaConversa,
  formaDoQuadro,
  quadrosDoAlbum,
} from '../album/agruparAlbuns';
import {
  MAXIMO_DO_ALBUM,
  contagemDoWaha,
  eMarcadorDoWaha,
  paraOBalao,
  temMarcaDoWaha,
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
const agrupar = (lista, agora, extras = {}) =>
  agruparDaConversa(
    lista.map(mensagem => paraOBalao(mensagem, CONTATO)),
    { fuso: FUSO, agora, ...extras }
  );
const ids = quadros => quadros.map(quadro => quadro?.id ?? VAGA);
// Os quadros completos: o que ocupa cada posição (VAGA = reservado) e a forma.
const grade = mosaico =>
  mosaico.quadros.map((quadro, posicao) => [
    quadro?.id ?? VAGA,
    formaDoQuadro(mosaico, posicao),
  ]);
const { QUADRADO, ALTO, LARGO } = FORMAS;
const comContagem = (expectedImages, expectedVideos, formato = 'atividade') =>
  doWaha(formato, {
    contentAttributes: {
      wahaAlbum: { expectedImages, expectedVideos },
      ...(formato === 'atividade' ? { c2yHidden: true } : {}),
    },
  });
const video = (extras = {}) =>
  foto({
    attachments: [{ fileType: 'video', dataUrl: 'https://x.test/v.mp4' }],
    ...extras,
  });
const FECHADA = BASE + JANELA_DO_ALBUM_EM_SEGUNDOS + 1;

describe('marcador do WAHA (#1831)', () => {
  it('a contagem soma fotos e vídeos; sem a chave não é marcador', () => {
    expect(contagemDoWaha(doWaha('recebida'))).toBe(4);
    expect(eMarcadorDoWaha(doWaha('recebida'))).toBe(true);
    expect(eMarcadorDoWaha(doWaha('atividade'))).toBe(true);
    expect(eMarcadorDoWaha(texto())).toBe(false);
    expect(eMarcadorDoWaha(doWaha('recebida', { private: true }))).toBe(false);
    expect(contagemDoWaha(comContagem(1, 0))).toBe(1);
    expect(contagemDoWaha(comContagem(undefined, 2))).toBe(2);
  });

  it.each([
    ['texto', '3', 0],
    ['fração', 2.5, 0],
    ['negativa', -1, 3],
    ['acima do teto', MAXIMO_DO_ALBUM + 1, 0],
    ['vídeo acima do teto', 2, MAXIMO_DO_ALBUM + 1],
    ['soma zero', 0, 0],
    ['nula nas duas', null, null],
  ])('contagem inválida (%s): não há álbum', (_caso, fotos, videos) => {
    const pai = comContagem(fotos, videos);
    expect(contagemDoWaha(pai)).toBeNull();
    expect(eMarcadorDoWaha(pai)).toBe(false);
    expect(temMarcaDoWaha(pai)).toBe(true);
    const soltas = [1, 2].map(s => foto({ createdAt: BASE + s }));
    const { albuns, marcadores, chegadas } = agrupar(
      [pai, ...soltas],
      BASE + 3
    );
    expect(albuns.size).toBe(0);
    expect(chegadas.size).toBe(0);
    expect([...marcadores]).toEqual([pai.id]);
  });

  it('o teto é por contagem: 100 fotos e 100 vídeos ainda é álbum', () => {
    expect(contagemDoWaha(comContagem(MAXIMO_DO_ALBUM, MAXIMO_DO_ALBUM))).toBe(
      2 * MAXIMO_DO_ALBUM
    );
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

  it('sem remetente (conversa sem meta.sender): o marcador some e as fotos ficam soltas', () => {
    const pai = doWaha('atividade');
    const fotos = [1, 2].map(s => foto({ createdAt: BASE + s }));
    const { albuns, marcadores, chegadas } = agruparDaConversa(
      [pai, ...fotos].map(mensagem => paraOBalao(mensagem, undefined)),
      { fuso: FUSO, agora: BASE + 3 }
    );
    expect(albuns.size).toBe(0);
    expect(chegadas.size).toBe(0);
    expect([...marcadores]).toEqual([pai.id]);
  });
});

describe('álbum do WAHA: o balão é o do marcador, na grade anunciada (#1831)', () => {
  it.each(['recebida', 'atividade'])(
    'marcador %s com 2 de 4, chegando: grade de 4, chave do marcador',
    formato => {
      const pai = doWaha(formato);
      const fotos = [1, 2].map(s => foto({ createdAt: BASE + s }));
      const { albuns, marcadores, chegadas, emQuadrados, anunciados } = agrupar(
        [pai, ...fotos],
        BASE + 3
      );
      expect(albuns.get(pai.id)).toEqual(fotos);
      expect(marcadores.size).toBe(0);
      expect(emQuadrados.size).toBe(0);
      expect(anunciados.get(pai.id)).toBe(4);
      expect(chegadas.get(pai.id)).toEqual({
        esperados: 4,
        noMarcador: true,
        ate: BASE + JANELA_DO_ALBUM_EM_SEGUNDOS,
      });
      const mosaico = quadrosDoAlbum(fotos, { chegando: true, esperados: 4 });
      expect(grade(mosaico)).toEqual([
        [fotos[0].id, QUADRADO],
        [fotos[1].id, QUADRADO],
        [VAGA, QUADRADO],
        [VAGA, QUADRADO],
      ]);
      expect(mosaico.escondidos).toBe(0);
    }
  );

  it('janela fechada com 2 de 4: a mesma grade fica, sem "Recebendo"', () => {
    const pai = doWaha('atividade');
    const fotos = [1, 2].map(s => foto({ createdAt: BASE + s }));
    const { albuns, chegadas, anunciados } = agrupar([pai, ...fotos], FECHADA);
    expect(albuns.get(pai.id)).toEqual(fotos);
    expect(chegadas.size).toBe(0);
    expect(anunciados.get(pai.id)).toBe(4);
    const chegando = quadrosDoAlbum(fotos, { chegando: true, esperados: 4 });
    const fechado = quadrosDoAlbum(fotos, { chegando: false, esperados: 4 });
    expect(grade(fechado)).toEqual(grade(chegando));
    expect(grade(fechado)).toEqual([
      [fotos[0].id, QUADRADO],
      [fotos[1].id, QUADRADO],
      [VAGA, QUADRADO],
      [VAGA, QUADRADO],
    ]);
  });

  it('3 anunciadas: grade de 3 (1ª larga) chegando e pronta, sem mudar', () => {
    const pai = comContagem(3, 0);
    const fotos = [1, 2, 3].map(s => foto({ createdAt: BASE + s }));
    const esperado = [
      [fotos[0].id, LARGO],
      [VAGA, QUADRADO],
      [VAGA, QUADRADO],
    ];
    const antes = quadrosDoAlbum(fotos.slice(0, 1), {
      chegando: true,
      esperados: 3,
    });
    expect(grade(antes)).toEqual(esperado);
    const { albuns, chegadas } = agrupar([pai, ...fotos], BASE + 4);
    expect(albuns.get(pai.id)).toEqual(fotos);
    expect(chegadas.size).toBe(0);
    const depois = quadrosDoAlbum(fotos, { esperados: 3 });
    expect(grade(depois)).toEqual([
      [fotos[0].id, LARGO],
      [fotos[1].id, QUADRADO],
      [fotos[2].id, QUADRADO],
    ]);
  });

  it('2 anunciadas: as duas em pé, chegando e prontas', () => {
    const fotos = [foto(), foto()];
    expect(
      grade(quadrosDoAlbum(fotos.slice(0, 1), { chegando: true, esperados: 2 }))
    ).toEqual([
      [fotos[0].id, ALTO],
      [VAGA, ALTO],
    ]);
    expect(grade(quadrosDoAlbum(fotos, { esperados: 2 }))).toEqual([
      [fotos[0].id, ALTO],
      [fotos[1].id, ALTO],
    ]);
  });

  it('o marcador sozinho abre o álbum com a contagem, no próprio balão', () => {
    const pai = doWaha('atividade');
    const { albuns, chegadas, marcadores } = agrupar([pai], BASE + 1);
    expect(albuns.get(pai.id)).toEqual([]);
    expect(marcadores.size).toBe(0);
    expect(chegadas.get(pai.id)).toMatchObject({
      esperados: 4,
      noMarcador: true,
    });
  });

  it('com 1 foto e a janela fechada: a grade não encolhe', () => {
    const pai = doWaha('atividade');
    const uma = foto({ createdAt: BASE + 1 });
    const { albuns, chegadas } = agrupar([pai, uma], FECHADA);
    expect(albuns.get(pai.id)).toEqual([uma]);
    expect(chegadas.size).toBe(0);
    expect(ids(quadrosDoAlbum([uma], { esperados: 4 }).quadros)).toEqual([
      uma.id,
      VAGA,
      VAGA,
      VAGA,
    ]);
  });

  it('sem foto e a janela fechada: o marcador fica à vista, sem álbum', () => {
    const pai = doWaha('atividade');
    const { albuns, marcadores, chegadas } = agrupar([pai], FECHADA);
    expect(albuns.size).toBe(0);
    expect(marcadores.size).toBe(0);
    expect(chegadas.size).toBe(0);
  });

  it('com 5 anunciadas, o reservado do 4º quadro entra no "+N"', () => {
    const mosaico = quadrosDoAlbum([foto(), foto()], {
      chegando: true,
      esperados: 5,
    });
    expect(mosaico.quadros).toHaveLength(4);
    expect(mosaico.escondidos).toBe(2);
  });

  it('foto atrasada (depois da janela, até 30 s da anterior) ocupa a vaga', () => {
    const pai = doWaha('atividade');
    const a = foto({ createdAt: BASE + 20 });
    const atrasada = foto({ createdAt: BASE + 45 });
    const { albuns } = agrupar([pai, a, atrasada], BASE + 46);
    expect(albuns.get(pai.id)).toEqual([a, atrasada]);
  });

  it('foto bem depois (mais de 30 s da anterior) fica solta', () => {
    const pai = doWaha('atividade');
    const a = foto({ createdAt: BASE + 5 });
    const tarde = foto({ createdAt: BASE + 120 });
    const { albuns, marcadores } = agrupar([pai, a, tarde], BASE + 121);
    expect(albuns.get(pai.id)).toEqual([a]);
    expect(marcadores.has(tarde.id)).toBe(false);
  });
});

describe('álbum do WAHA: limites (#1831 com o #1741)', () => {
  it('para na quantidade anunciada: a foto seguinte fica solta', () => {
    const pai = comContagem(2, 0);
    const fotos = [1, 2, 3].map(s => foto({ createdAt: BASE + s }));
    const { albuns } = agrupar([pai, ...fotos], BASE + 4);
    expect(albuns.get(pai.id)).toEqual(fotos.slice(0, 2));
    expect(albuns.has(fotos[2].id)).toBe(false);
  });

  it('vídeo misto no teto: 2 fotos + 1 vídeo, a 4ª mídia fica solta', () => {
    const pai = comContagem(2, 1);
    const itens = [
      foto({ createdAt: BASE + 1 }),
      video({ createdAt: BASE + 2 }),
      foto({ createdAt: BASE + 3 }),
    ];
    const sobra = video({ createdAt: BASE + 4 });
    const { albuns, chegadas } = agrupar([pai, ...itens, sobra], BASE + 5);
    expect(albuns.get(pai.id)).toEqual(itens);
    expect(albuns.has(sobra.id)).toBe(false);
    expect(chegadas.size).toBe(0);
  });

  it('duas mensagens nossas depois do marcador: nenhuma entra, a grade fica', () => {
    const pai = doWaha('atividade');
    const nossa = extras =>
      foto({
        messageType: 1,
        senderId: 1,
        senderType: 'User',
        sender: { id: 1, type: 'user' },
        ...extras,
      });
    // Separadas por mais de 3 s: não formam um envio da plataforma entre si.
    const n1 = nossa({ createdAt: BASE + 1 });
    const n2 = nossa({ createdAt: BASE + 10 });
    const { albuns, marcadores } = agrupar([pai, n1, n2], FECHADA);
    expect(albuns.size).toBe(0);
    expect(marcadores.has(n1.id)).toBe(false);
    expect(marcadores.has(n2.id)).toBe(false);
    const chegando = agrupar([pai, n1, n2], BASE + 11);
    expect([...chegando.albuns.entries()]).toEqual([[pai.id, []]]);
    expect(chegando.chegadas.get(pai.id).esperados).toBe(4);
  });

  it('item recusado (com citação) não ocupa vaga e fica solto', () => {
    const pai = doWaha('atividade');
    const a = foto({ createdAt: BASE + 1 });
    const citada = foto({
      createdAt: BASE + 2,
      contentAttributes: { inReplyTo: 99 },
    });
    const { albuns, marcadores } = agrupar([pai, a, citada], FECHADA);
    expect(albuns.get(pai.id)).toEqual([a]);
    expect(marcadores.has(citada.id)).toBe(false);
    expect(ids(quadrosDoAlbum([a], { esperados: 4 }).quadros)).toEqual([
      a.id,
      VAGA,
      VAGA,
      VAGA,
    ]);
  });

  it.each(['recebida', 'atividade'])(
    'em grupo o marcador %s só some: as fotos ficam soltas',
    formato => {
      const pai = doWaha(formato);
      const fotos = [1, 2].map(s => foto({ createdAt: BASE + s }));
      const { albuns, marcadores, chegadas } = agrupar(
        [pai, ...fotos],
        BASE + 3,
        { grupo: true }
      );
      expect(albuns.size).toBe(0);
      expect(chegadas.size).toBe(0);
      expect([...marcadores]).toEqual([pai.id]);
    }
  );

  it('em grupo, chegando (marcador sozinho): não abre álbum', () => {
    const pai = doWaha('atividade');
    const { albuns, marcadores, chegadas } = agrupar([pai], BASE + 1, {
      grupo: true,
    });
    expect(albuns.size).toBe(0);
    expect(chegadas.size).toBe(0);
    expect([...marcadores]).toEqual([pai.id]);
  });
});

describe('janela pelo relógio do navegador (#1831)', () => {
  it('relógio atrasado: fecha 30 s depois que a tela viu o marcador', () => {
    const pai = doWaha('atividade');
    const a = foto({ createdAt: BASE + 1 });
    const visto = BASE - 600;
    const vistoEm = () => visto;
    // O navegador está 10 min atrás: pela idade, o álbum chegaria para sempre.
    const aberta = agrupar([pai, a], visto + 10, { vistoEm });
    expect(aberta.chegadas.get(pai.id).ate).toBe(
      visto + JANELA_DO_ALBUM_EM_SEGUNDOS
    );
    const fechada = agrupar([pai, a], visto + 31, { vistoEm });
    expect(fechada.chegadas.size).toBe(0);
    expect(fechada.albuns.get(pai.id)).toEqual([a]);
  });

  it('relógio adiantado, sem foto: só vira "não carregada" 30 s depois de visto', () => {
    const pai = doWaha('atividade');
    // 2 min adiantado: o marcador ainda é recente.
    const visto = BASE + 120;
    const vistoEm = () => visto;
    const logo = agrupar([pai], visto + 5, { vistoEm });
    expect(logo.albuns.get(pai.id)).toEqual([]);
    expect(logo.chegadas.get(pai.id).ate).toBe(
      visto + JANELA_DO_ALBUM_EM_SEGUNDOS
    );
    const depois = agrupar([pai], visto + 31, { vistoEm });
    expect(depois.albuns.size).toBe(0);
    expect(depois.marcadores.size).toBe(0);
  });

  it('relógio adiantado, com foto: a janela já fechou e a grade fica', () => {
    const pai = doWaha('atividade');
    const a = foto({ createdAt: BASE + 1 });
    const visto = BASE + 120;
    const { albuns, chegadas } = agrupar([pai, a], visto + 1, {
      vistoEm: () => visto,
    });
    expect(albuns.get(pai.id)).toEqual([a]);
    expect(chegadas.size).toBe(0);
  });

  it('Cloud: o marcador sem foto também espera 30 s à vista', () => {
    const pai = texto({
      content: null,
      contentAttributes: { isUnsupported: true, unsupportedKind: 'unknown' },
    });
    const visto = BASE + 120;
    const logo = agruparDaConversa([pai], {
      fuso: FUSO,
      agora: visto + 5,
      vistoEm: () => visto,
    });
    expect(logo.chegadas.get(pai.id)).toEqual({
      esperados: null,
      noMarcador: true,
      ate: visto + JANELA_DO_ALBUM_EM_SEGUNDOS,
    });
  });

  // Conversa antiga: idade (relógio do navegador) a partir de 5 min.
  const ANTIGA = BASE + IDADE_DO_MARCADOR_RECENTE_EM_SEGUNDOS;

  it('conversa antiga, WAHA sem foto: já é "mensagem não carregada", sem esperar', () => {
    const pai = doWaha('atividade');
    const { albuns, marcadores, chegadas } = agrupar([pai], ANTIGA, {
      vistoEm: () => ANTIGA,
    });
    expect(albuns.size).toBe(0);
    expect(marcadores.size).toBe(0);
    expect(chegadas.size).toBe(0);
  });

  it('conversa antiga, Cloud sem foto: já é "mensagem não carregada", sem esperar', () => {
    const pai = texto({
      content: null,
      contentAttributes: { isUnsupported: true, unsupportedKind: 'unknown' },
    });
    const { albuns, marcadores, chegadas } = agruparDaConversa([pai], {
      fuso: FUSO,
      agora: ANTIGA,
      vistoEm: () => ANTIGA,
    });
    expect(albuns.size).toBe(0);
    expect(marcadores.size).toBe(0);
    expect(chegadas.size).toBe(0);
  });

  it('conversa antiga com 2 de 4: a grade fica, sem "Recebendo"', () => {
    const pai = doWaha('atividade');
    const fotos = [1, 2].map(s => foto({ createdAt: BASE + s }));
    const { albuns, chegadas } = agrupar([pai, ...fotos], ANTIGA, {
      vistoEm: () => ANTIGA,
    });
    expect(albuns.get(pai.id)).toEqual(fotos);
    expect(chegadas.size).toBe(0);
  });

  it('um pouco antes de 5 min, ainda recente: espera 30 s à vista', () => {
    const pai = doWaha('atividade');
    const quase = ANTIGA - 1;
    const { chegadas } = agrupar([pai], quase, { vistoEm: () => quase });
    expect(chegadas.get(pai.id).ate).toBe(quase + JANELA_DO_ALBUM_EM_SEGUNDOS);
  });
});
