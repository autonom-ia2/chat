import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import MenuDoEmail from '../email/MenuDoEmail.vue';
import AcoesDoEmail from '../email/AcoesDoEmail.vue';
import TopoDoEmail from '../email/TopoDoEmail.vue';
import PastasDoEmailNoMenu from '../email/PastasDoEmailNoMenu.vue';
import { usePodeComecarConversa } from 'dashboard/components-next/NovaConversa/usePodeComecarConversa';

// #1809 — quem só lê a conversa (conversation_view, #1800) não vê o que escreve:
// Responder, Encaminhar, Nota, Spam, Lixeira, Excluir e Escrever. O servidor já recusa;
// a tela não oferece o que vai dar erro.
const estado = vi.hoisted(() => ({
  podeOperar: true,
  permissoes: ['conversation_manage'],
}));

vi.mock('../email/useConversaDeEmail', async original => {
  const { computed: calculado } = await import('vue');
  return {
    ...(await original()),
    useEmailDaConversa: () => ({
      ligado: calculado(() => true),
      respostaAberta: calculado(() => false),
      recolher: calculado(() => false),
      alternarRecolher: () => {},
      assunto: calculado(() => 'Proposta'),
      podeOperar: calculado(() => estado.podeOperar),
    }),
  };
});
vi.mock('dashboard/composables/store', async () => {
  const { ref: valor } = await import('vue');
  const getters = {
    getCurrentAccountId: 1,
    'inboxes/getInbox': id => ({
      id,
      name: 'Comercial',
      channel_type: 'Channel::Email',
    }),
    'accounts/isFeatureEnabledonAccount': () => true,
  };
  return {
    useMapGetter: nome =>
      nome === 'getCurrentUser'
        ? valor({ accounts: [{ id: 1, permissions: estado.permissoes }] })
        : valor(getters[nome]),
  };
});
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { inbox_id: '2' }, query: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/components-next/sidebar/provider', () => ({
  usePopoverState: () => ({ closeActivePopover: vi.fn() }),
}));
vi.mock('../email/pastaDoEmail', () => ({
  PASTAS: { SPAM: 'spam', LIXEIRA: 'lixeira' },
  usePastaDoEmail: () => ({ pasta: ref(null), abrirPasta: vi.fn() }),
}));

const global = {
  mocks: { $t: chave => chave },
  stubs: {
    Icon: true,
    Avatar: true,
    AcoesDaPasta: { template: '<div data-acoes-da-pasta />' },
    NovaConversaEntrada: {
      template: '<span data-gaveta><slot name="trigger" /></span>',
    },
  },
};
const itensDoMenu = async wrapper => {
  await wrapper.get('[data-menu-do-email]').trigger('click');
  return wrapper
    .findAll('[data-item-do-menu]')
    .map(item => item.attributes('data-item-do-menu'));
};

describe('conversa de e-mail para quem só lê (#1809)', () => {
  beforeEach(() => {
    estado.podeOperar = true;
    estado.permissoes = ['conversation_manage'];
  });

  it('o ⋮ de quem só lê tem só Copiar link, Imprimir e Mostrar original', async () => {
    const leitor = mount(MenuDoEmail, {
      props: { podeOperar: false, podeTraduzir: true, podeExcluir: true },
      global,
    });
    expect(await itensDoMenu(leitor)).toEqual([
      'copiar-link',
      'imprimir',
      'original',
    ]);

    const atendente = mount(MenuDoEmail, {
      props: { podeTraduzir: true, podeExcluir: true },
      global,
    });
    expect(await itensDoMenu(atendente)).toEqual([
      'todos',
      'encaminhar',
      'traduzir',
      'copiar-link',
      'imprimir',
      'original',
      'nao-lida',
      'excluir',
    ]);
  });

  it('sem a barra de Responder, Responder a todos, Encaminhar e Nota', () => {
    estado.podeOperar = false;
    expect(
      mount(AcoesDoEmail, { global }).find('[data-acoes-do-email]').exists()
    ).toBe(false);

    estado.podeOperar = true;
    const barra = mount(AcoesDoEmail, { global });
    expect(
      barra
        .findAll('[data-acao-do-email]')
        .map(botao => botao.attributes('data-acao-do-email'))
    ).toEqual(['responder', 'todos', 'encaminhar', 'nota']);
  });

  it('o topo do e-mail não mostra Spam, Lixeira nem Excluir para sempre', () => {
    estado.podeOperar = false;
    const topo = mount(TopoDoEmail, { props: { mensagens: [] }, global });
    expect(topo.find('[data-topo-do-email]').exists()).toBe(true);
    expect(topo.find('[data-acoes-da-pasta]').exists()).toBe(false);

    estado.podeOperar = true;
    expect(
      mount(TopoDoEmail, { props: { mensagens: [] }, global })
        .find('[data-acoes-da-pasta]')
        .exists()
    ).toBe(true);
  });

  describe('Escrever no menu', () => {
    const folha = { to: { params: { inbox_id: '2' } }, label: 'Comercial' };

    it.each([
      ['aberto', false],
      ['recolhido (balão)', true],
    ])(
      'menu %s: quem só lê vê as pastas, sem o Escrever',
      (_nome, compacto) => {
        estado.permissoes = ['conversation_view'];
        const menu = mount(PastasDoEmailNoMenu, {
          props: { folha, compacto },
          global,
        });

        expect(menu.find('[data-escrever-email]').exists()).toBe(false);
        expect(
          menu
            .findAll('[data-pasta-do-email]')
            .map(item => item.attributes('data-pasta-do-email'))
        ).toEqual(['entrada', 'spam', 'lixeira']);
      }
    );

    it('quem opera vê o Escrever', () => {
      const menu = mount(PastasDoEmailNoMenu, { props: { folha }, global });
      expect(menu.find('[data-escrever-email]').exists()).toBe(true);
    });

    it('a regra é a do "nova conversa" do menu: só leitura sem nenhuma chave de operar', () => {
      const pode = permissoes => {
        estado.permissoes = permissoes;
        return usePodeComecarConversa().value;
      };
      expect(pode(['conversation_view'])).toBe(false);
      expect(
        pode(['conversation_view', 'conversation_participating_manage'])
      ).toBe(true);
      expect(pode(['conversation_manage'])).toBe(true);
    });
  });
});
