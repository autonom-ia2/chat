import { flushPromises, mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/seusPosts.json';
import SeusPostPage from '../pages/SeusPostPage.vue';
import SeusPostsAPI from 'dashboard/api/seusPosts';
import { useAlert } from 'dashboard/composables';

// Seus posts F2 (#2305): o post e os comentários, com o que GET seus_posts/posts/:id manda. Dados sintéticos.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/seusPosts', () => ({
  default: {
    getPost: vi.fn(),
    getComments: vi.fn(),
    reply: vi.fn(),
    privateReply: vi.fn(),
    releasePrivateReply: vi.fn(),
    hide: vi.fn(),
    removeComment: vi.fn(),
  },
}));
vi.mock('dashboard/api/channel/fbChannel', () => ({
  default: { reauthorizeFacebookPage: vi.fn() },
}));
vi.mock('dashboard/api/channel/instagramClient', () => ({
  default: { generateAuthorization: vi.fn() },
}));
vi.mock('dashboard/composables/useFacebookPageConnect', () => ({
  useFacebookPageConnect: () => ({
    preloadSdk: () => Promise.resolve(),
    login: vi.fn(),
  }),
}));
const granted = ref([]);
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    usePermissionGranted: key => computed(() => granted.value.includes(key)),
  };
});
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flag === 'seus_posts_comentarios',
  }),
}));
const route = reactive({
  query: { perfil: 'instagram-1', dias: '30' },
  params: { accountId: 1, postId: '17900000000000001' },
});
vi.mock('vue-router', () => ({ useRoute: () => route }));

const UM_DIA = 24 * 60 * 60 * 1000;
const haDias = dias => new Date(Date.now() - dias * UM_DIA).toISOString();

const comentario = (id, extra = {}) => ({
  id,
  text: `Comentário ${id}`,
  created_time: haDias(1),
  author: { username: `pessoa.${id}` },
  replies: [],
  can_reply: true,
  can_hide: true,
  can_delete: true,
  can_reply_private: true,
  ...extra,
});

const lista = (comentarios, extra = {}) => ({
  status: 'ready',
  comments: comentarios,
  total: comentarios.length,
  next_cursor: null,
  ...extra,
});

const responder = (extra = {}) =>
  SeusPostsAPI.getPost.mockResolvedValue({
    data: {
      perfil: { id: 'instagram-1', network: 'instagram', inbox_id: 7 },
      status: 'ok',
      can_manage: true,
      post: {
        id: '17900000000000001',
        text: 'Promoção de outubro. Peças com 20% até domingo.',
        type: 'foto',
        image_url: null,
        permalink: 'https://www.instagram.com/p/exemplo',
        created_time: haDias(5),
        boosted: null,
        views: 1200,
        reach: 900,
        likes: 40,
        comments: 3,
        saved: 5,
        shares: 2,
        waiting: 50,
        waiting_more: true,
      },
      normal: { views: 400 },
      comments: lista([
        comentario('1'),
        comentario('2', {
          replies: [
            { id: 'r', text: 'Oi!', author: { name: 'Loja', is_page: true } },
          ],
        }),
        comentario('3', { hidden: true }),
      ]),
      ...extra,
    },
  });

const montadas = [];
const montar = async () => {
  const wrapper = mount(SeusPostPage, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ],
      stubs: {
        RouterLink: { props: ['to'], template: '<a><slot /></a>' },
        DropdownMenu: true,
      },
    },
  });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};

const linhas = wrapper =>
  wrapper
    .findAll('[data-seus-posts-comentario]')
    .map(linha => linha.attributes('data-seus-posts-comentario'));

