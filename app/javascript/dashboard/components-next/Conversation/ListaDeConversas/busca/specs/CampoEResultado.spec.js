import { createStore } from 'vuex';
import { flushPromises, mount, enableAutoUnmount } from '@vue/test-utils';
import CampoDaBusca from '../CampoDaBusca.vue';
import ResultadoDaBusca from '../ResultadoDaBusca.vue';
import { pedirFoco } from '../atalhoDaBusca';
import { criarI18n } from '../../specs/apoio';

// #2211 — o campo (✕ e foco pelo atalho) e o resultado em três seções, com "Escrever".
const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const { podeComecar } = vi.hoisted(() => ({ podeComecar: { value: true } }));
vi.mock(
  'dashboard/components-next/NovaConversa/usePodeComecarConversa',
  async () => {
    const { ref } = await import('vue');
    const valor = ref(true);
    podeComecar.ref = valor;
    return { usePodeComecarConversa: () => valor };
  }
);
vi.mock('dashboard/components/ConversationItem.vue', () => ({
  default: {
    props: ['source'],
    template: '<div data-item-de-conversa>{{ source.id }}</div>',
  },
}));

enableAutoUnmount(afterEach);

const store = createStore({
  getters: {
    getCurrentUser: () => ({ id: 1 }),
    getCurrentAccountId: () => 1,
    'accounts/getAccount': () => () => ({ id: 1 }),
  },
});
const global = { plugins: [criarI18n(), store] };

