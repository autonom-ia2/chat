import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsReportButton from '../components/MetaAdsReportButton.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { useAlert } from 'dashboard/composables';
import { ref } from 'vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { report: vi.fn() },
}));
const canExportCrm = ref(true);
vi.mock('dashboard/routes/dashboard/crm/composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canExportCrm }),
}));

const open = vi.fn();
const close = vi.fn();
// O Dialog de verdade abre um <dialog> nativo; aqui só o conteúdo e o "Baixar".
const DialogStub = {
  emits: ['confirm'],
  methods: { open, close },
  template:
    '<div><slot /><button data-dialog-confirm @click="$emit(\'confirm\')" /></div>',
};

const mountButton = () =>
  mount(MetaAdsReportButton, {
    props: { days: 30 },
    global: { stubs: { Dialog: DialogStub } },
  });

describe('Anúncios · baixar relatório (#1960)', () => {
  let clicked;

  beforeEach(() => {
    vi.clearAllMocks();
    canExportCrm.value = true;
    clicked = [];
    global.URL.createObjectURL = vi.fn(() => 'blob:relatorio');
    global.URL.revokeObjectURL = vi.fn();
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
      function registrar() {
        clicked.push(this.getAttribute('download'));
      }
    );
    CrmMetaAdsConnectionAPI.report.mockResolvedValue({
      data: new Blob(['%PDF']),
      headers: {
        'content-disposition':
          'attachment; filename="anuncios-2026-10-20.pdf"; filename*=UTF-8\'\'anuncios-2026-10-20.pdf',
      },
    });
  });

  it('opens the choice with PDF selected and a 44px button', async () => {
    const wrapper = mountButton();

    await wrapper.find('[data-panel-report]').trigger('click');

    expect(open).toHaveBeenCalled();
    expect(
      wrapper.find('[data-report-format="pdf"]').attributes('aria-pressed')
    ).toBe('true');
    expect(wrapper.find('[data-report-format="pdf"]').classes()).toContain(
      'min-h-11'
    );
  });

  it('tells who cannot export the CRM that the file has only the numbers', async () => {
    expect(mountButton().find('[data-report-no-people]').exists()).toBe(false);

    canExportCrm.value = false;

    expect(mountButton().find('[data-report-no-people]').text()).toBe(
      'CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.NO_PEOPLE'
    );
  });

  it('downloads the PDF of the period with the server file name', async () => {
    const wrapper = mountButton();

    await wrapper.find('[data-dialog-confirm]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.report).toHaveBeenCalledWith('pdf', 30);
    expect(clicked).toEqual(['anuncios-2026-10-20.pdf']);
    expect(close).toHaveBeenCalled();
  });

  it('downloads the spreadsheet when chosen, with a fallback name', async () => {
    CrmMetaAdsConnectionAPI.report.mockResolvedValue({
      data: new Blob(['x']),
      headers: {},
    });
    const wrapper = mountButton();

    await wrapper.find('[data-report-format="planilha"]').trigger('click');
    await wrapper.find('[data-dialog-confirm]').trigger('click');
    await flushPromises();

    expect(
      wrapper.find('[data-report-format="planilha"]').attributes('aria-pressed')
    ).toBe('true');
    expect(CrmMetaAdsConnectionAPI.report).toHaveBeenCalledWith('planilha', 30);
    expect(clicked).toEqual(['anuncios.xlsx']);
  });

  it('warns and keeps the choice open when the download fails', async () => {
    CrmMetaAdsConnectionAPI.report.mockRejectedValue(new Error('500'));
    const wrapper = mountButton();

    await wrapper.find('[data-dialog-confirm]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'CRM_KANBAN.META_ADS_HUB.PANEL.REPORT.ERROR'
    );
    expect(close).not.toHaveBeenCalled();
    expect(clicked).toEqual([]);
  });
});
