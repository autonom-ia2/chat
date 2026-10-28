import { perfilParaTela, postParaTela } from '../seusPostsDados';
import { vereditoDoPost } from '../seusPostsHelpers';

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

  it('números lidos mas posts recusados: pede a mesma liberação', () => {
    expect(
      perfilParaTela(
        {
          id: 'instagram-1',
          network: 'instagram',
          status: 'ok',
          posts_status: 'needs_permission',
          inbox_id: 7,
        },
        null,
        AGORA
      )
    ).toMatchObject({ status: 'needs_permission', inboxId: 7 });
  });
});
