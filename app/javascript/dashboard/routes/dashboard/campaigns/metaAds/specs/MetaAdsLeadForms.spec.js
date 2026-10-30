import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsLeadForms from '../leadForms/MetaAdsLeadForms.vue';
import LeadFormsAPI from 'dashboard/api/crmMetaAdsLeadForms';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsLeadForms', () => ({
  default: {
    get: vi.fn(),
    receive: vi.fn(),
    stopReceiving: vi.fn(),
    saveDestination: vi.fn(),
    bringPast: vi.fn(),
    removeDestination: vi.fn(),
  },
}));

const PAGE = {
  id: '104882',
  name: 'Studio Aurora',
  receiving: true,
  forms: [
    {
      id: '9001',
      name: 'Orçamento de verão',
      status: 'ACTIVE',
      leads_count: 2,
      past_count: 0,
      destination: {
        pipeline_id: 1,
        pipeline_name: 'Comercial',
        stage_id: 2,
        stage_name: 'Novo',
      },
    },
  ],
};

const LEAD = {
  id: 1,
  card_id: 7,
  name: 'Ana',
  phone: '+5511987650001',
  form_name: 'Orçamento de verão',
  ad_name: 'Carrossel',
  pipeline_id: 1,
  pipeline_name: 'Comercial',
  stage_name: 'Novo',
  received_at: new Date().toISOString(),
  new_contact: true,
};

const mountForms = () =>
  mount(MetaAdsLeadForms, {
    global: {
      mocks: { $t: key => key, $route: { params: { accountId: '1' } } },
      stubs: {
        MetaAdsLeadsRecent: {
          props: ['leads'],
          template: '<div data-recent>{{ leads.length }}</div>',
        },
        MetaAdsLeadFormDestination: true,
        // O Dialog real abre um <dialog> nativo com Teleport; aqui não importa.
        Dialog: {
          methods: { open() {}, close() {} },
          template: '<div />',
        },
      },
      directives: { onClickaway: {} },
    },
  });

// Formulários dos anúncios (#2195): a tela fala com a API real (sem o adaptador do protótipo).
describe('Anúncios da Meta · Formulários (#2195)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('loads pages and forms from the API and shows who arrived', async () => {
    LeadFormsAPI.get.mockResolvedValue({
      data: { pages: [PAGE], pipelines: [], recent_leads: [LEAD] },
    });

    const wrapper = mountForms();
    await flushPromises();

    expect(LeadFormsAPI.get).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-lead-page="104882"]').exists()).toBe(true);
    expect(wrapper.find('[data-lead-form-destination]').exists()).toBe(true);
    expect(wrapper.find('[data-recent]').text()).toBe('1');
  });

  it('hides the list of who arrived when the server does not send it (no contact_view)', async () => {
    LeadFormsAPI.get.mockResolvedValue({
      data: { pages: [PAGE], pipelines: [], recent_leads: null },
    });

    const wrapper = mountForms();
    await flushPromises();

    expect(wrapper.find('[data-lead-page="104882"]').exists()).toBe(true);
    expect(wrapper.find('[data-recent]').exists()).toBe(false);
  });

  it('shows the error with try again when the API fails', async () => {
    LeadFormsAPI.get.mockRejectedValueOnce(new Error('meta_unavailable'));

    const wrapper = mountForms();
    await flushPromises();

    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.find('[data-lead-page]').exists()).toBe(false);
  });

  it('a Page that Meta cannot read now shows the reason and the other Pages stay', async () => {
    const other = { ...PAGE, id: '200', name: 'Outra Página' };
    LeadFormsAPI.get.mockResolvedValue({
      data: {
        pages: [{ ...PAGE, forms: [], error: 'meta_unavailable' }, other],
        pipelines: [],
        recent_leads: [],
      },
    });

    const wrapper = mountForms();
    await flushPromises();

    expect(wrapper.findAll('[data-lead-page-error]')).toHaveLength(1);
    expect(wrapper.findAll('[data-lead-form]').length).toBeGreaterThan(0);
  });

  it('a Page Meta refuses for good says to connect again, not to try again', async () => {
    LeadFormsAPI.get.mockResolvedValue({
      data: {
        pages: [{ ...PAGE, forms: [], error: 'meta_refused' }],
        pipelines: [],
        recent_leads: [],
      },
    });

    const wrapper = mountForms();
    await flushPromises();

    const error = wrapper.find('[data-lead-page-error]').text();
    expect(error).toContain('PAGE_REFUSED');
    expect(error).not.toContain('PAGE_UNAVAILABLE');
  });

  it('saving and bringing the old ones says they are coming in the background', async () => {
    LeadFormsAPI.get.mockResolvedValue({
      data: { pages: [PAGE], pipelines: [], recent_leads: [] },
    });

    const wrapper = mountForms();
    await flushPromises();
    wrapper
      .findComponent({ name: 'MetaAdsLeadFormPage' })
      .vm.$emit('choose', PAGE.forms[0]);
    await flushPromises();
    wrapper
      .findComponent({ name: 'MetaAdsLeadFormDestination' })
      .vm.$emit('saved', {
        form: PAGE.forms[0],
        archived: false,
        destination: PAGE.forms[0].destination,
        importing: true,
      });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining('SAVED_BRINGING')
    );
  });

  it('stopping the page calls the API and refreshes with what it returns', async () => {
    LeadFormsAPI.get.mockResolvedValue({
      data: { pages: [PAGE], pipelines: [], recent_leads: [] },
    });
    LeadFormsAPI.stopReceiving.mockResolvedValue({
      data: {
        pages: [{ ...PAGE, receiving: false }],
        pipelines: [],
        recent_leads: [],
      },
    });

    const wrapper = mountForms();
    await flushPromises();
    wrapper.findComponent({ name: 'MetaAdsLeadFormPage' }).vm.$emit('stop');
    await flushPromises();

    expect(LeadFormsAPI.stopReceiving).toHaveBeenCalledWith('104882');
    expect(useAlert).toHaveBeenCalled();
    expect(wrapper.find('[data-lead-page-paused]').exists()).toBe(true);
  });
});
