import { flushPromises, mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/seusPosts.json';
import SeusPostsPage from '../pages/SeusPostsPage.vue';
import SeusPostsAPI from 'dashboard/api/seusPosts';
import FBChannel from 'dashboard/api/channel/fbChannel';
import instagramClient from 'dashboard/api/channel/instagramClient';

// Seus posts (#2302, F1 #2304): a página com o que GET seus_posts manda. Dados sintéticos.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/seusPosts', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/channel/fbChannel', () => ({
  default: { reauthorizeFacebookPage: vi.fn() },
}));
vi.mock('dashboard/api/channel/instagramClient', () => ({
  default: { generateAuthorization: vi.fn() },
}));
const login = vi.fn();
vi.mock('dashboard/composables/useFacebookPageConnect', () => ({
  useFacebookPageConnect: () => ({
    preloadSdk: () => Promise.resolve(),
    login,
  }),
}));
const granted = ref([]);
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    usePermissionGranted: key => computed(() => granted.value.includes(key)),
  };
});
// F2 (#2305): a flag dos comentários muda o que o "Liberar acesso" pede à Meta.
const flags = ref([]);
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flags.value.includes(flag),
  }),
}));
const route = reactive({ query: {}, params: { accountId: 1 } });
const push = vi.fn();
const replace = vi.fn(({ query }) => {
  route.query = query;
});
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push, replace }),
}));

const UM_DIA = 24 * 60 * 60 * 1000;
const haDias = dias => new Date(Date.now() - dias * UM_DIA).toISOString();

const post = (id, extra = {}) => ({
  id,
  text: `Post ${id}`,
  type: 'foto',
  image_url: null,
  permalink: `https://www.instagram.com/p/${id}`,
  created_time: haDias(5),
  boosted: false,
  views: 400,
  reach: 300,
  likes: 20,
  comments: 3,
  ...extra,
});

const instagram = (extra = {}) => ({
  id: 'instagram-1',
  network: 'instagram',
  status: 'ok',
  username: 'studioacme',
  link: 'https://www.instagram.com/studioacme',
  followers: 2300,
  reach: 1800,
  views: 5200,
  interactions: 410,
  new_followers: 35,
  previous: { reach: 1500, views: 4000, interactions: 380, new_followers: 20 },
  inbox_id: 7,
  messages: { count: 12, previous: 9 },
  posts_status: 'ok',
  posts: [post('a', { views: 1200 }), post('b')],
  normal: { views: 400, likes: 20, comments: 3 },
  ...extra,
});

const responder = (perfil, perfis) =>
  SeusPostsAPI.get.mockResolvedValue({
    data: {
      days: 30,
      from: '2026-09-28',
      to: '2026-10-27',
      perfil,
      perfis: perfis || [
        { id: perfil.id, network: perfil.network, name: '@studioacme' },
      ],
    },
  });