describe('Seus posts: o post (#2305)', () => {
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  beforeEach(() => {
    vi.clearAllMocks();
    // O jsdom não rola a página.
    Element.prototype.scrollIntoView = vi.fn();
    granted.value = ['integration_manage', 'inbox_manage'];
  });

  it('pede o post do perfil do endereço e mostra o nome, como foi e os números', async () => {
    responder();
    const wrapper = await montar();

    expect(SeusPostsAPI.getPost).toHaveBeenCalledWith({
      perfil: 'instagram-1',
      postId: '17900000000000001',
    });
    expect(wrapper.find('h1').text()).toBe('Promoção de outubro');
    expect(wrapper.find('[data-seus-posts-como-foi]').text()).toContain(
      '3 vezes mais'
    );
    expect(wrapper.find('[data-seus-posts-legenda]').text()).toContain(
      'Peças com 20% até domingo.'
    );
    expect(wrapper.find('[data-seus-posts-outros]').text()).toBe(
      '5 salvaram · 2 compartilharam'
    );
  });

  it('o herói conta quem espera e Ver quem espera filtra a lista', async () => {
    responder();
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-esperando-heroi]').text()).toContain(
      '50 ou mais comentários esperando você'
    );
    expect(linhas(wrapper)).toEqual(['1', '2', '3']);
    await wrapper.find('[data-seus-posts-ver-esperando]').trigger('click');
    expect(linhas(wrapper)).toEqual(['1']);
  });

  it('o filtro só mostra aba que tem comentário', async () => {
    responder();
    const wrapper = await montar();

    const abas = wrapper
      .findAll('[data-seus-posts-comentarios-filtro]')
      .map(aba => aba.attributes('data-seus-posts-comentarios-filtro'));
    expect(abas).toEqual(['all', 'esperando', 'escondido']);
  });

  it('responder vai à Meta, avisa e lê o post de novo (quem espera junto)', async () => {
    responder();
    SeusPostsAPI.reply.mockResolvedValue({ data: { id: 'novo' } });
    const wrapper = await montar();

    await wrapper
      .find('[data-seus-posts-comentario="1"] [data-seus-posts-acao]')
      .trigger('click');
    await wrapper
      .find('[data-seus-posts-comentario="1"] textarea')
      .setValue('Tem sim!');
    await wrapper
      .find('[data-seus-posts-comentario="1"] form')
      .trigger('submit');
    await flushPromises();

    expect(SeusPostsAPI.reply).toHaveBeenCalledWith({
      perfil: 'instagram-1',
      postId: '17900000000000001',
      commentId: '1',
      content: 'Tem sim!',
    });
    expect(useAlert).toHaveBeenCalledWith('Resposta publicada.');
    expect(SeusPostsAPI.getPost).toHaveBeenCalledTimes(2);
  });

  it('só a leitura mais nova vale ao trocar de post no meio', async () => {
    let primeira;
    SeusPostsAPI.getPost.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          primeira = resolve;
        })
    );
    responder();
    const wrapper = await montar();
    route.params.postId = '17900000000000002';
    await flushPromises();
    primeira({
      data: { perfil: { network: 'instagram' }, status: 'unavailable' },
    });
    await flushPromises();

    expect(wrapper.find('[data-seus-posts-post-indisponivel]').exists()).toBe(
      false
    );
    expect(wrapper.find('h1').text()).toBe('Promoção de outubro');
    route.params.postId = '17900000000000001';
  });

  it('falha da Meta: avisa pelo código e o texto escrito fica', async () => {
    responder();
    SeusPostsAPI.reply.mockRejectedValue({
      response: { status: 422, data: { error: 'meta_refused' } },
    });
    const wrapper = await montar();

    await wrapper
      .find('[data-seus-posts-comentario="1"] [data-seus-posts-acao]')
      .trigger('click');
    await wrapper
      .find('[data-seus-posts-comentario="1"] textarea')
      .setValue('Tem sim!');
    await wrapper
      .find('[data-seus-posts-comentario="1"] form')
      .trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'A Meta não deixou fazer isso neste comentário.'
    );
    expect(
      wrapper.find('[data-seus-posts-comentario="1"] textarea').element.value
    ).toBe('Tem sim!');
    expect(SeusPostsAPI.getPost).toHaveBeenCalledTimes(1);
  });

  it('sem a permissão de comentários: a lista vira o pedido para liberar', async () => {
    responder({
      comments: lista([], { status: 'needs_permission', total: null }),
    });
    const wrapper = await montar();

    expect(
      wrapper.find('[data-seus-posts-comentarios-sem-permissao]').text()
    ).toContain('Libere os comentários');
    expect(wrapper.find('[data-seus-posts-numeros]').exists()).toBe(true);
  });

  it('Ver mais comentários junta a próxima página', async () => {
    responder({
      comments: lista([comentario('1')], { next_cursor: 'cursor-2' }),
    });
    SeusPostsAPI.getComments.mockResolvedValue({
      data: lista([comentario('9')], { total: null }),
    });
    const wrapper = await montar();

    await wrapper.find('[data-seus-posts-ver-mais]').trigger('click');
    await flushPromises();

    expect(SeusPostsAPI.getComments).toHaveBeenCalledWith({
      perfil: 'instagram-1',
      postId: '17900000000000001',
      after: 'cursor-2',
    });
    expect(linhas(wrapper)).toEqual(['1', '9']);
  });

  it.each([
    [403, '[data-seus-posts-post-sem-acesso]'],
    [404, '[data-seus-posts-post-sumiu]'],
    [500, '[data-seus-posts-post-erro]'],
  ])('erro %s mostra o estado certo', async (status, seletor) => {
    SeusPostsAPI.getPost.mockRejectedValue({ response: { status } });
    const wrapper = await montar();

    expect(wrapper.find(seletor).exists()).toBe(true);
  });

  it('a Meta não mandou os posts: diz e oferece tentar de novo', async () => {
    SeusPostsAPI.getPost.mockResolvedValue({
      data: {
        perfil: { id: 'instagram-1', network: 'instagram', inbox_id: 7 },
        status: 'unavailable',
        can_manage: true,
      },
    });
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-post-indisponivel]').exists()).toBe(
      true
    );
  });
});
