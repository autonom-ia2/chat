import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import DialogoGanhou from '../DialogoGanhou.vue';

// #2075 — sem a chave de valores o card chega com value_hidden: o Ganhou não
// pede valor e confirma sem mexer nele; quem vê o valor continua confirmando.
const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  fallbackWarn: false,
  messages: {
    pt_BR: {
      CRM_CARD: {
        CANCELAR: 'Cancelar',
        DESFECHO: {
          GANHOU_TITULO_PADRAO: 'Ganhou?',
          GANHOU_TEXTO: 'Confira o valor.',
          GANHOU_CONFIRMA_PADRAO: 'Marcar como ganho',
          VALOR: 'Valor',
          VALOR_OCULTO: 'O valor do negócio fica como está.',
        },
      },
    },
  },
});

const DialogStub = {
  props: ['title', 'description'],
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template:
    '<div><p data-descricao>{{ description }}</p><slot /><slot name="footer" /></div>',
};

const montar = () =>
  mount(DialogoGanhou, {
    props: { rotulo: 'Ganhou', padrao: true },
    global: {
      plugins: [i18n],
      stubs: {
        Dialog: DialogStub,
        Button: true,
        ChoiceSelect: true,
        Input: { props: ['modelValue'], template: '<input data-valor />' },
      },
    },
  });

describe('DialogoGanhou', () => {
  it('without the sales values key, wins without asking or sending a value', async () => {
    const wrapper = montar();
    wrapper.vm.abrir({ value_cents: null, value_hidden: true });
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-valor]').exists()).toBe(false);
    expect(wrapper.get('[data-ganhou-valor-oculto]').text()).toBe(
      'O valor do negócio fica como está.'
    );
    expect(wrapper.get('[data-descricao]').text()).toBe('');

    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    expect(wrapper.emitted('confirmar')).toEqual([[{ result: 'won' }]]);
  });

  it('with the value visible, keeps the value field and sends it', async () => {
    const wrapper = montar();
    wrapper.vm.abrir({ value_cents: 150000, currency: 'BRL' });
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-valor]').exists()).toBe(true);
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    expect(wrapper.emitted('confirmar')).toEqual([
      [{ result: 'won', value_cents: 150000, currency: 'BRL' }],
    ]);
  });
});
