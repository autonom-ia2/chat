import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/metaAdsComentariosIa.json';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';
import { useAlert } from 'dashboard/composables';
import CuidarComentarios from '../CuidarComentarios.vue';

// #2212: a tela de cuidar com o Painel do servidor. Desligado, os passos do dono; ligado, o resultado e "Pausar".
// Sem can_manage, o estado aparece sem nenhum botão de escrita.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/comentariosIa', () => ({
  default: {
    getCuidado: vi.fn(),
    saveCuidado: vi.fn(),
    previa: vi.fn(),
    lerAntigos: vi.fn(),
    getResumo: vi.fn(),
  },
}));
const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

const target = { kind: 'post', id: '1790', perfil: 'instagram-7' };
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

const montadas = [];
const montar = async (props = {}) => {
  const wrapper = mount(CuidarComentarios, {
    props: { target, canManage: true, inboxPath: '/app/inbox/7', ...props },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ],
      stubs: {
        Dialog: {
          template: '<div><slot /><slot name="footer" /></div>',
          methods: { open() {}, close() {} },
        },
      },
    },
  });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};

describe('CuidarComentarios (#2212)', () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  it('desligado: os passos do dono; ligar grava com status on e a frase primeiro', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({ message: 'Oi!', para_quem: 'Quem pedir o link' }),
    });
    ComentariosIaAPI.previa.mockResolvedValue({
      data: { recebe: { sample: true }, nao: null },
    });
    ComentariosIaAPI.saveCuidado.mockResolvedValue({
      data: painel({ care: 'on', para_quem: 'Quem pedir o link' }),
    });
    const wrapper = await montar();

    expect(wrapper.find('[data-ia-dono]').exists()).toBe(true);
    await wrapper.find('[data-ia-dono-next]').trigger('click');
    await wrapper.find('[data-ia-dono-next]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-ia-dono-start]').trigger('click');
    await flushPromises();

    expect(ComentariosIaAPI.saveCuidado).toHaveBeenCalledWith(target, {
      message: 'Oi!',
      paraQuem: 'Quem pedir o link',
      phrases: ['Te mandei no privado!'],
      status: 'on',
    });
    expect(wrapper.find('[data-ia-on]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-started]').text()).toContain(
      'Quem pedir o link'
    );
  });

  it('ligar que falha avisa e fica nos passos', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({ message: 'Oi!', para_quem: 'Quem pedir o link' }),
    });
    ComentariosIaAPI.previa.mockResolvedValue({ data: null });
    ComentariosIaAPI.saveCuidado.mockRejectedValue(new Error('x'));
    const wrapper = await montar();
    await wrapper.find('[data-ia-dono-next]').trigger('click');
    await wrapper.find('[data-ia-dono-next]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-ia-dono-start]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui guardar agora. Tente de novo.'
    );
    expect(wrapper.find('[data-ia-dono]').exists()).toBe(true);
  });

  it.each([
    [403, null, 'Você não tem acesso ao cuidado dos comentários deste post.'],
    [
      422,
      'invalid_message',
      'A mensagem ficou longa demais para a Meta. Tire um pouco do texto.',
    ],
    [422, 'invalid_para_quem', 'Ficou longo demais. Use até 500 letras.'],
    [500, null, 'Não consegui guardar agora. Tente de novo.'],
  ])(
    'ligar que falha com %s %s diz o porquê',
    async (status, codigo, aviso) => {
      ComentariosIaAPI.getCuidado.mockResolvedValue({
        data: painel({ message: 'Oi!', para_quem: 'Quem pedir o link' }),
      });
      ComentariosIaAPI.previa.mockResolvedValue({ data: null });
      ComentariosIaAPI.saveCuidado.mockRejectedValue(
        Object.assign(new Error('x'), {
          response: { status, data: codigo ? { error: codigo } : {} },
        })
      );
      const wrapper = await montar();
      await wrapper.find('[data-ia-dono-next]').trigger('click');
      await wrapper.find('[data-ia-dono-next]').trigger('click');
      await flushPromises();
      await wrapper.find('[data-ia-dono-start]').trigger('click');
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith(aviso);
    }
  );

  it('ligado: um comentário sem conversa leva de volta ao post, e o botão diz isso', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'on',
        to_see: [
          {
            id: 'c-1',
            network: 'instagram',
            author: 'ana',
            text: 'Péssimo',
            kind: 'complaint',
          },
        ],
      }),
    });
    const wrapper = await montar();
    const botao = wrapper.find('[data-ia-reply-comment]');

    expect(botao.text()).toBe('Ver no post');
    await botao.trigger('click');
    expect(wrapper.emitted('back')).toHaveLength(1);
  });

  it('o que a IA leu depois de ligar e não era o caso fica em "Esperando você", não nos antigos', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'on',
        para_quem: 'Quem pedir o link',
        to_see: [
          {
            id: 'c-1',
            network: 'instagram',
            author: 'ana',
            text: 'Link?',
            kind: 'waiting',
          },
          {
            id: 'c-4',
            network: 'instagram',
            author: 'cris',
            text: 'Lindo!',
            kind: 'skipped',
          },
        ],
      }),
    });
    const wrapper = await montar();

    expect(wrapper.find('[data-ia-to-see="waiting"]').text()).toContain(
      'Lindo!'
    );
    expect(wrapper.find('[data-ia-to-see="before"]').text()).not.toContain(
      'Lindo!'
    );
  });

  it('"pode ter saído" e "não cuidei" ficam em "Esperando você", com o porquê; o primeiro em destaque', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'on',
        para_quem: 'Quem pedir o link',
        to_see: [
          {
            id: 'c-5',
            network: 'instagram',
            author: 'bia',
            text: 'Preço?',
            kind: 'unsure',
          },
          {
            id: 'c-6',
            network: 'instagram',
            author: 'leo',
            text: 'Hmm',
            kind: 'unread',
          },
        ],
      }),
    });
    const wrapper = await montar();
    const esperando = wrapper.find('[data-ia-to-see="waiting"]');

    expect(esperando.text()).toContain(
      'Não sei se o privado saiu: a Meta não respondeu.'
    );
    expect(esperando.text()).toContain('Não cuidei deste comentário.');
    expect(
      wrapper.find('[data-ia-to-see-row="unsure"] .text-n-amber-11').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-ia-to-see-row="unread"] .text-n-amber-11').exists()
    ).toBe(false);
  });

  it('ligado: resultado, pausar e, no grupo dos antigos, ler e mandar', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'on',
        para_quem: 'Quem pedir o link',
        results: { sent: 2, replied: 1, skipped: 0 },
        unanswered: 2,
        to_see: [
          {
            id: 'c-1',
            network: 'instagram',
            author: 'ana',
            text: 'Link?',
            kind: 'waiting',
          },
          {
            id: 'c-2',
            network: 'instagram',
            author: 'bia',
            text: 'Péssimo',
            kind: 'complaint',
            conversation_path: '/app/accounts/1/conversations/9',
          },
        ],
        hidden: [
          { id: 'c-3', network: 'instagram', author: 'x', text: 'golpe' },
        ],
      }),
    });
    ComentariosIaAPI.saveCuidado.mockResolvedValue({
      data: painel({ care: 'paused' }),
    });
    ComentariosIaAPI.lerAntigos.mockResolvedValue({ data: { queued: 2 } });
    const wrapper = await montar();

    expect(wrapper.find('[data-ia-result]').text()).toBe(
      '2 receberam no privado · 1 respondeu'
    );
    expect(wrapper.find('[data-ia-to-see="before"]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-to-see="hidden"]').text()).toContain('golpe');

    await wrapper.find('[data-ia-open-inbox]').trigger('click');
    expect(push).toHaveBeenCalledWith('/app/accounts/1/conversations/9');

    await wrapper.find('[data-ia-old-confirm]').trigger('click');
    await flushPromises();
    expect(ComentariosIaAPI.lerAntigos).toHaveBeenCalledWith(target);

    await wrapper.find('[data-ia-pause]').trigger('click');
    await flushPromises();
    expect(ComentariosIaAPI.saveCuidado.mock.lastCall[1].status).toBe('paused');
    expect(wrapper.find('[data-ia-on]').attributes('data-ia-care')).toBe(
      'paused'
    );
  });

  it('sem can_manage: mostra o estado, sem pausar, mudar nem ler e mandar', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'on',
        para_quem: 'Quem pedir o link',
        unanswered: 2,
        to_see: [
          {
            id: 'c-1',
            network: 'instagram',
            author: 'ana',
            text: 'Link?',
            kind: 'waiting',
          },
        ],
      }),
    });
    const wrapper = await montar({ canManage: false });

    expect(wrapper.find('[data-ia-on]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-pause]').exists()).toBe(false);
    expect(wrapper.find('[data-ia-change]').exists()).toBe(false);
    expect(wrapper.find('[data-ia-read-old]').exists()).toBe(false);
  });

  it('desligado sem can_manage: diz o estado, sem os passos', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    const wrapper = await montar({ canManage: false });

    expect(wrapper.find('[data-ia-off-readonly]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-dono]').exists()).toBe(false);
  });

  it('erro ao ler: diz e oferece tentar de novo', async () => {
    ComentariosIaAPI.getCuidado
      .mockRejectedValueOnce(
        Object.assign(new Error('x'), { response: { status: 500 } })
      )
      .mockResolvedValueOnce({ data: painel() });
    const wrapper = await montar();

    expect(wrapper.find('[data-ia-error]').exists()).toBe(true);
    await wrapper.find('[data-ia-error] button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-ia-dono]').exists()).toBe(true);
  });
});
