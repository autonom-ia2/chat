import { flushPromises, mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/seusPosts.json';
import ptBRIa from 'dashboard/i18n/locale/pt_BR/metaAdsComentariosIa.json';
import SeusPostsPage from '../pages/SeusPostsPage.vue';
import SeusPostsAPI from 'dashboard/api/seusPosts';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';
import { useAlert } from 'dashboard/composables';

// #2212 (B1): na lista do Seus posts, atrás da flag meta_ads_comentarios_ia, o selo "Cuidando" de cada cartão e a
// faixa "Cuidando dos comentários de N posts", com "Pausar todos". Dados sintéticos.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/seusPosts', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/comentariosIa', () => ({
  default: { getCuidados: vi.fn(), mudarTodos: vi.fn() },
}));
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
          messages: { pt_BR: { ...ptBR, ...ptBRIa } },
        }),
      ],
      stubs: {
        ChoiceSelect: true,
        Dialog: {
          template: '<div><slot /></div>',
          methods: { open() {}, close() {} },
        },
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

const cuidados = lista =>
  ComentariosIaAPI.getCuidados.mockResolvedValue({ data: { cuidados: lista } });
const item = (postId, care) => ({
  post_id: postId,
  care,
  network: 'instagram',
  results: { sent: 4, replied: 2 },
});

describe('Seus posts: o cuidado da IA (#2212)', () => {
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  beforeEach(() => {
    vi.clearAllMocks();
    Element.prototype.scrollIntoView = vi.fn();
    route.query = {};
    granted.value = ['posts_manage'];
    flags.value = ['seus_posts_comentarios', 'meta_ads_comentarios_ia'];
  });

  it('sem a flag, não lê os cuidados nem mostra faixa', async () => {
    flags.value = [];
    responder(instagram());
    const wrapper = await montar();

    expect(ComentariosIaAPI.getCuidados).not.toHaveBeenCalled();
    expect(wrapper.find('[data-ia-band]').exists()).toBe(false);
  });

  it('lê os cuidados do perfil, põe o selo no cartão e a faixa com o resultado', async () => {
    responder(instagram());
    cuidados([item('a', 'on')]);
    const wrapper = await montar();

    expect(ComentariosIaAPI.getCuidados).toHaveBeenCalledWith('instagram-1');
    const cartao = wrapper.find('[data-seus-posts-card="a"]');
    expect(cartao.text()).toContain('Cuidando');
    expect(wrapper.find('[data-seus-posts-card="b"]').text()).not.toContain(
      'Cuidando'
    );
    const faixa = wrapper.find('[data-ia-band]');
    expect(faixa.text()).toContain('1 post');
    await faixa.find('[data-ia-band-toggle]').trigger('click');
    expect(faixa.find('[data-ia-band-post="a"]').text()).toContain('Post a');
  });

  it('na faixa, 1 é singular: "1 recebeu no privado · 1 respondeu"', async () => {
    responder(instagram());
    cuidados([{ ...item('a', 'on'), results: { sent: 1, replied: 1 } }]);
    const wrapper = await montar();

    await wrapper.find('[data-ia-band-toggle]').trigger('click');
    expect(wrapper.find('[data-ia-band-post="a"]').text()).toContain(
      '1 recebeu no privado · 1 respondeu'
    );
  });

  it('cuidado de um post fora do período: entra na faixa, sem foto', async () => {
    responder(instagram());
    cuidados([item('velho', 'on')]);
    const wrapper = await montar();

    await wrapper.find('[data-ia-band-toggle]').trigger('click');
    const linha = wrapper.find('[data-ia-band-post="velho"]');
    expect(linha.exists()).toBe(true);
    expect(linha.find('img').exists()).toBe(false);
  });

  it('"Pausar todos" pede ao servidor e mostra a lista que voltou', async () => {
    responder(instagram());
    cuidados([item('a', 'on')]);
    ComentariosIaAPI.mudarTodos.mockResolvedValue({
      data: { cuidados: [item('a', 'paused')] },
    });
    const wrapper = await montar();

    await wrapper.find('[data-ia-pause-all]').trigger('click');
    await flushPromises();

    expect(ComentariosIaAPI.mudarTodos).toHaveBeenCalledWith(
      'instagram-1',
      'paused'
    );
    expect(wrapper.find('[data-ia-resume-all]').exists()).toBe(true);
  });

  it('trocar de perfil enquanto pausa: a lista que volta não entra no perfil novo', async () => {
    responder(instagram());
    cuidados([item('a', 'on')]);
    let pausou;
    ComentariosIaAPI.mudarTodos.mockReturnValue(
      new Promise(resolve => {
        pausou = resolve;
      })
    );
    const wrapper = await montar();
    await wrapper.find('[data-ia-pause-all]').trigger('click');

    responder(instagram({ id: 'instagram-2' }));
    cuidados([]);
    route.query = { perfil: 'instagram-2' };
    await flushPromises();
    expect(ComentariosIaAPI.getCuidados).toHaveBeenLastCalledWith(
      'instagram-2'
    );
    pausou({ data: { cuidados: [item('a', 'paused')] } });
    await flushPromises();

    expect(wrapper.find('[data-ia-band]').exists()).toBe(false);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('a lista da faixa fica no DOM fechada: o aria-controls sempre aponta para ela', async () => {
    responder(instagram());
    cuidados([item('a', 'on')]);
    const wrapper = await montar();
    const botao = wrapper.find('[data-ia-band-toggle]');
    const id = botao.attributes('aria-controls');
    const lista = wrapper.find(`#${id}`);

    // Montada fora do documento, isVisible não serve: o v-show é o display do elemento.
    expect(lista.exists()).toBe(true);
    expect(lista.element.style.display).toBe('none');
    await botao.trigger('click');
    expect(botao.attributes('aria-expanded')).toBe('true');
    expect(lista.element.style.display).toBe('');
  });

  it('falha ao pausar avisa e não muda a lista', async () => {
    responder(instagram());
    cuidados([item('a', 'on')]);
    ComentariosIaAPI.mudarTodos.mockRejectedValue(new Error('rede'));
    const wrapper = await montar();

    await wrapper.find('[data-ia-pause-all]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalled();
    expect(wrapper.find('[data-ia-pause-all]').exists()).toBe(true);
  });

  it('sem posts_manage: vê a faixa, sem "Pausar todos"', async () => {
    granted.value = [];
    responder(instagram());
    cuidados([item('a', 'on')]);
    const wrapper = await montar();

    expect(wrapper.find('[data-ia-band]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-pause-all]').exists()).toBe(false);
  });

  it('abrir um post da faixa leva à tela de cuidar dele, no perfil', async () => {
    responder(instagram());
    cuidados([item('a', 'on')]);
    const wrapper = await montar();

    await wrapper.find('[data-ia-band-toggle]').trigger('click');
    await wrapper.find('[data-ia-band-post="a"]').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'seus_posts_cuidar',
      params: { accountId: 1, postId: 'a' },
      query: { perfil: 'instagram-1' },
    });
  });

  it('falha ao ler os cuidados: a página segue, sem faixa', async () => {
    responder(instagram());
    ComentariosIaAPI.getCuidados.mockRejectedValue(new Error('rede'));
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-grade]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-band]').exists()).toBe(false);
  });
});
