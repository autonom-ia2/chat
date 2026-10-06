import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import GuidePreviaAutomacao from '../GuidePreviaAutomacao.vue';
import AutomationAPI from 'dashboard/api/automation';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, valores) =>
      valores ? `${key} ${Object.values(valores).join(' ')}` : key,
  }),
}));
vi.mock('dashboard/api/automation', () => ({ default: { show: vi.fn() } }));
vi.mock(
  'dashboard/routes/dashboard/automacoes/composables/useNomesDaConta',
  () => ({
    useNomesDaConta: () => ({
      nomes: ref({ inboxes: { 3: 'Comercial' } }),
      carregarNomes: vi.fn(),
    }),
  })
);

const condicao = (chave, operador, valores, liga = 'AND') => ({
  attribute_key: chave,
  filter_operator: operador,
  values: valores,
  query_operator: liga,
});

const regraAtual = {
  event_name: 'message_created',
  conditions: [
    condicao('inbox_id', 'equal_to', [3]),
    condicao('mail_subject', 'contains', ['Novo lead Chat2You'], null),
  ],
  actions: [{ action_name: 'crm_create_card', action_params: [25] }],
};

const montar = acao =>
  mount(GuidePreviaAutomacao, {
    props: { acao },
    global: { mocks: { $t: key => key } },
  });

describe('GuidePreviaAutomacao', () => {
  afterEach(() => vi.clearAllMocks());

  // Conta 16 (05/10/2026): o cartão mostrou `{"values" => [3], ...}`.
  it('mostra como a automação vai ficar, marca o que muda e risca o que sai', async () => {
    AutomationAPI.show.mockResolvedValue({ data: { payload: regraAtual } });
    const wrapper = montar({
      nome: 'PATCH automation_rules/:id',
      dados: {
        caminho: { id: 8 },
        corpo: {
          conditions: [
            condicao('inbox_id', 'equal_to', [3]),
            condicao('mail_subject', 'contains', ['Chat2You'], null),
          ],
        },
      },
    });
    await flushPromises();

    expect(AutomationAPI.show).toHaveBeenCalledWith(8);
    const texto = wrapper.text();
    expect(texto).not.toContain('{');
    expect(texto).not.toContain('attribute_key');
    expect(wrapper.findAll('[data-muda]')).toHaveLength(1);
    expect(
      wrapper.find('[data-muda]').element.parentElement.textContent
    ).toContain('Chat2You');
    expect(wrapper.findAll('[data-sai]')).toHaveLength(1);
    expect(wrapper.find('[data-sai]').text()).toContain('Novo lead Chat2You');
  });

  it('automação nova: mostra como vai ficar, sem marcar nada como mudança', async () => {
    const wrapper = montar({
      nome: 'POST automation_rules',
      dados: { corpo: regraAtual },
    });
    await flushPromises();

    expect(AutomationAPI.show).not.toHaveBeenCalled();
    expect(wrapper.findAll('[data-muda]')).toHaveLength(0);
    expect(wrapper.findAll('[data-sai]')).toHaveLength(0);
    expect(wrapper.text()).toContain('Novo lead Chat2You');
  });
});
