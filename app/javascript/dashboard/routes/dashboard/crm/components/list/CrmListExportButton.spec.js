import { flushPromises, mount } from '@vue/test-utils';
import CrmListExportButton from './CrmListExportButton.vue';

const { dispatch, useAlert } = vi.hoisted(() => ({
  dispatch: vi.fn(),
  useAlert: vi.fn(),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const montar = props =>
  mount(CrmListExportButton, {
    props: { pipelineId: 9, ...props },
  });

// #722 — "Exportar" da Lista do CRM.
describe('CrmListExportButton', () => {
  let clicado;

  beforeEach(() => {
    vi.clearAllMocks();
    URL.createObjectURL = vi.fn(() => 'blob:planilha');
    URL.revokeObjectURL = vi.fn();
    clicado = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(() => {});
  });

  afterEach(() => {
    clicado.mockRestore();
  });

  it('pede a planilha com o funil e a ordem da Lista e baixa com o nome do servidor', async () => {
    const blob = new Blob(['x']);
    dispatch.mockResolvedValue({ blob, filename: 'crm-2026-09-25.xlsx' });
    let baixado;
    clicado.mockImplementation(function registrar() {
      baixado = this.getAttribute('download');
    });
    const wrapper = montar({
      sortParams: { sort: 'value_cents', direction: 'asc' },
    });

    await wrapper.get('[data-crm-exportar]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('crmKanban/exportCardsList', {
      pipelineId: 9,
      sort: 'value_cents',
      direction: 'asc',
    });
    expect(URL.createObjectURL).toHaveBeenCalledWith(blob);
    expect(baixado).toBe('crm-2026-09-25.xlsx');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:planilha');
  });

  it('avisa quando a exportação falha, sem baixar nada', async () => {
    dispatch.mockRejectedValue(new Error('rede'));
    const wrapper = montar();

    await wrapper.get('[data-crm-exportar]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('CRM_KANBAN.ACTIONS.EXPORT_ERROR');
    expect(clicado).not.toHaveBeenCalled();
  });

  it('sem funil selecionado, o botão fica desativado', () => {
    const wrapper = montar({ pipelineId: null });

    expect(
      wrapper.get('[data-crm-exportar]').attributes('disabled')
    ).toBeDefined();
  });
});