// A rota é uma só para todos os testes: a página de um teste não pode seguir viva no seguinte.
const montadas = [];
const montar = async () => {
  const wrapper = mount(SeusPostsPage, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ],
      stubs: {
        ChoiceSelect: true,
        RouterLink: {
          props: ['to'],
          template: '<a :data-para="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};

describe('Seus posts (#2304)', () => {
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  beforeEach(() => {
    vi.clearAllMocks();
    // O jsdom não rola a página.
    Element.prototype.scrollIntoView = vi.fn();
    route.query = {};
    granted.value = ['integration_manage', 'inbox_manage'];
    flags.value = [];
    delete window.location;
    window.location = { href: '' };
  });

  it('pede 30 dias e o primeiro perfil quando o endereço não diz', async () => {
    responder(instagram());
    await montar();
    expect(SeusPostsAPI.get).toHaveBeenCalledWith({
      perfil: undefined,
      days: 30,
    });
  });

  it('mostra a frase, a comparação e os quatro números', async () => {
    responder(instagram());
    const wrapper = await montar();

    const heroi = wrapper.find('[data-seus-posts-heroi]').text();
    expect(heroi).toContain('5.200 vezes sem anúncio');
    expect(heroi).toContain('1.200 a mais que nos 30 dias anteriores');
    const quadros = wrapper.findAll('[data-seus-posts-quadro]');
    expect(quadros.map(q => q.attributes('data-seus-posts-quadro'))).toEqual([
      'people',
      'interactions',
      'followers',
      'messages',
    ]);
    // No Instagram, quem viu é o teto.
    expect(quadros[0].text()).toContain('até 1.800');
    expect(quadros[3].text()).toContain('3 a mais');
  });

  it('sem ver a caixa, sem o quadro de mensagens nem "Ver conversas"', async () => {
    responder(instagram({ messages: { count: null, previous: null } }));
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-quadro="messages"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-seus-posts-ver-conversas]').exists()).toBe(
      false
    );
  });

  it('cada post contra o normal, o destaque e o link para a rede', async () => {
    responder(instagram());
    const wrapper = await montar();

    const melhor = wrapper.find('[data-seus-posts-card="a"]');
    expect(melhor.find('[data-seus-posts-veredito]').text()).toBe(
      '3 vezes o normal'
    );
    expect(melhor.find('[data-seus-posts-destaque]').exists()).toBe(true);
    expect(melhor.find('[data-seus-posts-abrir="a"]').attributes('href')).toBe(
      'https://www.instagram.com/p/a'
    );
    expect(
      wrapper
        .find('[data-seus-posts-card="b"] [data-seus-posts-veredito]')
        .text()
    ).toBe('Perto do normal');
  });

  it('post novo sem as vezes: sem veredito, com as curtidas e os comentários que já vieram', async () => {
    responder(
      instagram({
        posts: [
          post('novo', {
            views: null,
            comments: null,
            created_time: haDias(0.5),
          }),
        ],
      })
    );
    const wrapper = await montar();

    const cartao = wrapper.find('[data-seus-posts-card="novo"]');
    expect(cartao.find('[data-seus-posts-sem-numeros]').exists()).toBe(true);
    expect(cartao.find('[data-seus-posts-veredito]').exists()).toBe(false);
    const rotulos = cartao.findAll('dt').map(dt => dt.text());
    expect(rotulos).toEqual(['Curtidas']);
  });

  it('posts recusados: os números do perfil ficam e a grade pede a liberação', async () => {
    responder(instagram({ posts_status: 'needs_permission', posts: [] }));
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-heroi]').exists()).toBe(true);
    expect(wrapper.find('[data-seus-posts-sem-permissao]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-seus-posts-posts-sem-permissao]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-seus-posts-sem-post]').exists()).toBe(false);
  });

  it('posts da última leitura boa: a grade avisa', async () => {
    responder(instagram({ posts_stale: true }));
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-posts-antigos]').exists()).toBe(true);
  });

  it('seguidores negativos não viram "-3 começaram": "3 deixaram de seguir", descendo', async () => {
    responder(instagram({ new_followers: -3 }));
    const wrapper = await montar();

    const quadro = wrapper.find('[data-seus-posts-quadro="followers"]').text();
    expect(quadro).toContain('3 deixaram de seguir');
    expect(quadro).not.toContain('-3');
  });

  it('seguidores que a Meta não mandou: "—", sem o aviso de poucos seguidores', async () => {
    responder(instagram({ followers: null, new_followers: null }));
    const wrapper = await montar();

    const quadro = wrapper.find('[data-seus-posts-quadro="followers"]').text();
    expect(quadro).toContain('—');
    expect(quadro).not.toContain('Com 100 seguidores');
  });

  it('menos de 100 seguidores: o aviso no lugar de quem começou a seguir', async () => {
    responder(instagram({ followers: 80, new_followers: null }));
    const wrapper = await montar();

    expect(
      wrapper.find('[data-seus-posts-quadro="followers"]').text()
    ).toContain('Com 100 seguidores');
  });

  it('pessoas que a Meta não mandou: só "—", nunca "até —"', async () => {
    responder(instagram({ reach: null }));
    const wrapper = await montar();

    const quadro = wrapper.find('[data-seus-posts-quadro="people"]').text();
    expect(quadro).toContain('—');
    expect(quadro).not.toContain('até');
  });

  it('o destaque "sem anúncio" só vai para post que se sabe sem anúncio', async () => {
    responder(
      instagram({
        posts: [
          post('pago', { views: 5000, boosted: true }),
          post('nao-se-sabe', { views: 3000, boosted: null }),
          post('organico', { views: 900, boosted: false }),
        ],
      })
    );
    const wrapper = await montar();

    const destacado = wrapper.find('[data-seus-posts-destaque]');
    expect(destacado.exists()).toBe(true);
    expect(
      wrapper
        .find('[data-seus-posts-card="organico"] [data-seus-posts-destaque]')
        .exists()
    ).toBe(true);
    expect(wrapper.findAll('[data-seus-posts-destaque]')).toHaveLength(1);
  });

  it('megafone nas curtidas quando não se sabe se teve anúncio; sem ele quando se sabe que não', async () => {
    responder(
      instagram({
        posts: [
          post('nao-se-sabe', { boosted: null }),
          post('organico', { boosted: false }),
        ],
      })
    );
    const wrapper = await montar();

    const marcas = id =>
      wrapper.findAll(
        `[data-seus-posts-card="${id}"] [data-seus-posts-marca-anuncio]`
      );
    expect(marcas('nao-se-sabe').length).toBeGreaterThan(0);
    expect(marcas('organico')).toHaveLength(0);
  });

  it('403 é "sem acesso", não erro de rede', async () => {
    SeusPostsAPI.get.mockRejectedValue({ response: { status: 403 } });
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-sem-acesso]').exists()).toBe(true);
    expect(wrapper.find('[data-seus-posts-erro]').exists()).toBe(false);
  });

  it('falha de rede mostra "Tentar de novo"', async () => {
    SeusPostsAPI.get.mockRejectedValue(new Error('Network Error'));
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-erro]').exists()).toBe(true);
  });

  it('perfil do endereço que sumiu volta para o primeiro', async () => {
    route.query = { perfil: 'instagram-99' };
    SeusPostsAPI.get.mockRejectedValueOnce({ response: { status: 404 } });
    responder(instagram());
    await montar();

    expect(SeusPostsAPI.get).toHaveBeenLastCalledWith({
      perfil: undefined,
      days: 30,
    });
  });

  it('Meta fora no perfil: "Tentar de novo" só nele', async () => {
    responder({
      id: 'instagram-1',
      network: 'instagram',
      status: 'unavailable',
    });
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-indisponivel]').exists()).toBe(true);
  });

  it('Instagram sem a permissão: o login volta para Seus posts', async () => {
    responder({
      id: 'instagram-1',
      network: 'instagram',
      status: 'needs_permission',
      inbox_id: 7,
    });
    instagramClient.generateAuthorization.mockResolvedValue({
      data: { url: 'https://www.instagram.com/oauth/authorize?x=1' },
    });
    const wrapper = await montar();

    await wrapper
      .find('[data-seus-posts-sem-permissao] button')
      .trigger('click');
    await flushPromises();

    expect(instagramClient.generateAuthorization).toHaveBeenCalledWith({
      inbox_id: 7,
      return_to: 'meta_ads',
      purpose: 'seus_posts',
    });
    expect(window.location.href).toBe(
      'https://www.instagram.com/oauth/authorize?x=1'
    );
  });

  it('Página sem a permissão: reautoriza com read_insights e lê de novo', async () => {
    responder({
      id: 'facebook-2',
      network: 'facebook',
      status: 'needs_permission',
      name: 'Studio Acme',
      inbox_id: 8,
    });
    login.mockResolvedValue('token-sintetico');
    FBChannel.reauthorizeFacebookPage.mockResolvedValue({});
    const wrapper = await montar();

    await wrapper
      .find('[data-seus-posts-sem-permissao] button')
      .trigger('click');
    await flushPromises();

    expect(login).toHaveBeenCalledWith(['read_insights']);
    expect(FBChannel.reauthorizeFacebookPage).toHaveBeenCalledWith({
      omniauthToken: 'token-sintetico',
      inboxId: 8,
    });
    expect(SeusPostsAPI.get).toHaveBeenCalledTimes(2);
  });

  it('quem não pode trocar a credencial da caixa recebe o que pedir, sem botão', async () => {
    granted.value = [];
    responder({
      id: 'instagram-1',
      network: 'instagram',
      status: 'needs_permission',
      inbox_id: null,
    });
    const wrapper = await montar();

    const bloco = wrapper.find('[data-seus-posts-sem-permissao]');
    expect(bloco.text()).toContain('Peça a quem administra a conta');
    expect(bloco.find('button').exists()).toBe(false);
  });

  it('sem caixa nenhuma: conectar o Instagram', async () => {
    SeusPostsAPI.get.mockResolvedValue({
      data: { days: 30, perfil: null, perfis: [] },
    });
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-sem-caixa]').exists()).toBe(true);
  });

  it('sem post no período: oferece 90 dias, sem números zerados', async () => {
    responder(instagram({ posts: [], views: 0 }));
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-sem-post]').exists()).toBe(true);
    expect(wrapper.find('[data-seus-posts-numeros]').exists()).toBe(false);
  });

  it('sem as vezes do período, não diz que os posts não apareceram', async () => {
    responder(instagram({ views: null }));
    const wrapper = await montar();

    const heroi = wrapper.find('[data-seus-posts-heroi]').text();
    expect(heroi).toContain('ainda não mandou as vezes');
    expect(heroi).not.toContain('não apareceram');
  });

  it('post de hoje com 0 vezes mostra o zero, sem veredito', async () => {
    responder(
      instagram({
        posts: [post('hoje', { views: 0, created_time: haDias(0.1) })],
      })
    );
    const wrapper = await montar();

    const cartao = wrapper.find('[data-seus-posts-card="hoje"]');
    expect(cartao.find('[data-seus-posts-sem-numeros]').exists()).toBe(false);
    expect(cartao.find('[data-seus-posts-veredito]').exists()).toBe(false);
    expect(cartao.text()).toContain('0');
  });

  it('Meta fora só nos posts: os números ficam e a grade pede outra tentativa', async () => {
    responder(
      instagram({ posts: [], posts_status: 'unavailable', normal: null })
    );
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-numeros]').exists()).toBe(true);
    expect(wrapper.find('[data-seus-posts-sem-post]').exists()).toBe(false);
    expect(wrapper.find('[data-seus-posts-posts-indisponiveis]').exists()).toBe(
      true
    );
  });

  it('leitura antiga e lista cortada aparecem escritas', async () => {
    responder(instagram({ stale: true, posts_truncated: true }));
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-antigo]').exists()).toBe(true);
    expect(wrapper.find('[data-seus-posts-cortados]').exists()).toBe(true);
  });

  it('nenhum seguidor novo não sai com seta para cima', async () => {
    responder(instagram({ new_followers: 0 }));
    const wrapper = await montar();

    expect(
      wrapper
        .find('[data-seus-posts-quadro="followers"] .i-lucide-arrow-up-right')
        .exists()
    ).toBe(false);
  });

  it('primeiro período com números: diz que ainda não compara', async () => {
    responder(instagram({ previous: null, first_period: true }));
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-mudanca]').text()).toContain(
      'ainda não dá para comparar'
    );
    expect(wrapper.find('[data-seus-posts-numeros] h2').text()).toBe(
      'Números dos últimos 30 dias'
    );
  });
  describe('comentários esperando você (F2 #2305)', () => {
    const comComentarios = () =>
      instagram({
        waiting_status: 'ok',
        posts: [
          post('a', { waiting: 2 }),
          post('b', { waiting: 0 }),
          post('c', { waiting: 50, waiting_more: true }),
        ],
      });

    it('soma quem espera na faixa e diz "ou mais" quando um post passou de 50', async () => {
      responder(comComentarios());
      const wrapper = await montar();

      expect(wrapper.find('[data-seus-posts-atencao]').text()).toContain(
        '52 ou mais comentários esperando você em 2 posts'
      );
      expect(
        wrapper
          .find('[data-seus-posts-card="c"] [data-seus-posts-esperando]')
          .text()
      ).toContain('50 ou mais comentários esperando você');
    });

    it('o filtro Esperando você deixa só os posts com alguém esperando', async () => {
      responder(comComentarios());
      const wrapper = await montar();

      await wrapper.find('[data-seus-posts-ver-esperando]').trigger('click');

      expect(
        wrapper
          .findAll('[data-seus-posts-card]')
          .map(card => card.attributes('data-seus-posts-card'))
      ).toEqual(['a', 'c']);
    });

    it('Ver post abre o post aqui dentro, com o perfil no endereço', async () => {
      route.query = { dias: '30' };
      responder(comComentarios());
      const wrapper = await montar();

      const para = JSON.parse(
        wrapper
          .find('[data-seus-posts-card="a"] [data-para]')
          .attributes('data-para')
      );
      expect(para).toEqual({
        name: 'seus_posts_post',
        params: { accountId: 1, postId: 'a' },
        query: { perfil: 'instagram-1', dias: '30' },
      });
    });

    it('sem a flag no servidor (waiting_status ausente): nem faixa, nem link interno', async () => {
      responder(instagram());
      const wrapper = await montar();

      expect(wrapper.find('[data-seus-posts-atencao]').exists()).toBe(false);
      expect(wrapper.find('[data-para]').exists()).toBe(false);
    });

    it('sem a permissão de comentários: os números ficam e o pedido aparece', async () => {
      responder(instagram({ waiting_status: 'needs_permission' }));
      const wrapper = await montar();

      expect(
        wrapper.find('[data-seus-posts-comentarios-sem-permissao]').exists()
      ).toBe(true);
      expect(wrapper.find('[data-seus-posts-card="a"]').exists()).toBe(true);
    });

    it('com a flag, liberar a Página pede também os comentários', async () => {
      flags.value = ['seus_posts_comentarios'];
      responder({
        id: 'facebook-2',
        network: 'facebook',
        status: 'needs_permission',
        name: 'Studio Acme',
        inbox_id: 8,
      });
      login.mockResolvedValue('token-sintetico');
      FBChannel.reauthorizeFacebookPage.mockResolvedValue({});
      const wrapper = await montar();

      await wrapper
        .find('[data-seus-posts-sem-permissao] button')
        .trigger('click');
      await flushPromises();

      expect(login).toHaveBeenCalledWith([
        'read_insights',
        'pages_read_user_content',
        'pages_manage_engagement',
      ]);
    });

    it('com a flag, liberar o Instagram pede números e comentários juntos', async () => {
      flags.value = ['seus_posts_comentarios'];
      responder({
        id: 'instagram-1',
        network: 'instagram',
        status: 'needs_permission',
        inbox_id: 7,
      });
      instagramClient.generateAuthorization.mockResolvedValue({
        data: { url: 'https://www.instagram.com/oauth/authorize?x=2' },
      });
      const wrapper = await montar();

      await wrapper
        .find('[data-seus-posts-sem-permissao] button')
        .trigger('click');
      await flushPromises();

      expect(instagramClient.generateAuthorization).toHaveBeenCalledWith({
        inbox_id: 7,
        return_to: 'meta_ads',
        purpose: 'seus_posts_comentarios',
      });
    });
  });
});
