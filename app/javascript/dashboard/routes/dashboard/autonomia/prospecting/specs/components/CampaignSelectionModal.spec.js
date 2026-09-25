// Janela "Adicionar à campanha" a partir da seleção da busca (#680, ACAO-25,
// 26, 27 e 37), com o texto real: escolha da campanha (só as de envio único
// ativas), nome do segmento e resumo de quem entrou e de quem ficou de fora,
// com o motivo de cada lead.
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CampaignsAPI from 'dashboard/api/campaigns';
import { isFixedPanelOpen } from 'dashboard/composables/useFixedPanelState';
import CampaignSelectionModal from '../../components/campaign/CampaignSelectionModal.vue';
import { ChoiceSelectStub, deferred } from '../support/searchPageHarness';

vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: { addLeadsToCampaign: vi.fn() },
}));
vi.mock('dashboard/api/campaigns', () => ({ default: { get: vi.fn() } }));

withFullI18n();

const LEADS = [
  { id: 101, name: 'Padaria Sol' },
  { id: 102, name: 'Pão Quente' },
  { id: 103, name: 'Confeitaria Lua' },
];

const CAMPAIGNS = [
  {
    id: 8,
    title: 'Café da manhã',
    campaign_type: 'one_off',
    campaign_status: 'active',
  },
  {
    id: 9,
    title: 'Encerrada',
    campaign_type: 'one_off',
    campaign_status: 'completed',
  },
  {
    id: 10,
    title: 'Boas-vindas do site',
    campaign_type: 'ongoing',
    campaign_status: 'active',
  },
];

const segmentResponse = (extra = {}) => ({
  data: {
    payload: {
      list: { id: 70, name: 'padaria' },
      segment: {
        label: { id: 5, title: 'prospeccao_70_padaria' },
        campaign: { id: 8, title: 'Café da manhã' },
        eligible_count: 1,
        blocked_count: 2,
        created_contacts_count: 1,
        blocked_leads: [
          {
            id: 102,
            name: 'Pão Quente',
            status: 'contacted',
            reason_code: 'no_whatsapp',
          },
          {
            id: 103,
            name: 'Confeitaria Lua',
            status: 'new',
            reason_code: 'opt_out',
          },
        ],
        ...extra,
      },
    },
  },
});

const mountModal = async ({ campaigns = CAMPAIGNS } = {}) => {
  CampaignsAPI.get.mockResolvedValue({ data: campaigns });
  const wrapper = mount(CampaignSelectionModal, {
    props: { leads: LEADS, defaultSegmentName: 'padaria' },
    global: { stubs: { ChoiceSelect: ChoiceSelectStub } },
  });
  await flushPromises();
  return wrapper;
};

const campaignChoice = wrapper =>
  wrapper
    .findAllComponents(ChoiceSelectStub)
    .find(item => item.props('ariaLabel') === 'Campanha');
const submit = wrapper => wrapper.find('[data-test="campaign-submit"]');
const result = wrapper => wrapper.find('[data-test="campaign-result"]');

