import { flushPromises, mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/seusPosts.json';
import SeusPostPage from '../pages/SeusPostPage.vue';
import SeusPostsAPI from 'dashboard/api/seusPosts';

// #2454: com a flag meta_ads_comentarios_ia_conversa, o fio conta na lista de comentários do post, como no Resumo: as
// respostas de cliente contam nas abas e aparecem dentro do comentário de cima, cada uma com o próprio selo. As da
// própria conta não contam. Sem a flag, nada muda. Dados sintéticos.
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
const flags = ref([]);
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flags.value.includes(flag),
  }),
}));
const route = reactive({
  query: { perfil: 'instagram-1', dias: '30' },
  params: { accountId: 1, postId: '17900000000000001' },
});
vi.mock('vue-router', () => ({ useRoute: () => route }));

const hora = h => `2026-10-29T${String(h).padStart(2, '0')}:00:00+0000`;
const daConta = (id, h) => ({
  id,
  text: 'Te chamei no privado',
  created_time: hora(h),
  author: { name: null, username: 'loja.exemplo', is_page: true },
});
const cliente = (id, h, extra = {}) => ({
  id,
  text: `Resposta ${id}`,
  created_time: hora(h),
  author: { username: `pessoa.${id}`, is_page: false },
  ...extra,
});
const comentario = (id, h, extra = {}) => ({
  ...cliente(id, h),
  text: `Comentário ${id}`,
  replies: [],
  can_reply: true,
  can_hide: true,
  can_delete: true,
  can_reply_private: true,
  ...extra,
});

// c1 espera, com uma resposta de cliente que espera; c2 a conta respondeu, mas depois veio uma resposta de cliente que
// espera; c3 escondido. Resumo: 3 esperam (c1, r1, r2).
const comentarios = [
  comentario('c1', 10, { replies: [cliente('r1', 11)] }),
  comentario('c2', 9, {
    replies: [daConta('p2', 9), cliente('r2', 12), daConta('p3', 8)],
  }),
  comentario('c3', 8, { hidden: true }),
];

const responder = () =>
  SeusPostsAPI.getPost.mockResolvedValue({
    data: {
      perfil: { id: 'instagram-1', network: 'instagram', inbox_id: 7 },
      status: 'ok',
      can_manage: true,
      post: {
        id: '17900000000000001',
        text: 'Vestido azul',
        type: 'foto',
        image_url: null,
        permalink: 'https://www.instagram.com/p/exemplo',
        created_time: hora(1),
        boosted: null,
        likes: 4,
        comments: 7,
      },
      normal: {},
      comments: {
        status: 'ready',
        comments: comentarios,
        total: 7,
        next_cursor: null,
      },
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

const abas = wrapper =>
  Object.fromEntries(
    wrapper
      .findAll('[data-seus-posts-comentarios-filtro]')
      .map(aba => [
        aba.attributes('data-seus-posts-comentarios-filtro'),
        Number(aba.find('span').text()),
      ])
  );
const abrir = async (wrapper, chave) => {
  await wrapper
    .find(`[data-seus-posts-comentarios-filtro="${chave}"]`)
    .trigger('click');
};
const linha = (wrapper, id) =>
  wrapper.find(`[data-seus-posts-comentario="${id}"]`);
const seloDe = (wrapper, id) =>
  linha(wrapper, id).find('[data-seus-posts-selo]');
const resposta = (wrapper, id) =>
  wrapper.find(`[data-seus-posts-resposta="${id}"]`);

describe('Seus posts: o fio conta na lista do post (#2454)', () => {
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  beforeEach(() => {
    vi.clearAllMocks();
    Element.prototype.scrollIntoView = vi.fn();
    granted.value = ['integration_manage', 'inbox_manage'];
    responder();
  });

  describe('com a flag da conversa', () => {
    beforeEach(() => {
      flags.value = [
        'seus_posts_comentarios',
        'meta_ads_comentarios_ia_conversa',
      ];
    });

    it('as abas contam as respostas de cliente, como o Resumo; as da conta não contam', async () => {
      const wrapper = await montar();

      expect(abas(wrapper)).toEqual({ all: 5, esperando: 3, escondido: 1 });
    });

    it('cada resposta de cliente fica dentro do comentário de cima, com o próprio selo', async () => {
      const wrapper = await montar();

      expect(
        linha(wrapper, 'c1').find('[data-seus-posts-resposta="r1"]').exists()
      ).toBe(true);
      expect(
        resposta(wrapper, 'r1').find('[data-seus-posts-resposta-estado]').text()
      ).toBe('Esperando você');
      expect(
        resposta(wrapper, 'p2')
          .find('[data-seus-posts-resposta-estado]')
          .exists()
      ).toBe(false);
      expect(seloDe(wrapper, 'c2').text()).toBe('Respondido');
    });

    it('na aba Esperando você, o de cima aparece pela resposta que espera, sem selo que contradiga a aba', async () => {
      const wrapper = await montar();
      await abrir(wrapper, 'esperando');

      expect(
        wrapper
          .findAll('[data-seus-posts-comentario]')
          .map(item => item.attributes('data-seus-posts-comentario'))
      ).toEqual(['c1', 'c2']);
      expect(seloDe(wrapper, 'c1').text()).toBe('Esperando você');
      expect(seloDe(wrapper, 'c2').exists()).toBe(false);
      expect(
        resposta(wrapper, 'r2').find('[data-seus-posts-resposta-estado]').text()
      ).toBe('Esperando você');
      expect(
        wrapper
          .findAll('[data-seus-posts-resposta-estado]')
          .map(selo => selo.text())
      ).toEqual(['Esperando você', 'Esperando você']);
    });
  });

  describe('sem a flag da conversa', () => {
    beforeEach(() => {
      flags.value = ['seus_posts_comentarios'];
    });

    it('as abas contam só os comentários de primeiro nível, e as respostas ficam sem selo, como antes', async () => {
      const wrapper = await montar();

      expect(abas(wrapper)).toEqual({ all: 3, esperando: 1, escondido: 1 });
      expect(wrapper.find('[data-seus-posts-resposta-estado]').exists()).toBe(
        false
      );

      await abrir(wrapper, 'esperando');
      expect(
        wrapper
          .findAll('[data-seus-posts-comentario]')
          .map(item => item.attributes('data-seus-posts-comentario'))
      ).toEqual(['c1']);
    });
  });
});
