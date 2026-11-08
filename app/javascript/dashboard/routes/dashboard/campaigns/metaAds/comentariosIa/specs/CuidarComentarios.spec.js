import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
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
    rascunho: vi.fn(),
    lerAntigos: vi.fn(),
    getResumo: vi.fn(),
    foto: vi.fn(),
    corrigirFoto: vi.fn(),
  },
}));
const flags = ref([]);
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flags.value.includes(flag),
  }),
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

  it('passo 1: o post pede o começo da mensagem à IA; o anúncio abre vazio, sem "Estou escrevendo"', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    ComentariosIaAPI.rascunho.mockResolvedValue({
      data: { status: 'ready', message: 'Oi! Sai por R$ 29.' },
    });
    const post = await montar();
    expect(post.find('[data-ia-dono-message]').element.value).toBe(
      'Oi! Sai por R$ 29.'
    );

    ComentariosIaAPI.rascunho.mockClear();
    const anuncio = await montar({ target: { kind: 'ad', id: '120' } });
    expect(anuncio.find('[data-ia-dono-writing]').exists()).toBe(false);
    expect(anuncio.find('[data-ia-dono-message]').element.value).toBe('');
    expect(ComentariosIaAPI.rascunho).not.toHaveBeenCalled();
  });

  it('passo 1 (#2454): com a flag meta_ads_comentarios_ia, pede "o que eu vi na foto"; sem ela, nada', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    ComentariosIaAPI.rascunho.mockResolvedValue({
      data: { status: 'no_offer' },
    });
    ComentariosIaAPI.foto.mockResolvedValue({
      data: { status: 'ready', text: 'Um bolo de cenoura', corrected: false },
    });

    const sem = await montar();
    expect(sem.find('[data-ia-foto]').exists()).toBe(false);
    expect(ComentariosIaAPI.foto).not.toHaveBeenCalled();

    flags.value = ['meta_ads_comentarios_ia'];
    const com = await montar();
    flags.value = [];

    expect(com.find('[data-ia-foto]').text()).toContain('Um bolo de cenoura');
    expect(ComentariosIaAPI.foto).toHaveBeenCalledWith(target);
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
    expect(wrapper.emitted('reply')).toHaveLength(1);
    expect(wrapper.emitted('back')).toBeUndefined();
  });

  // #2520: sem o post por dentro (seus_posts_comentarios), não há onde responder: o "Ver no post" some.
  it('sem poder abrir o post (canReply falso): o comentário fica sem "Ver no post"', async () => {
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
    const wrapper = await montar({ canReply: false });

    expect(wrapper.text()).toContain('Péssimo');
    expect(wrapper.find('[data-ia-reply-comment]').exists()).toBe(false);
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

  it('#2519 · a IA não pegou em 10 min: "não vi a tempo", em destaque, com há quanto tempo a pessoa espera', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'on',
        para_quem: 'Quem pedir o link',
        to_see: [
          {
            id: 'c-7',
            network: 'instagram',
            author: 'fabi',
            text: 'Qual o valor com desconto?',
            kind: 'not_caught',
            created_time: new Date(Date.now() - 3 * 3600 * 1000).toISOString(),
          },
        ],
      }),
    });
    const wrapper = await montar();
    const linha = wrapper.find('[data-ia-to-see-row="not_caught"]');

    expect(linha.text()).toContain('Não vi este comentário a tempo.');
    expect(linha.find('.text-n-amber-11').exists()).toBe(true);
    expect(linha.find('[data-ia-quando]').text()).toBe('há 3 horas');
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

  it('pergunta que era o caso, sem privado possível: em "Esperando você", com o porquê', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'on',
        network: 'facebook',
        private_available: false,
        para_quem: 'Quem pedir o e-book',
        to_see: [
          {
            id: 'c-1',
            network: 'facebook',
            author: 'Carla',
            text: 'Quanto custa?',
            kind: 'no_private',
          },
        ],
      }),
    });
    const wrapper = await montar({ origin: 'anuncio' });

    expect(wrapper.find('[data-ia-to-see-row="no_private"]').text()).toContain(
      'Mandar no privado ainda não dá aqui: responda no comentário.'
    );
  });

  const falhaCom = (status, error) =>
    Object.assign(new Error('x'), { response: { status, data: { error } } });

  it.each([
    [422, 'no_post', 'não aparece numa rede'],
    [422, 'no_inbox', 'Conecte a caixa'],
    [422, 'needs_login', 'Entre de novo na Meta'],
    [404, 'not_connected', 'não está conectada'],
    [404, 'ad_not_found', 'Não achei este anúncio'],
  ])(
    'erro %s %s: diz o motivo, sem "Tentar de novo" (tentar não cura)',
    async (status, codigo, texto) => {
      ComentariosIaAPI.getCuidado.mockRejectedValue(falhaCom(status, codigo));
      const wrapper = await montar({ origin: 'anuncio' });

      expect(wrapper.find('[data-ia-error]').text()).toContain(texto);
      expect(wrapper.find('[data-ia-error] button').exists()).toBe(false);
    }
  );

  it('Meta fora do ar: diz e oferece tentar de novo', async () => {
    ComentariosIaAPI.getCuidado.mockRejectedValue(
      falhaCom(422, 'meta_unavailable')
    );
    const wrapper = await montar({ origin: 'anuncio' });

    expect(wrapper.find('[data-ia-error]').text()).toContain(
      'A Meta não respondeu'
    );
    expect(wrapper.find('[data-ia-error] button').exists()).toBe(true);
  });

  it('no anúncio, o erro genérico não fala em "post"', async () => {
    ComentariosIaAPI.getCuidado.mockRejectedValue(
      Object.assign(new Error('x'), { response: { status: 500 } })
    );
    const wrapper = await montar({ origin: 'anuncio' });

    const texto = wrapper.find('[data-ia-error]').text();
    expect(texto).toContain('Não consegui ler o anúncio agora.');
    expect(texto).not.toContain('post');
  });

  it('Painel sem a lista (status needs_login): o aviso diz o motivo', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({ care: 'on', para_quem: 'x', status: 'needs_login' }),
    });
    const wrapper = await montar({ origin: 'anuncio' });

    const aviso = wrapper.find('[data-ia-painel-problem]');
    expect(aviso.text()).toContain('Entre de novo na Meta');
    expect(aviso.find('button').exists()).toBe(false);
    expect(wrapper.find('[data-ia-on]').exists()).toBe(true);
  });

  it('Painel sem a lista (Meta fora do ar): o aviso oferece tentar de novo', async () => {
    ComentariosIaAPI.getCuidado
      .mockResolvedValueOnce({
        data: painel({ care: 'on', status: 'meta_unavailable' }),
      })
      .mockResolvedValueOnce({ data: painel({ care: 'on', status: 'ready' }) });
    const wrapper = await montar({ origin: 'anuncio' });

    await wrapper.find('[data-ia-painel-problem] button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-ia-painel-problem]').exists()).toBe(false);
  });

  // #2522: no anúncio nas duas redes, a falha numa não esconde a outra. A lista é a da rede que leu, e a tela diz qual
  // rede faltou e por quê.
  it('anúncio nas duas redes com o Facebook sem login: a lista do Instagram e o aviso do Facebook', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'on',
        para_quem: 'x',
        network: 'both',
        status: 'ready',
        network_status: { instagram: 'ready', facebook: 'needs_login' },
      }),
    });
    const wrapper = await montar({ origin: 'anuncio' });

    const avisos = wrapper.findAll('[data-ia-rede-faltou]');
    expect(avisos).toHaveLength(1);
    expect(avisos[0].attributes('data-network')).toBe('facebook');
    expect(avisos[0].text()).toContain(
      'Só consegui ler os comentários do Instagram. Os do Facebook ficaram de fora.'
    );
    expect(avisos[0].text()).toContain('Entre de novo na Meta');
    expect(avisos[0].find('button').exists()).toBe(false);
    expect(wrapper.find('[data-ia-painel-problem]').exists()).toBe(false);
    expect(wrapper.find('[data-ia-on]').exists()).toBe(true);
  });

  it('rede que faltou por Meta fora do ar: o aviso oferece tentar de novo; as duas lidas, sem aviso', async () => {
    ComentariosIaAPI.getCuidado
      .mockResolvedValueOnce({
        data: painel({
          care: 'on',
          status: 'ready',
          network_status: { instagram: 'meta_unavailable', facebook: 'ready' },
        }),
      })
      .mockResolvedValueOnce({
        data: painel({
          care: 'on',
          status: 'ready',
          network_status: { instagram: 'ready', facebook: 'ready' },
        }),
      });
    const wrapper = await montar({ origin: 'anuncio' });

    const aviso = wrapper.find('[data-ia-rede-faltou]');
    expect(aviso.text()).toContain(
      'Só consegui ler os comentários do Facebook'
    );
    await aviso.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-ia-rede-faltou]').exists()).toBe(false);
  });

  it('rede que faltou por um código que a tela não conhece: o aviso sem o genérico do anúncio, com tentar de novo', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'on',
        status: 'ready',
        network_status: { instagram: 'ready', facebook: 'meta_refused' },
      }),
    });
    const wrapper = await montar({ origin: 'anuncio' });

    const aviso = wrapper.find('[data-ia-rede-faltou]');
    expect(aviso.text()).toContain('Os do Facebook ficaram de fora.');
    expect(aviso.text()).not.toContain('Não consegui ler o anúncio agora');
    expect(aviso.find('button').exists()).toBe(true);
  });

  it('desligado e sem poder ligar: nenhuma lista na tela, nenhum aviso de rede', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'off',
        status: 'ready',
        network_status: { instagram: 'ready', facebook: 'needs_login' },
      }),
    });
    const wrapper = await montar({ origin: 'anuncio', canManage: false });

    expect(wrapper.find('[data-ia-off-readonly]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-rede-faltou]').exists()).toBe(false);
  });

  it('desligado e com poder ligar: o aviso de rede continua, porque o "Ler e mandar" conta só a rede que leu', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({
        care: 'off',
        status: 'ready',
        network_status: { instagram: 'ready', facebook: 'needs_login' },
      }),
    });
    const wrapper = await montar({ origin: 'anuncio' });

    expect(wrapper.find('[data-ia-off-readonly]').exists()).toBe(false);
    expect(wrapper.find('[data-ia-rede-faltou]').exists()).toBe(true);
  });
});