describe('CampoDaBusca', () => {
  it('o ✕ limpa o texto e avisa', async () => {
    const wrapper = mount(CampoDaBusca, {
      props: { modelValue: 'jo', 'onUpdate:modelValue': vi.fn() },
      global,
      attachTo: document.body,
    });
    await wrapper.find('[data-limpar-busca]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual(['']);
    expect(wrapper.emitted('limpar')).toHaveLength(1);
  });

  it('Esc também limpa', async () => {
    const wrapper = mount(CampoDaBusca, {
      props: { modelValue: 'jo' },
      global,
    });
    await wrapper.find('[data-campo-da-busca]').trigger('keydown.esc');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual(['']);
  });

  it('sem texto, não mostra o ✕', () => {
    const wrapper = mount(CampoDaBusca, { props: { modelValue: '' }, global });
    expect(wrapper.find('[data-limpar-busca]').exists()).toBe(false);
  });

  it('o atalho foca o campo, também quando o campo monta depois do pedido', async () => {
    pedirFoco();
    const wrapper = mount(CampoDaBusca, {
      props: { modelValue: '' },
      global,
      attachTo: document.body,
    });
    await flushPromises();
    expect(document.activeElement).toBe(
      wrapper.find('[data-campo-da-busca]').element
    );
  });

  it('o campo diz o que dá para buscar', () => {
    const wrapper = mount(CampoDaBusca, { props: { modelValue: '' }, global });
    expect(
      wrapper.find('[data-campo-da-busca]').attributes('placeholder')
    ).toBe('Buscar nome, telefone ou mensagem');
  });
});

const resultado = (extras = {}) => ({
  conversas: [],
  mensagens: [],
  pessoas: [],
  telefoneNovo: null,
  ...extras,
});
const montarResultado = props =>
  mount(ResultadoDaBusca, {
    props: { buscado: 'jo', texto: 'jo', ...props },
    global,
  });

describe('ResultadoDaBusca', () => {
  beforeEach(() => {
    push.mockReset();
    if (podeComecar.ref) podeComecar.ref.value = true;
  });

  it('mostra as três seções, nesta ordem', () => {
    const wrapper = montarResultado({
      buscado: 'joa',
      texto: 'joa',
      resultado: resultado({
        conversas: [{ id: 5 }],
        mensagens: [
          {
            id: 9,
            conversation_id: 5,
            content: 'Oi, é a Joana',
            created_at: 1,
            message_type: 0,
            contact_name: 'Joana Mattos',
          },
        ],
        pessoas: [{ id: 3, name: 'Joaquim Antônio', phone_number: '+55' }],
      }),
    });
    expect(
      wrapper.findAll('[data-secao]').map(s => s.attributes('data-secao'))
    ).toEqual(['conversas', 'mensagens', 'pessoas']);
    expect(wrapper.find('mark').text()).toBe('Joa');
  });

  it('pessoa sem conversa abre "Começar conversa" na área da direita', async () => {
    const wrapper = montarResultado({
      resultado: resultado({ pessoas: [{ id: 3, name: 'Joaquim' }] }),
    });
    await wrapper.find('[data-pessoa-achada]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: 1 },
      query: { comecar: 3 },
    });
  });

  it('pessoa sem conversa: telefone legível e "Escrever" à vista', () => {
    const wrapper = montarResultado({
      resultado: resultado({
        pessoas: [
          { id: 3, name: 'Joaquim Antônio', phone_number: '+5541966665555' },
        ],
      }),
    });
    const pessoa = wrapper.find('[data-pessoa-achada]');
    expect(pessoa.text()).toContain('+55 41 96666-5555');
    expect(pessoa.find('[data-escrever]').text()).toBe('Escrever');
  });

  it('parte que passou do tempo no servidor: avisa, mesmo sem nada achado', () => {
    const wrapper = montarResultado({
      resultado: resultado({ parcial: true }),
    });
    expect(wrapper.find('[data-busca-parcial]').exists()).toBe(true);
    expect(wrapper.find('[data-nada-achado]').exists()).toBe(false);
  });

  it('telefone novo abre a conversa vazia com o número, sem criar contato', async () => {
    const wrapper = montarResultado({
      buscado: '11 91234-5678',
      texto: '11 91234-5678',
      resultado: resultado({
        telefoneNovo: '+5511912345678',
        caixasParaComecar: [1, 5],
      }),
    });
    expect(wrapper.text()).toContain('Começar conversa com +55 11 91234-5678');
    await wrapper.find('[data-comecar-com-telefone]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: 1 },
      query: { telefone: '+5511912345678', caixas: '1,5' },
    });
  });

  it('telefone novo leva as caixas com texto livre (#2257)', async () => {
    const wrapper = montarResultado({
      resultado: resultado({
        telefoneNovo: '+5511912345678',
        textoLivreNasCaixas: [1, 5],
        caixasParaComecar: [1, 5, 7],
      }),
    });
    await wrapper.find('[data-comecar-com-telefone]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: 1 },
      query: { telefone: '+5511912345678', livre: '1,5', caixas: '1,5,7' },
    });
  });

  it('quem só lê conversas não vê "Escrever" nem a oferta do telefone', async () => {
    podeComecar.ref.value = false;
    const wrapper = montarResultado({
      resultado: resultado({
        pessoas: [{ id: 3, name: 'Joaquim' }],
        telefoneNovo: '+5511912345678',
        caixasParaComecar: [1],
      }),
    });
    expect(wrapper.find('[data-escrever]').exists()).toBe(false);
    expect(wrapper.find('[data-comecar-com-telefone]').exists()).toBe(false);
    await wrapper.find('[data-pessoa-achada]').trigger('click');
    expect(push).not.toHaveBeenCalled();
  });

  // inbox_view de função personalizada vê caixas de que não é membro; o servidor diz em quais dá
  // para começar conversa. Sem nenhuma, oferecer gravaria o contato e falharia na conversa.
  it('sem caixa em que dá para começar, não oferece o telefone nem o e-mail novos', () => {
    const wrapper = montarResultado({
      resultado: resultado({
        telefoneNovo: '+5511912345678',
        emailNovo: 'nova@exemplo.test',
        caixasParaComecar: [],
      }),
    });
    expect(wrapper.find('[data-comecar-com-telefone]').exists()).toBe(false);
    expect(wrapper.find('[data-comecar-com-email]').exists()).toBe(false);
    expect(wrapper.find('[data-nada-achado]').exists()).toBe(true);
  });

  it('mensagem abre a conversa já na mensagem (?messageId=)', async () => {
    const wrapper = montarResultado({
      resultado: resultado({
        mensagens: [
          {
            id: 9,
            conversation_id: 5,
            content: 'Oi, é a Joana',
            created_at: 1,
            message_type: 0,
            contact_name: 'Joana Mattos',
          },
        ],
      }),
    });
    await wrapper.find('[data-mensagem-achada]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      path: '/app/accounts/1/conversations/5',
      query: { messageId: 9 },
    });
  });

  it('nada achado diz o que foi buscado', () => {
    const wrapper = montarResultado({ resultado: resultado() });
    expect(wrapper.find('[data-nada-achado]').text()).toContain('jo');
  });

  it('enquanto o texto novo não voltou, diz "Buscando…"', () => {
    const wrapper = montarResultado({
      buscado: 'jo',
      texto: 'joa',
      resultado: resultado(),
    });
    expect(wrapper.find('[data-buscando]').exists()).toBe(true);
  });

  it('erro oferece "Tentar de novo"', async () => {
    const wrapper = montarResultado({ erro: true, resultado: resultado() });
    await wrapper.find('[data-erro-da-busca] button').trigger('click');
    expect(wrapper.emitted('tentar')).toHaveLength(1);
  });

  describe('o que o leitor de tela ouve (#2211)', () => {
    it('a lista não é região viva; uma região à parte diz só quantos achou', () => {
      const wrapper = montarResultado({
        resultado: resultado({
          conversas: [{ id: 5 }],
          pessoas: [{ id: 3, name: 'Joaquim' }],
        }),
      });
      expect(wrapper.find('[aria-live]').exists()).toBe(false);
      const anuncio = wrapper.find('[role="status"]');
      expect(anuncio.text()).toBe('2 resultados');
      expect(wrapper.findAll('[role="status"]')).toHaveLength(1);
    });

    it('um só: no singular', () => {
      const wrapper = montarResultado({
        resultado: resultado({ conversas: [{ id: 5 }] }),
      });
      expect(wrapper.find('[role="status"]').text()).toBe('1 resultado');
    });

    it('buscando e nada achado', () => {
      const buscando = montarResultado({
        buscado: 'jo',
        texto: 'joa',
        resultado: resultado(),
      });
      expect(buscando.find('[role="status"]').text()).toBe('Buscando…');
      const nada = montarResultado({ resultado: resultado() });
      expect(nada.find('[role="status"]').text()).toBe(
        nada.find('[data-nada-achado]').text()
      );
    });
  });

  describe('e-mail novo (#2211)', () => {
    it('sem o campo do servidor, nada aparece', () => {
      const wrapper = montarResultado({
        buscado: 'nova@exemplo.test',
        texto: 'nova@exemplo.test',
        resultado: resultado(),
      });
      expect(wrapper.find('[data-comecar-com-email]').exists()).toBe(false);
    });

    it('com o campo: "Escrever para" abre a conversa vazia com o e-mail', async () => {
      const wrapper = montarResultado({
        buscado: 'nova@exemplo.test',
        texto: 'nova@exemplo.test',
        resultado: resultado({
          emailNovo: 'nova@exemplo.test',
          caixasParaComecar: [2],
        }),
      });
      const botao = wrapper.find('[data-comecar-com-email]');
      expect(botao.text()).toContain('Escrever para nova@exemplo.test');
      await botao.trigger('click');
      expect(push).toHaveBeenCalledWith({
        name: 'home',
        params: { accountId: 1 },
        query: { email: 'nova@exemplo.test', caixas: '2' },
      });
    });

    it('quem só lê conversas não vê', () => {
      podeComecar.ref.value = false;
      const wrapper = montarResultado({
        resultado: resultado({
          emailNovo: 'nova@exemplo.test',
          caixasParaComecar: [2],
        }),
      });
      expect(wrapper.find('[data-comecar-com-email]').exists()).toBe(false);
    });
  });
});
