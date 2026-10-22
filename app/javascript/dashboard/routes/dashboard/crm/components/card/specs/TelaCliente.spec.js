import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import TelaCliente from '../telas/TelaCliente.vue';

const api = vi.hoisted(() => ({ update: vi.fn() }));
vi.mock('dashboard/api/contacts', () => ({ default: api }));
vi.mock('@sentry/vue', () => ({ captureException: vi.fn() }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave}:${JSON.stringify(valores)}` : chave,
    te: () => true,
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// O painel de relacionamento real busca o contato; aqui ele só mostra o editor.
const Painel = defineComponent({
  setup(_, { slots, expose }) {
    expose({ reload: vi.fn(), reset: vi.fn() });
    return () => h('div', slots.editor?.());
  },
});

const CONTATO = {
  id: 7,
  name: 'Mariana Costa',
  email: 'mariana@exemplo.invalid',
  phone_number: '+5511987654321',
};

const montar = () =>
  mount(TelaCliente, {
    props: { card: { id: 3, contact: CONTATO }, podeRegistros: true },
    global: {
      stubs: { CrmCardRelationshipPanel: Painel, CardPessoaBasica: true },
      directives: { onClickaway: {} },
    },
  });

describe('TelaCliente — erro ao salvar a pessoa', () => {
  it('mostra o motivo do 422 e marca e-mail e telefone', async () => {
    api.update.mockRejectedValue(
      Object.assign(new Error('422'), {
        isAxiosError: true,
        response: {
          status: 422,
          data: {
            message: 'E-mail já está em uso',
            attributes: ['email', 'phone_number'],
          },
        },
      })
    );
    const wrapper = montar();
    await wrapper.find('input[type="email"]').setValue('ja@exemplo.invalid');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'CRM_CARD.PESSOA.SAVE_ERROR_MOTIVO:{"motivo":"E-mail já está em uso"}'
    );
    const confira = wrapper
      .findAll('p')
      .filter(p => p.text() === 'CRM_CARD.PESSOA.CAMPO_CONFIRA');
    expect(confira).toHaveLength(2);
    expect(wrapper.find('[data-campo-telefone]').text()).toContain(
      'CRM_CARD.PESSOA.CAMPO_CONFIRA'
    );
  });

  it('o telefone tem a altura das outras caixas (h-10)', () => {
    const wrapper = montar();
    const caixa = wrapper.find('[data-campo-telefone] input[type="tel"]');
    expect(caixa.classes()).toContain('h-10');
  });
});
