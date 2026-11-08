import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/metaAdsComentariosIa.json';
import CuidarComentariosPage from '../pages/CuidarComentariosPage.vue';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';

// #2212 (B1): a página de cuidar de um post só abre a tela com o post lido (é dele que vem o `can_manage`). Falhou a
// leitura: diz e oferece tentar de novo, em vez de mostrar só leitura sem explicação. Dados sintéticos.
// #2520: o post vem do próprio cuidado (GET .../cuidado/post), com a régua dele.
vi.mock('dashboard/api/comentariosIa', () => ({
  default: { getPostDoCuidado: vi.fn() },
}));
const flags = vi.hoisted(() => ({ ligadas: ['seus_posts_comentarios'] }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flags.ligadas.includes(flag),
  }),
}));
const route = reactive({
  query: { perfil: 'instagram-1', dias: '30' },
  params: { accountId: 1, postId: '17900000000000001' },
});
const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push }),
}));

const CuidarComentarios = {
  name: 'CuidarComentarios',
  props: [
    'target',
    'post',
    'origin',
    'canManage',
    'inboxPath',
    'backLabel',
    'canReply',
  ],
  template: '<div data-tela-de-cuidar :data-pode="String(canManage)" />',
};

const postLido = () => ({
  data: {
    perfil: { id: 'instagram-1', network: 'instagram', inbox_id: 7 },
    can_manage: true,
    post: { id: '17900000000000001', text: 'Promoção', image_url: null },
  },
});
const falha = status =>
  Object.assign(new Error('x'), { response: status ? { status } : undefined });

const montadas = [];
const montar = async () => {
  const wrapper = mount(CuidarComentariosPage, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ],
      stubs: { CuidarComentarios },
    },
  });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};

describe('CuidarComentariosPage (#2212)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete route.query.de;
    flags.ligadas = ['seus_posts_comentarios'];
  });
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  it('com o post lido: abre a tela de cuidar com o can_manage dele', async () => {
    ComentariosIaAPI.getPostDoCuidado.mockResolvedValue(postLido());
    const wrapper = await montar();

    expect(wrapper.find('[data-tela-de-cuidar]').attributes('data-pode')).toBe(
      'true'
    );
    expect(wrapper.find('[data-seus-posts-cuidar-erro]').exists()).toBe(false);
  });

  it('lendo o post: diz que está lendo, sem a tela em só leitura', async () => {
    ComentariosIaAPI.getPostDoCuidado.mockReturnValue(new Promise(() => {}));
    const wrapper = await montar();

    expect(wrapper.find('[data-seus-posts-cuidar-lendo]').exists()).toBe(true);
    expect(wrapper.find('[data-tela-de-cuidar]').exists()).toBe(false);
  });

  it('falha ao ler o post: diz e tenta de novo', async () => {
    ComentariosIaAPI.getPostDoCuidado
      .mockRejectedValueOnce(falha(500))
      .mockResolvedValueOnce(postLido());
    const wrapper = await montar();
    const erro = wrapper.find('[data-seus-posts-cuidar-erro]');

    expect(erro.text()).toContain('Não consegui ler o post agora.');
    expect(wrapper.find('[data-tela-de-cuidar]').exists()).toBe(false);

    await erro.find('[data-seus-posts-cuidar-de-novo]').trigger('click');
    await flushPromises();

    expect(ComentariosIaAPI.getPostDoCuidado).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-tela-de-cuidar]').attributes('data-pode')).toBe(
      'true'
    );
  });

  it('sem acesso ao post (403): diz, sem tentar de novo', async () => {
    ComentariosIaAPI.getPostDoCuidado.mockRejectedValue(falha(403));
    const wrapper = await montar();
    const erro = wrapper.find('[data-seus-posts-cuidar-erro]');

    expect(erro.text()).toContain(
      'Você não tem acesso ao cuidado dos comentários deste post.'
    );
    expect(erro.find('[data-seus-posts-cuidar-de-novo]').exists()).toBe(false);
  });

  it('voltar leva ao post, no mesmo perfil', async () => {
    ComentariosIaAPI.getPostDoCuidado.mockRejectedValue(falha());
    const wrapper = await montar();
    await wrapper.find('[data-seus-posts-cuidar-voltar]').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'seus_posts_post',
      params: { accountId: 1, postId: '17900000000000001' },
      query: { perfil: 'instagram-1', dias: '30' },
    });
  });

  // #2479: aberto pelo "Qual post?" de Agentes, o "Voltar" leva a Agentes; "Ver no post" segue indo ao post.
  it('aberto de Agentes: voltar leva a Agentes; responder vai ao post', async () => {
    route.query.de = 'agentes';
    ComentariosIaAPI.getPostDoCuidado.mockResolvedValue(postLido());
    const wrapper = await montar();

    const tela = wrapper.findComponent({ name: 'CuidarComentarios' });
    expect(tela.props('backLabel')).toBe(
      'AGENTS.AGENTE_DO_POST.CRIAR.VOLTAR_AGENTES'
    );
    tela.vm.$emit('back');
    expect(push).toHaveBeenLastCalledWith({
      name: 'autonomia_agents_index',
      params: { accountId: 1 },
    });

    tela.vm.$emit('reply');
    expect(push).toHaveBeenLastCalledWith({
      name: 'seus_posts_post',
      params: { accountId: 1, postId: '17900000000000001' },
      query: { perfil: 'instagram-1', dias: '30' },
    });
  });

  it('sem vir de Agentes, a tela de cuidar fica com o "Voltar" de sempre', async () => {
    ComentariosIaAPI.getPostDoCuidado.mockResolvedValue(postLido());
    const wrapper = await montar();

    expect(
      wrapper.findComponent({ name: 'CuidarComentarios' }).props('backLabel')
    ).toBe('');
  });

  it('lê o post pelo cuidado, com o alvo do post e o perfil (#2520)', async () => {
    ComentariosIaAPI.getPostDoCuidado.mockResolvedValue(postLido());
    await montar();

    expect(ComentariosIaAPI.getPostDoCuidado).toHaveBeenCalledWith({
      kind: 'post',
      id: '17900000000000001',
      perfil: 'instagram-1',
    });
  });

  // #2520: o cuidado abre sem seus_posts_comentarios; o post por dentro, não.
  it('sem seus_posts_comentarios: voltar leva à lista do Seus posts e não há "Ver no post"', async () => {
    flags.ligadas = [];
    ComentariosIaAPI.getPostDoCuidado.mockResolvedValue(postLido());
    const wrapper = await montar();

    const tela = wrapper.findComponent({ name: 'CuidarComentarios' });
    expect(tela.props('canReply')).toBe(false);
    expect(tela.props('backLabel')).toBe('Voltar para Seus posts');
    tela.vm.$emit('back');
    expect(push).toHaveBeenLastCalledWith({
      name: 'seus_posts_index',
      params: { accountId: 1 },
      query: { perfil: 'instagram-1', dias: '30' },
    });
  });
});
