import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import CrmNumerosOrigensAPI from 'dashboard/api/crmNumerosOrigens';
import OrigensRelatorio from './OrigensRelatorio.vue';

// "Baixar relatório" de Números › Origens (#2001, F6): o diálogo diz o filtro antes de baixar, "Alterar mês ou
// funil" fecha e devolve o foco à tela, e o arquivo é pedido ao servidor com o mesmo mês e funil da tela.
withFullI18n('pt_BR');

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmNumerosOrigens', () => ({
  default: { report: vi.fn() },
}));
vi.mock('shared/composables/useLocale', () => ({
  useLocale: () => ({ resolvedLocale: ref('pt-BR') }),
}));
const canExportCrm = ref(true);
vi.mock('dashboard/routes/dashboard/crm/composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canExportCrm }),
}));

const close = vi.fn();
const DialogStub = {
  props: ['description'],
  emits: ['confirm'],
  methods: { open: vi.fn(), close },
  template:
    '<div><p data-descricao>{{ description }}</p><slot /><button data-dialog-confirm @click="$emit(\'confirm\')" /></div>',
};

const montar = (props = {}) =>
  mount(OrigensRelatorio, {
    props: {
      filtro: { mes: '2026-10', funil: '1' },
      mesNome: 'outubro',
      funilNome: 'Vendas',
      ...props,
    },
    global: { stubs: { Dialog: DialogStub } },
  });

describe('OrigensRelatorio', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    canExportCrm.value = true;
    global.URL.createObjectURL = vi.fn(() => 'blob:x');
    global.URL.revokeObjectURL = vi.fn();
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    CrmNumerosOrigensAPI.report.mockResolvedValue({ data: new Blob(['x']) });
  });

  it('mostra o filtro antes de baixar e diz que a lista vai junto', () => {
    const wrapper = montar();

    expect(wrapper.find('[data-descricao]').text()).toBe(
      'Outubro, funil Vendas. Leva os mesmos números desta tela.'
    );
    expect(wrapper.find('[data-report-people]').text()).toBe(
      'A lista de clientes vai junto.'
    );
    expect(
      montar({ funilNome: '', filtro: { mes: '2026-10', funil: 'todos' } })
        .find('[data-descricao]')
        .text()
    ).toBe('Outubro, todos os funis. Leva os mesmos números desta tela.');
  });

  it('pede o arquivo com o mesmo mês e funil da tela', async () => {
    const wrapper = montar();

    await wrapper.find('[data-dialog-confirm]').trigger('click');
    await flushPromises();

    expect(CrmNumerosOrigensAPI.report).toHaveBeenCalledWith('pdf', {
      mes: '2026-10',
      funil: '1',
    });
  });

  it('"Alterar mês ou funil" fecha o diálogo e avisa a tela', async () => {
    const wrapper = montar();

    await wrapper.find('[data-report-alterar]').trigger('click');

    expect(close).toHaveBeenCalled();
    expect(wrapper.emitted('alterar')).toHaveLength(1);
  });
});