describe('CampaignSelectionModal', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('é uma janela com título e avisa o lançador do Guia enquanto aberta', async () => {
    const wrapper = await mountModal();

    expect(wrapper.find('[role="dialog"]').attributes('aria-modal')).toBe(
      'true'
    );
    expect(wrapper.find('h2').text()).toBe('Adicionar à campanha');
    expect(isFixedPanelOpen.value).toBe(true);
    wrapper.unmount();
    expect(isFixedPanelOpen.value).toBe(false);
  });

  it('oferece só as campanhas de envio único ativas, além de só criar o segmento', async () => {
    const wrapper = await mountModal();

    expect(campaignChoice(wrapper).props('options')).toEqual([
      { value: '', label: 'Só criar o segmento, sem campanha' },
      { value: 8, label: 'Café da manhã' },
    ]);
    expect(campaignChoice(wrapper).props('modelValue')).toBe('');
    expect(wrapper.find('input[type="text"]').element.value).toBe('padaria');
    expect(wrapper.text()).toContain('3 lead(s) selecionado(s).');
  });

  it('manda os selecionados com a campanha e o nome do segmento, e mostra quem entrou e quem ficou de fora com o motivo', async () => {
    const wrapper = await mountModal();
    AutonomiaProspectingAPI.addLeadsToCampaign.mockResolvedValue(
      segmentResponse()
    );

    campaignChoice(wrapper).vm.$emit('update:modelValue', 8);
    await wrapper.find('input[type="text"]').setValue('Padarias do centro');
    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.addLeadsToCampaign).toHaveBeenCalledWith({
      leadIds: [101, 102, 103],
      campaignId: 8,
      segmentName: 'Padarias do centro',
    });
    const text = result(wrapper).text();
    expect(text).toContain('1 lead(s) entraram no segmento');
    expect(text).toContain('Campanha: Café da manhã');
    expect(wrapper.text()).toContain('2 ficaram de fora');
    expect(
      wrapper.findAll('[data-test="campaign-blocked"]').map(item => item.text())
    ).toEqual([
      'Pão Quente · Sem WhatsApp verificado',
      'Confeitaria Lua · Pediu para não receber mensagens',
    ]);
    expect(wrapper.emitted('done')[0][0].eligible_count).toBe(1);
  });

  it('cada motivo de bloqueio tem texto próprio, e motivo desconhecido não some', async () => {
    const wrapper = await mountModal();
    AutonomiaProspectingAPI.addLeadsToCampaign.mockResolvedValue(
      segmentResponse({
        campaign: null,
        blocked_count: 4,
        blocked_leads: [
          { id: 1, name: 'A', reason_code: 'no_phone' },
          { id: 2, name: 'B', reason_code: 'contact_blocked' },
          { id: 3, name: 'C', reason_code: 'discarded' },
          { id: 4, name: 'D', reason_code: 'algo_novo' },
        ],
      })
    );

    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(result(wrapper).text()).not.toContain('Campanha:');
    expect(
      wrapper.findAll('[data-test="campaign-blocked"]').map(item => item.text())
    ).toEqual([
      'A · Sem telefone',
      'B · Contato bloqueado',
      'C · Descartado',
      'D · Não pode entrar na campanha',
    ]);
  });

  it('motivos que só o servidor conhece: lead de outra conta, lead não pronto e código novo com o texto do servidor', async () => {
    const wrapper = await mountModal();
    AutonomiaProspectingAPI.addLeadsToCampaign.mockResolvedValue(
      segmentResponse({
        blocked_count: 3,
        blocked_leads: [
          { id: 900, name: null, reason_code: 'not_found', reason: 'x' },
          { id: 2, name: 'B', reason_code: 'not_ready', reason: 'y' },
          {
            id: 3,
            name: 'C',
            reason_code: 'outro_motivo',
            reason: 'Motivo explicado pelo servidor.',
          },
        ],
      })
    );

    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(
      wrapper.findAll('[data-test="campaign-blocked"]').map(item => item.text())
    ).toEqual([
      'Lead 900 · Lead não encontrado nesta conta',
      'B · Ainda não está pronto para campanha',
      'C · Motivo explicado pelo servidor.',
    ]);
  });

  it('ninguém elegível (422 do servidor): diz isso em texto e mostra o motivo de cada lead, sem o código cru', async () => {
    const wrapper = await mountModal();
    AutonomiaProspectingAPI.addLeadsToCampaign.mockRejectedValue({
      response: {
        status: 422,
        data: {
          // #682: a frase do servidor vem em error e o código em code.
          error: 'Frase do servidor.',
          code: 'prospecting.campaign.no_eligible_leads',
          payload: {
            segment: {
              eligible_count: 0,
              blocked_count: 1,
              blocked_leads: [
                {
                  id: 101,
                  name: 'Padaria Sol',
                  reason_code: 'no_whatsapp',
                  reason: 'Telefone sem WhatsApp confirmado.',
                },
              ],
            },
          },
        },
      },
    });

    await submit(wrapper).trigger('click');
    await flushPromises();

    const alert = wrapper.find('[role="alert"]').text();
    expect(alert).toBe('Nenhum lead da seleção pode entrar na campanha.');
    expect(wrapper.text()).not.toContain('prospecting.campaign');
    expect(
      wrapper.findAll('[data-test="campaign-blocked"]').map(item => item.text())
    ).toEqual(['Padaria Sol · Sem WhatsApp verificado']);
    expect(result(wrapper).exists()).toBe(false);
    expect(wrapper.emitted('done')).toBeUndefined();
  });

  it('recusa do servidor aparece na janela, sem resumo de sucesso, e deixa tentar de novo', async () => {
    const wrapper = await mountModal();
    AutonomiaProspectingAPI.addLeadsToCampaign.mockRejectedValue({
      response: { data: { error: 'Nenhum lead pode entrar na campanha.' } },
    });

    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'Nenhum lead pode entrar na campanha.'
    );
    expect(result(wrapper).exists()).toBe(false);
    expect(submit(wrapper).element.disabled).toBe(false);
    expect(wrapper.emitted('done')).toBeUndefined();
  });

  it('sem nome do segmento não manda', async () => {
    const wrapper = await mountModal();

    await wrapper.find('input[type="text"]').setValue('   ');

    expect(submit(wrapper).element.disabled).toBe(true);
  });

  it('enquanto manda, não deixa mandar de novo nem fechar', async () => {
    const wrapper = await mountModal();
    const pending = deferred();
    AutonomiaProspectingAPI.addLeadsToCampaign.mockReturnValue(pending.promise);

    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(submit(wrapper).element.disabled).toBe(true);
    await wrapper.find('[data-test="campaign-close"]').trigger('click');
    expect(wrapper.emitted('close')).toBeUndefined();

    pending.resolve(segmentResponse());
    await flushPromises();
    await wrapper.find('[data-test="campaign-close"]').trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('campanhas que não carregam deixam criar só o segmento', async () => {
    CampaignsAPI.get.mockRejectedValue(new Error('fora'));
    const wrapper = mount(CampaignSelectionModal, {
      props: { leads: LEADS, defaultSegmentName: 'padaria' },
      global: { stubs: { ChoiceSelect: ChoiceSelectStub } },
    });
    await flushPromises();

    expect(campaignChoice(wrapper).props('options')).toEqual([
      { value: '', label: 'Só criar o segmento, sem campanha' },
    ]);
    expect(wrapper.text()).toContain('Não foi possível carregar as campanhas.');
    expect(submit(wrapper).element.disabled).toBe(false);
  });

  // Sem campaign_manage o servidor recusaria a campanha, mas aceita o segmento
  // (authorize_campaign_update!, #682): a janela esconde a escolha e manda sem.
  it('sem poder escolher campanha, não pede as campanhas, esconde a escolha e cria só o segmento', async () => {
    const wrapper = mount(CampaignSelectionModal, {
      props: {
        leads: LEADS,
        defaultSegmentName: 'padaria',
        canChooseCampaign: false,
      },
      global: { stubs: { ChoiceSelect: ChoiceSelectStub } },
    });
    await flushPromises();
    AutonomiaProspectingAPI.addLeadsToCampaign.mockResolvedValue(
      segmentResponse({ campaign: null })
    );

    expect(CampaignsAPI.get).not.toHaveBeenCalled();
    expect(campaignChoice(wrapper)).toBeUndefined();
    expect(wrapper.text()).not.toContain('Campanha');
    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.addLeadsToCampaign).toHaveBeenCalledWith({
      leadIds: [101, 102, 103],
      campaignId: '',
      segmentName: 'padaria',
    });
    expect(result(wrapper).text()).toContain('1 lead(s) entraram no segmento');
  });
});
