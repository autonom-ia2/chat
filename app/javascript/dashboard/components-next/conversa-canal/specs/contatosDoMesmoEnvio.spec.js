/* eslint-disable vue/one-component-per-file */
// Vários contatos de uma vez pela Cloud (#1702): o Chatwoot cria UMA mensagem por
// contato, todas com o mesmo source_id. O app mostra um cartão só: "Roberto Martins e
// 1 outro contato" e "Ver todos", que abre a janela com cada contato e as ações dele.
import { computed, defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/conversaCanal.json';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { provideMessageContext } from '../../message/provider.js';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerFuso, fornecerPele } from '../pele';
import { useAlbunsDaConversa } from '../album/useAlbuns';
import ContatosDoWhatsapp from '../midia/ContatosDoWhatsapp.vue';
import {
  agruparContatos,
  contatosDoCartao,
  semDuplicadasNaPele,
} from '../midia/contatos';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const contato = (id, extras = {}) => ({
  id,
  messageType: MESSAGE_TYPES.INCOMING,
  status: MESSAGE_STATUS.SENT,
  content: null,
  conversationId: 7,
  createdAt: AGORA,
  currentUserId: 1,
  senderId: 7,
  sender: { id: 7, name: 'Maria', type: 'Contact' },
  sourceId: 'wamid.CONTATOS',
  contentAttributes: {},
  attachments: [
    {
      id: id * 10,
      fileType: 'contact',
      fallbackTitle: `+55 11 9000-000${id}`,
      meta: { firstName: ['', 'Roberto', 'Paula', 'Caio'][id] || 'Ana' },
    },
  ],
  ...extras,
});
const roberto = contato(1, {
  attachments: [
    {
      id: 10,
      fileType: 'contact',
      fallbackTitle: '+55 11 9000-0001',
      meta: { firstName: 'Roberto', lastName: 'Martins' },
    },
    {
      id: 11,
      fileType: 'contact',
      fallbackTitle: '+55 11 3000-0001',
      meta: { firstName: 'Roberto', lastName: 'Martins' },
    },
  ],
});
const paula = contato(2);

describe('semDuplicadasNaPele (teste do Rodrigo em prod, 17/10)', () => {
  // Lista crua do servidor: o Chatwoot jogava fora o 2º contato do mesmo envio.
  const cru = (id, sourceId, tipo = 'contact') => ({
    id,
    source_id: sourceId,
    attachments: tipo ? [{ file_type: tipo }] : [],
  });

  it('mantém todos os contatos do mesmo envio, mesmo o mesmo contato duas vezes', () => {
    const lista = [cru(2, 'wamid.A'), cru(1, 'wamid.A')];
    expect(semDuplicadasNaPele(lista).map(m => m.id)).toEqual([2, 1]);
  });

  it('o resto segue o filtro do Chatwoot: eco repetido sai, sem source_id fica', () => {
    const lista = [
      cru(1, 'wamid.B', null),
      cru(2, 'wamid.B', null),
      cru(3, 'wamid.C', 'image'),
      cru(4, 'wamid.C', 'image'),
      cru(5, null, null),
      cru(6, null, null),
    ];
    expect(semDuplicadasNaPele(lista).map(m => m.id)).toEqual([1, 3, 5, 6]);
  });
});

describe('agruparContatos (#1702)', () => {
  it('mesmo segundo, fora de ordem na lista: o cartão segue a ordem do envio', () => {
    const grupos = agruparContatos([contato(2), contato(1)]);
    expect([...grupos.keys()]).toEqual([2]);
    expect(grupos.get(2).map(m => m.id)).toEqual([1, 2]);
  });

  it('mensagens de contato seguidas com o mesmo sourceId viram um grupo', () => {
    const grupos = agruparContatos([roberto, paula]);
    expect([...grupos.keys()]).toEqual([1]);
    expect(grupos.get(1).map(m => m.id)).toEqual([1, 2]);
  });

  it('sourceId diferente, sem sourceId, texto no meio ou um contato só: sem grupo', () => {
    expect(
      agruparContatos([roberto, contato(2, { sourceId: 'wamid.OUTRO' })]).size
    ).toBe(0);
    expect(
      agruparContatos([
        contato(1, { sourceId: null }),
        contato(2, { sourceId: null }),
      ]).size
    ).toBe(0);
    const texto = { id: 9, sourceId: 'wamid.CONTATOS', attachments: [] };
    expect(agruparContatos([roberto, texto, paula]).size).toBe(0);
    expect(agruparContatos([roberto]).size).toBe(0);
  });

  it('três contatos do mesmo envio e, depois, outro envio de dois', () => {
    const outro = { sourceId: 'wamid.DEPOIS' };
    const lista = [
      roberto,
      paula,
      contato(3),
      contato(4, outro),
      contato(5, outro),
    ];
    const grupos = agruparContatos(lista);
    expect(
      [...grupos.entries()].map(([id, itens]) => [id, itens.length])
    ).toEqual([
      [1, 3],
      [4, 2],
    ]);
  });

  it('cada mensagem da Cloud é UM contato: os anexos são os telefones dele', () => {
    const lista = contatosDoCartao([roberto, paula]);
    expect(lista.map(item => item.nome)).toEqual(['Roberto Martins', 'Paula']);
    expect(lista[0].telefones).toEqual([
      '+55 11 9000-0001',
      '+55 11 3000-0001',
    ]);
    expect(lista[0].paraConversar).toBe('551190000001');
    expect(lista.every(item => item.comAcoes)).toBe(true);
  });

  it('resposta a pedido de contato fica sem ações, como no cartão de um contato', () => {
    const resposta = contato(2, {
      attachments: [
        {
          id: 20,
          fileType: 'contact',
          fallbackTitle: '+55 11 9000-0002',
          meta: { firstName: 'Paula', isContactInfoResponse: true },
        },
      ],
    });
    expect(contatosDoCartao([roberto, resposta]).map(i => i.comAcoes)).toEqual([
      true,
      false,
    ]);
  });
});

const i18n = (locale = 'en') =>
  createI18n({
    legacy: false,
    locale,
    messages: { en, pt_BR: ptBR },
    missingWarn: false,
    fallbackWarn: false,
  });

const naConversa = (mensagens, filho, { pele = PELES.WHATSAPP } = {}) => {
  const contexto = {};
  const Conversa = defineComponent({
    setup() {
      const { escondida } = useAlbunsDaConversa(
        computed(() => mensagens),
        computed(() => null)
      );
      contexto.escondida = escondida;
      return () => filho();
    },
  });
  const Tela = defineComponent({
    setup() {
      fornecerPele(computed(() => pele));
      fornecerFuso(computed(() => 'America/Sao_Paulo'));
      return () => h(Conversa);
    },
  });
  return { Tela, contexto };
};

describe('cartão de vários contatos do mesmo envio (#1702)', () => {
  it('Message.vue: a 1ª desenha o cartão do app e as outras somem da lista', () => {
    const { Tela, contexto } = naConversa([roberto, paula], () =>
      h(Message, roberto)
    );
    const wrapper = mount(Tela, {
      global: {
        ...montagem,
        plugins: [...montagem.plugins, i18n()],
        stubs: { ...montagem.stubs, NovaConversaEntrada: true },
      },
    });
    expect(wrapper.find('[data-bubble-name="contatos"]').exists()).toBe(true);
    expect(wrapper.find('[data-resumo-dos-contatos]').text()).toBe(
      'Roberto Martins and 1 other contact'
    );
    expect(contexto.escondida(1)).toBe(false);
    expect(contexto.escondida(2)).toBe(true);
  });

  it('sem a pele, cada contato no cartão de sempre e nada escondido', () => {
    const { Tela, contexto } = naConversa(
      [roberto, paula],
      () => h(Message, roberto),
      { pele: null }
    );
    const wrapper = mount(Tela, {
      global: {
        ...montagem,
        plugins: [...montagem.plugins, i18n()],
        stubs: { ...montagem.stubs, NovaConversaEntrada: true },
      },
    });
    expect(wrapper.find('[data-contatos-do-whatsapp]').exists()).toBe(false);
    expect(contexto.escondida(2)).toBe(false);
  });

  // Monta só o cartão, dentro do painel da conversa (onde a janela se prende).
  const montarCartao = ({ locale = 'en', store } = {}) => {
    const painel = document.createElement('div');
    painel.innerHTML =
      '<div class="conversation-panel"><div id="lugar"></div></div>';
    document.body.append(painel);
    const Balao = defineComponent({
      setup() {
        provideMessageContext({
          id: ref(roberto.id),
          attachments: ref(roberto.attachments),
          contentAttributes: ref(roberto.contentAttributes),
        });
        return () => h(ContatosDoWhatsapp);
      },
    });
    const { Tela } = naConversa([roberto, paula], () => h(Balao));
    const wrapper = mount(Tela, {
      attachTo: painel.querySelector('#lugar'),
      global: {
        plugins: [
          store || createStore({ actions: { 'contacts/filter': () => [] } }),
          i18n(locale),
        ],
        stubs: {
          BaseBubble: { template: '<div data-balao><slot /></div>' },
          NovaConversaEntrada: {
            props: ['contactId'],
            template:
              '<div data-nova-conversa :data-contato="contactId"><slot name="trigger" /></div>',
          },
        },
      },
    });
    return { wrapper, painel };
  };

  it('em português: "Roberto Martins e 1 outro contato"', () => {
    const { wrapper, painel } = montarCartao({ locale: 'pt_BR' });
    expect(wrapper.find('[data-resumo-dos-contatos]').text()).toBe(
      'Roberto Martins e 1 outro contato'
    );
    expect(wrapper.find('[data-ver-todos-os-contatos]').text()).toBe(
      'Ver todos'
    );
    wrapper.unmount();
    painel.remove();
  });

  it('"Ver todos" abre a janela por cima da conversa com cada contato e as ações', async () => {
    const { wrapper, painel } = montarCartao();
    const botao = wrapper.find('[data-ver-todos-os-contatos]');
    expect(botao.attributes('aria-haspopup')).toBe('dialog');
    expect(document.querySelector('[data-janela-dos-contatos]')).toBeNull();

    await botao.trigger('click');
    const janela = document.querySelector('[data-janela-dos-contatos]');
    expect(janela).not.toBeNull();
    expect(janela.getAttribute('role')).toBe('dialog');
    expect(janela.getAttribute('aria-modal')).toBe('true');
    // Presa ao painel da conversa, fora do balão.
    expect(painel.firstElementChild.contains(janela)).toBe(false);
    expect(painel.contains(janela)).toBe(true);
    expect(botao.attributes('aria-expanded')).toBe('true');

    const itens = [...janela.querySelectorAll('[data-lista-de-contatos] li')];
    expect(itens).toHaveLength(2);
    expect(itens[0].textContent).toContain('Roberto Martins');
    expect(itens[0].textContent).toContain('+55 11 9000-0001');
    expect(itens[0].textContent).toContain('+55 11 3000-0001');
    expect(itens[1].textContent).toContain('Paula');
    expect(
      itens.every(item => item.querySelector('[data-conversar-com-contato]'))
    ).toBe(true);
    expect(
      itens.every(item => item.querySelector('[data-salvar-contato]'))
    ).toBe(true);
    // O foco vai para o fechar; Esc fecha e devolve o foco a "Ver todos".
    expect(document.activeElement?.hasAttribute('data-fechar-contatos')).toBe(
      true
    );
    janela.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await flushPromises();
    expect(document.querySelector('[data-janela-dos-contatos]')).toBeNull();
    expect(document.activeElement).toBe(botao.element);
    wrapper.unmount();
    painel.remove();
  });

  it('"Conversar" de um contato da lista acha/cria o contato e abre a Nova conversa dele', async () => {
    const criar = vi.fn(() => ({ id: 42 }));
    const store = createStore({
      actions: { 'contacts/filter': () => [], 'contacts/create': criar },
    });
    const { wrapper, painel } = montarCartao({ store });
    await wrapper.find('[data-ver-todos-os-contatos]').trigger('click');
    const itens = document.querySelectorAll('[data-lista-de-contatos] li');
    itens[1].querySelector('[data-conversar-com-contato]').click();
    await flushPromises();
    expect(criar).toHaveBeenCalledWith(expect.anything(), {
      name: 'Paula',
      phone_number: '+551190000002',
    });
    const entradas = document.querySelectorAll('[data-nova-conversa]');
    expect(entradas[1].getAttribute('data-contato')).toBe('42');
    expect(entradas[0].hasAttribute('data-contato')).toBe(false);
    wrapper.unmount();
    painel.remove();
  });

  it('"Salvar contato" abre a ficha do contato numa aba nova', async () => {
    const abrir = vi.spyOn(window, 'open').mockImplementation(() => null);
    const store = createStore({
      actions: {
        'contacts/filter': () => [{ id: 9, name: 'Roberto Martins' }],
      },
    });
    const { wrapper, painel } = montarCartao({ store });
    await wrapper.find('[data-ver-todos-os-contatos]').trigger('click');
    document.querySelector('[data-salvar-contato]').click();
    await flushPromises();
    expect(abrir).toHaveBeenCalledWith(
      expect.stringContaining('/contacts/9'),
      '_blank'
    );
    abrir.mockRestore();
    wrapper.unmount();
    painel.remove();
  });
});
