import { flushPromises, mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/seusPosts.json';
import SeusPostPage from '../pages/SeusPostPage.vue';
import SeusPostsAPI from 'dashboard/api/seusPosts';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';
import { useAlert } from 'dashboard/composables';

// #2212 (B1): no post, atrás da flag meta_ads_comentarios_ia, o bloco "O que tem nos comentários" (o resumo, A2) e o
// "Cuidando · Pausar". Lidos à parte: a página não espera por eles. #2454: o resumo traz só o que o código conta
// (quantos esperam resposta e quantos ainda cabem no privado), sem IA. Dados sintéticos.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/seusPosts', () => ({
  default: { getPost: vi.fn(), getComments: vi.fn() },
}));
vi.mock('dashboard/api/comentariosIa', () => ({
  default: {
    getCuidado: vi.fn(),
    saveCuidado: vi.fn(),
    previa: vi.fn(),
    lerAntigos: vi.fn(),
    getResumo: vi.fn(),
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
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { usePermissionGranted: () => computed(() => false) };
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

// #2520: o cuidado segue a régua do motor: a flag dele e a dos comentários da rede do perfil.
const TODAS = [
  'seus_posts_comentarios',
  'meta_ads_comentarios_ia',
  'meta_ads_comentarios_instagram',
];

const comPost = ({ network = 'instagram', canManage = true } = {}) =>
  SeusPostsAPI.getPost.mockResolvedValue({
    data: {
      perfil: { id: 'instagram-1', network, inbox_id: 7 },
      status: 'ok',
      can_manage: canManage,
      post: {
        id: '17900000000000001',
        text: 'Promoção de outubro. Peças com 20% até domingo.',
        type: 'foto',
        image_url: null,
        permalink: 'https://www.instagram.com/p/exemplo',
        created_time: new Date().toISOString(),
        boosted: null,
        views: 1200,
        reach: 900,
        likes: 40,
        comments: 3,
        saved: 5,
        shares: 2,
        waiting: 4,
        waiting_more: false,
      },
      normal: { views: 400 },
      comments: { status: 'ready', comments: [], total: 0, next_cursor: null },
    },
  });
const painel = (extra = {}) => ({
  network: 'instagram',
  private_available: true,
  care: 'off',
  message: '',
  para_quem: '',
  phrases: ['Te mandei no privado!'],
  read_old: false,
  results: { sent: 0, replied: 0, skipped: 0 },
  unanswered: 0,
  older: 0,
  to_see: [],
  hidden: [],
  ...extra,
});
const resumoPronto = (extra = {}) => ({
  status: 'ready',
  waiting: 17,
  private_window: 12,
  ...extra,
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
        RouterLink: {
          props: ['to'],
          template: '<a :data-to="to && to.name"><slot /></a>',
        },
        DropdownMenu: true,
      },
    },
  });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};
const bloco = wrapper => wrapper.find('[data-seus-posts-o-que-tem]');

describe('Seus posts: o cuidado no post (#2212)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    flags.value = TODAS;
    comPost();
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    ComentariosIaAPI.getResumo.mockResolvedValue({ data: resumoPronto() });
  });
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  it('sem a flag: não lê o cuidado nem o resumo, e nada aparece', async () => {
    flags.value = ['seus_posts_comentarios'];
    const wrapper = await montar();

    expect(ComentariosIaAPI.getCuidado).not.toHaveBeenCalled();
    expect(ComentariosIaAPI.getResumo).not.toHaveBeenCalled();
    expect(bloco(wrapper).exists()).toBe(false);
    expect(wrapper.find('[data-seus-posts-cuidado-heroi]').exists()).toBe(
      false
    );
  });

  it('sem a flag dos comentários da rede do perfil: não lê o cuidado (#2520)', async () => {
    flags.value = [
      'seus_posts_comentarios',
      'meta_ads_comentarios_ia',
      'meta_ads_comentarios_facebook',
    ];
    const wrapper = await montar();

    expect(ComentariosIaAPI.getCuidado).not.toHaveBeenCalled();
    expect(bloco(wrapper).exists()).toBe(false);
  });

  it('pronto: lê o resumo do post do perfil e diz o que tem, com o botão de cuidar', async () => {
    const wrapper = await montar();
    const alvo = {
      kind: 'post',
      id: '17900000000000001',
      perfil: 'instagram-1',
    };

    expect(ComentariosIaAPI.getResumo).toHaveBeenCalledWith(alvo);
    expect(ComentariosIaAPI.getCuidado).toHaveBeenCalledWith(alvo);
    expect(bloco(wrapper).attributes('data-status')).toBe('ready');
    expect(bloco(wrapper).text()).toContain('17 comentários esperam resposta');
    expect(bloco(wrapper).text()).toContain('12 cabem no privado (até 7 dias)');
    expect(
      bloco(wrapper).find('[data-seus-posts-cuidar]').attributes('data-to')
    ).toBe('seus_posts_cuidar');
  });

  it('sem can_manage: mostra o resumo e esconde o botão de cuidar', async () => {
    comPost({ canManage: false });
    const wrapper = await montar();

    expect(bloco(wrapper).text()).toContain('17 comentários esperam resposta');
    expect(bloco(wrapper).find('[data-seus-posts-cuidar]').exists()).toBe(
      false
    );
  });

  it('carregando: o post aparece sem esperar o resumo', async () => {
    ComentariosIaAPI.getResumo.mockReturnValue(new Promise(() => {}));
    const wrapper = await montar();

    expect(wrapper.find('h1').text()).toBe('Promoção de outubro');
    expect(bloco(wrapper).attributes('data-status')).toBe('loading');
  });

  it('needs_permission: pede o acesso, sem os números', async () => {
    ComentariosIaAPI.getResumo.mockResolvedValue({
      data: { status: 'needs_permission' },
    });
    const wrapper = await montar();

    expect(bloco(wrapper).attributes('data-status')).toBe('needs_permission');
    expect(bloco(wrapper).text()).toContain('preciso do acesso');
    expect(bloco(wrapper).text()).not.toContain('esperam resposta');
  });

  // #2522: leitura de uma rede só, os números da rede que leu e o mesmo aviso do Painel, com ler de novo.
  it('uma rede faltou: os números da que leu, o aviso da que faltou e ler de novo', async () => {
    ComentariosIaAPI.getResumo
      .mockResolvedValueOnce({
        data: resumoPronto({
          network_status: { instagram: 'ready', facebook: 'meta_unavailable' },
        }),
      })
      .mockResolvedValueOnce({
        data: resumoPronto({
          network_status: { instagram: 'ready', facebook: 'ready' },
        }),
      });
    const wrapper = await montar();

    const aviso = bloco(wrapper).find('[data-ia-rede-faltou]');
    expect(aviso.attributes('data-network')).toBe('facebook');
    expect(bloco(wrapper).find('[data-seus-posts-esperam]').exists()).toBe(
      true
    );
    await aviso.find('button').trigger('click');
    await flushPromises();

    expect(ComentariosIaAPI.getResumo).toHaveBeenCalledTimes(2);
    expect(bloco(wrapper).find('[data-ia-rede-faltou]').exists()).toBe(false);
  });

  it('meta_unavailable: diz e oferece ler de novo', async () => {
    ComentariosIaAPI.getResumo
      .mockResolvedValueOnce({ data: { status: 'meta_unavailable' } })
      .mockResolvedValueOnce({ data: resumoPronto() });
    const wrapper = await montar();

    expect(bloco(wrapper).text()).toContain(
      'Não consegui ler os comentários agora.'
    );
    await bloco(wrapper)
      .find('[data-seus-posts-o-que-tem-de-novo]')
      .trigger('click');
    await flushPromises();

    expect(ComentariosIaAPI.getResumo).toHaveBeenCalledTimes(2);
    expect(bloco(wrapper).attributes('data-status')).toBe('ready');
  });

  it('erro de rede no resumo: o mesmo aviso, com tentar de novo', async () => {
    ComentariosIaAPI.getResumo.mockRejectedValue(new Error('rede'));
    const wrapper = await montar();

    expect(bloco(wrapper).attributes('data-status')).toBe('error');
    expect(
      bloco(wrapper).find('[data-seus-posts-o-que-tem-de-novo]').exists()
    ).toBe(true);
  });

  it('um comentário: singular, e o que eu faço com ele', async () => {
    ComentariosIaAPI.getResumo.mockResolvedValue({
      data: resumoPronto({ waiting: 1, private_window: 1 }),
    });
    const wrapper = await montar();

    expect(bloco(wrapper).text()).toContain('1 comentário espera resposta');
    expect(bloco(wrapper).text()).toContain('1 cabe no privado (até 7 dias)');
    expect(bloco(wrapper).find('[data-seus-posts-o-que-faco]').text()).toBe(
      ptBR.SEUS_POSTS.POST.CARE_OFFER.TEXT
    );
  });

  it('todos com mais de 7 dias: não diz que cabem no privado e avisa que só os novos', async () => {
    ComentariosIaAPI.getResumo.mockResolvedValue({
      data: resumoPronto({ waiting: 5, private_window: 0 }),
    });
    const wrapper = await montar();

    expect(bloco(wrapper).text()).toContain('5 comentários esperam resposta');
    expect(bloco(wrapper).text()).not.toContain('cabe');
    expect(bloco(wrapper).find('[data-seus-posts-o-que-faco]').text()).toBe(
      ptBR.SEUS_POSTS.POST.CARE_OFFER.TEXT_ONLY_NEW
    );
  });

  it('ninguém esperando: diz e fala dos que chegarem', async () => {
    ComentariosIaAPI.getResumo.mockResolvedValue({
      data: resumoPronto({ waiting: 0, private_window: 0 }),
    });
    const wrapper = await montar();

    expect(bloco(wrapper).text()).toContain(
      'Nenhum comentário esperando resposta.'
    );
    expect(bloco(wrapper).find('[data-seus-posts-o-que-faco]').text()).toBe(
      ptBR.SEUS_POSTS.POST.CARE_OFFER.TEXT_FUTURE
    );
  });

  it('lê o resumo uma vez só: sem IA, não pergunta de novo', async () => {
    vi.useFakeTimers();
    try {
      await montar();
      await vi.advanceTimersByTimeAsync(60000);

      expect(ComentariosIaAPI.getResumo).toHaveBeenCalledTimes(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('o cuidado não veio (rede): aviso com tentar de novo, sem oferecer cuidar', async () => {
    ComentariosIaAPI.getCuidado
      .mockRejectedValueOnce(
        Object.assign(new Error('x'), { response: { status: 500 } })
      )
      .mockResolvedValueOnce({ data: painel({ care: 'on' }) });
    const wrapper = await montar();
    const aviso = wrapper.find('[data-seus-posts-cuidado-erro]');

    expect(aviso.text()).toContain(
      'Não consegui ver agora se estou cuidando dos comentários deste post.'
    );
    expect(bloco(wrapper).exists()).toBe(false);
    expect(wrapper.find('[data-seus-posts-cuidar]').exists()).toBe(false);

    await aviso.find('[data-seus-posts-cuidado-de-novo]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-seus-posts-cuidado-erro]').exists()).toBe(false);
    expect(
      wrapper
        .find('[data-seus-posts-cuidado-heroi]')
        .attributes('data-situacao')
    ).toBe('on');
  });

  it('o cuidado ainda lendo: não oferece cuidar', async () => {
    ComentariosIaAPI.getCuidado.mockReturnValue(new Promise(() => {}));
    const wrapper = await montar();

    expect(bloco(wrapper).exists()).toBe(false);
    expect(wrapper.find('[data-seus-posts-cuidar]').exists()).toBe(false);
  });

  it('Facebook sem privado liberado: não promete privado', async () => {
    comPost({ network: 'facebook' });
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({ network: 'facebook', private_available: false }),
    });
    const wrapper = await montar();

    expect(bloco(wrapper).text()).toContain('17 comentários esperam resposta');
    expect(bloco(wrapper).text()).not.toContain('cabem no privado');
    expect(bloco(wrapper).text()).toContain('ainda não está liberado');
  });

  it('cuidando: o herói diz e pausa com um toque; o bloco do resumo sai', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({ care: 'on', message: 'Oi!', para_quem: 'Quem pedir' }),
    });
    ComentariosIaAPI.saveCuidado.mockResolvedValue({
      data: painel({ care: 'paused', message: 'Oi!', para_quem: 'Quem pedir' }),
    });
    const wrapper = await montar();
    const heroi = () => wrapper.find('[data-seus-posts-cuidado-heroi]');

    expect(bloco(wrapper).exists()).toBe(false);
    expect(heroi().text()).toContain('Cuidando dos comentários');
    await heroi().find('[data-seus-posts-pausar]').trigger('click');
    await flushPromises();

    expect(ComentariosIaAPI.saveCuidado).toHaveBeenCalledWith(
      { kind: 'post', id: '17900000000000001', perfil: 'instagram-1' },
      {
        message: 'Oi!',
        paraQuem: 'Quem pedir',
        phrases: ['Te mandei no privado!'],
        status: 'paused',
      }
    );
    expect(heroi().attributes('data-situacao')).toBe('paused');
    expect(heroi().text()).toContain('Voltar a cuidar');
  });

  it('pausar que falha avisa', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({ care: 'on' }),
    });
    ComentariosIaAPI.saveCuidado.mockRejectedValue(new Error('x'));
    const wrapper = await montar();
    await wrapper.find('[data-seus-posts-pausar]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui mudar agora. Tente de novo.'
    );
  });

  it('cuidando sem can_manage: o estado aparece, sem pausar', async () => {
    comPost({ canManage: false });
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({ care: 'on' }),
    });
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-cuidado-heroi]').exists()).toBe(true);
    expect(wrapper.find('[data-seus-posts-pausar]').exists()).toBe(false);
  });
});
