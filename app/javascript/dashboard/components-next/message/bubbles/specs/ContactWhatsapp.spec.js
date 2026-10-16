/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import Contact from '../Contact.vue';
import { provideMessageContext } from '../../provider.js';
import { PELES, fornecerPele } from '../../../conversa-canal/pele';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// #1702: "Conversar" e "Salvar contato" acham o contato pelo telefone, criam quando
// não existe e completam o nome quando o cadastro não tem um de verdade.
const montar = achado => {
  const despachos = [];
  const store = createStore({
    actions: {
      'contacts/filter': () => (achado ? [achado] : []),
      'contacts/create': (_ctx, dados) => {
        despachos.push(['create', dados]);
        return { id: 77, ...dados };
      },
      'contacts/update': (_ctx, dados) => {
        despachos.push(['update', dados]);
      },
    },
  });
  const Conversa = defineComponent({
    setup() {
      fornecerPele(computed(() => PELES.WHATSAPP));
      provideMessageContext({
        attachments: ref([
          {
            fallbackTitle: '+55 11 98765-0042',
            meta: { firstName: 'Juliana', lastName: 'Prado' },
          },
        ]),
      });
      return () => h(Contact);
    },
  });
  const i18n = createI18n({ legacy: false, locale: 'en', messages: {} });
  const wrapper = mount(Conversa, {
    global: {
      plugins: [store, i18n],
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        NovaConversaEntrada: { template: '<div><slot name="trigger" /></div>' },
      },
    },
  });
  return { wrapper, despachos };
};

const salvar = async wrapper => {
  const botoes = wrapper.findAll('button');
  await botoes[botoes.length - 1].trigger('click');
  await flushPromises();
};

describe('Contato recebido com a pele do WhatsApp', () => {
  beforeEach(() => {
    vi.spyOn(window, 'open').mockImplementation(() => null);
  });

  it('mostra Conversar e Salvar contato', () => {
    const { wrapper } = montar(null);
    expect(wrapper.find('[data-conversar-com-contato]').exists()).toBe(true);
    expect(wrapper.findAll('button')).toHaveLength(2);
  });

  it('cria o contato quando o telefone não existe', async () => {
    const { wrapper, despachos } = montar(null);
    await salvar(wrapper);
    expect(despachos).toEqual([
      ['create', { name: 'Juliana Prado', phone_number: '+5511987650042' }],
    ]);
  });

  it('completa o nome quando o cadastro só tem o telefone', async () => {
    const { wrapper, despachos } = montar({ id: 5, name: '+55 11 98765-0042' });
    await salvar(wrapper);
    expect(despachos).toEqual([['update', { id: 5, name: 'Juliana Prado' }]]);
  });

  it('não troca o nome que alguém já deu ao contato', async () => {
    const { wrapper, despachos } = montar({ id: 5, name: 'Ju (indicação)' });
    await salvar(wrapper);
    expect(despachos).toEqual([]);
  });

  it('Conversar entrega o contato achado para a Nova conversa', async () => {
    const { wrapper } = montar({ id: 5, name: 'Juliana' });
    await wrapper.find('[data-conversar-com-contato]').trigger('click');
    await flushPromises();
    expect(window.open).not.toHaveBeenCalled();
  });
});
