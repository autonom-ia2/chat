import {
  comentarioParaTela,
  perfilParaTela,
  postParaTela,
} from '../seusPostsDados';
import { haQuanto, vereditoDoPost } from '../seusPostsHelpers';

// Seus posts (#2304): número que a Meta não mandou continua nulo, nunca 0.
const AGORA = new Date('2026-10-27T12:00:00Z').getTime();
const UM_DIA = 24 * 60 * 60 * 1000;
const em = dias => new Date(AGORA - dias * UM_DIA).toISOString();

describe('Seus posts: postParaTela', () => {
  it('post de 5 dias sem as vezes fica só com curtidas e comentários', () => {
    const post = postParaTela(
      { id: '1', created_time: em(5), views: null, likes: 4 },
      'facebook',
      AGORA
    );
    expect(post).toMatchObject({
      semInsights: true,
      novo: false,
      apareceu: null,
      curtidas: 4,
      comentarios: null,
    });
    expect(vereditoDoPost(post, { apareceu: 100 }).nivel).toBe('NO_INSIGHTS');
  });

  it('post de hoje sem as vezes é novo', () => {
    const post = postParaTela(
      { id: '1', created_time: em(0.2), views: null },
      'instagram',
      AGORA
    );
    expect(post).toMatchObject({ novo: true, semInsights: false });
    expect(vereditoDoPost(post, { apareceu: 100 }).nivel).toBe('NEW');
  });

  it('impulsionado não se compara; sem normal também não', () => {
    const base = { id: '1', created_time: em(5), views: 300 };
    expect(
      vereditoDoPost(
        postParaTela({ ...base, boosted: true }, 'facebook', AGORA),
        {
          apareceu: 100,
        }
      ).nivel
    ).toBe('BOOSTED');
    expect(
      vereditoDoPost(postParaTela(base, 'facebook', AGORA), { apareceu: null })
        .nivel
    ).toBe('NO_NORMAL');
    expect(
      vereditoDoPost(postParaTela(base, 'facebook', AGORA), { apareceu: 100 })
        .nivel
    ).toBe('TIMES');
  });
});

describe('Seus posts: perfilParaTela', () => {
  it('Página: o que pode incluir anúncio e as mensagens do anterior', () => {
    const perfil = perfilParaTela(
      {
        id: 'facebook-2',
        network: 'facebook',
        status: 'ok',
        name: 'Studio Acme',
        views: 900,
        reach: 700,
        followers: 50,
        new_followers: 3,
        previous: { views: 800 },
        inbox_id: 8,
        messages: { count: 4, previous: 6 },
        posts_status: 'ok',
        posts: [],
        normal: { views: 120 },
      },
      null,
      AGORA
    );
    expect(perfil).toMatchObject({
      nome: 'Studio Acme',
      inboxId: 8,
      media: { apareceu: 120 },
    });
    expect(perfil.resumo).toMatchObject({
      apareceuAntes: 800,
      pessoasAntes: null,
      pessoasAte: false,
      mensagens: 4,
      mensagensAntes: 6,
      comparado: true,
      lados: { pessoas: true, interacoes: true, seguidores: true },
    });
  });

  it('Instagram: o nome guardado vence; seguidores novos nulos ficam nulos', () => {
    const perfil = perfilParaTela(
      {
        id: 'instagram-1',
        network: 'instagram',
        status: 'ok',
        username: 'studioacme',
        new_followers: null,
        previous: null,
        posts_status: 'ok',
        posts: [],
        normal: {},
      },
      '@nomeguardado',
      AGORA
    );
    expect(perfil.nome).toBe('@nomeguardado');
    expect(perfil.resumo).toMatchObject({
      seguidoresNovos: null,
      pessoasAte: true,
      comparado: false,
      lados: { pessoas: false, interacoes: false, seguidores: true },
    });
  });

  it('números lidos mas posts recusados: os números ficam e só a grade pede a liberação', () => {
    const tela = perfilParaTela(
      {
        id: 'instagram-1',
        network: 'instagram',
        status: 'ok',
        views: 5200,
        posts_status: 'needs_permission',
        inbox_id: 7,
      },
      null,
      AGORA
    );
    expect(tela).toMatchObject({
      status: 'ok',
      postsStatus: 'needs_permission',
      inboxId: 7,
    });
    expect(tela.resumo.apareceu).toBe(5200);
  });

  it('link que não é https não vira link', () => {
    const tela = perfilParaTela(
      {
        id: 'instagram-1',
        network: 'instagram',
        status: 'ok',
        link: 'data:text/html,oi',
        posts_status: 'ok',
        posts: [{ id: 'a', permalink: 'http://instagram.com/p/a' }],
      },
      null,
      AGORA
    );
    expect(tela.link).toBeNull();
    expect(tela.posts[0].link).toBeNull();
  });
});

// F2 (#2305): o estado de cada comentário e quem espera no cartão.
describe('Seus posts: comentarioParaTela', () => {
  const base = { id: 'c', text: 'Oi', author: { username: 'pessoa' } };

  it.each([
    [{ author: { name: 'Loja', is_page: true } }, 'meu'],
    [{ hidden: true }, 'escondido'],
    [{ private_reply: { sent_at: em(1), confirmed: true } }, 'privado'],
    [{ replies: [{ id: 'r', author: { is_page: true } }] }, 'respondido'],
    [{ replies: [{ id: 'r', author: { username: 'outra' } }] }, 'esperando'],
    [{}, 'esperando'],
  ])('%o vira %s', (extra, estado) => {
    expect(comentarioParaTela({ ...base, ...extra }).estado).toBe(estado);
  });

  it('autor do Instagram ganha @; botões só com o que o servidor deixa', () => {
    const tela = comentarioParaTela({ ...base, can_reply: true });
    expect(tela.autor).toBe('@pessoa');
    expect(tela.pode).toEqual({
      responder: true,
      esconder: false,
      apagar: false,
      privado: false,
    });
  });
});

describe('Seus posts: quem espera no post', () => {
  it('sem a contagem (flag desligada) fica nulo, nunca 0', () => {
    const post = postParaTela(
      { id: '1', created_time: em(5) },
      'instagram',
      AGORA
    );
    expect(post.esperando).toBeNull();
    expect(post.esperandoMais).toBe(false);
  });

  it('com mais de 50 comentários, marca o "ou mais"', () => {
    const post = postParaTela(
      {
        id: '1',
        created_time: em(5),
        waiting: 50,
        waiting_more: true,
        shares: 3,
      },
      'instagram',
      AGORA
    );
    expect(post).toMatchObject({
      esperando: 50,
      esperandoMais: true,
      compartilharam: 3,
    });
  });
});

describe('Seus posts: haQuanto', () => {
  it('comentário sem data não derruba a lista', () => {
    expect(haQuanto(undefined, 'pt_BR')).toBe('');
    expect(haQuanto('não é data', 'pt_BR')).toBe('');
  });
});
