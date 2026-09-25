// Janela "Enviar ao CRM" (#680), com o texto real: escolha de funil e estágio,
// frase de confirmação, estado vazio sem funil, envio em lotes de 30 e resumo
// honesto (criados, já existentes, falhas com motivo). Portada do modal de
// envio do Orth (BuscaClient.tsx).
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { isFixedPanelOpen } from 'dashboard/composables/useFixedPanelState';
import CrmSendModal from '../../components/crm/CrmSendModal.vue';
import {
  ChoiceSelectStub,
  PIPELINES,
  STAGES_BY_PIPELINE,
  deferred,
} from '../support/searchPageHarness';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: { createCrmCards: vi.fn() },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

withFullI18n();

const leadsNamed = count =>
  Array.from({ length: count }, (_, index) => ({
    id: index + 1,
    name: `Lead ${index + 1}`,
  }));

const createdFor = leadIds => ({
  data: {
    payload: {
      created: leadIds.map(leadId => ({
        lead_id: leadId,
        card_id: leadId * 10,
        contact_id: leadId * 100,
        company_id: 7,
      })),
      existing: [],
      failed: [],
    },
  },
});

const mountModal = async ({
  leads = leadsNamed(2),
  pipelines = PIPELINES,
  suggestedPipelineId = '',
  suggestedStageId = '',
} = {}) => {
  CrmKanbanAPI.getPipelines.mockResolvedValue({
    data: { payload: pipelines },
  });
  CrmKanbanAPI.getStages.mockImplementation(pipelineId =>
    Promise.resolve({
      data: { payload: STAGES_BY_PIPELINE[pipelineId] || [] },
    })
  );
  const wrapper = mount(CrmSendModal, {
    props: { leads, suggestedPipelineId, suggestedStageId },
    global: { stubs: { ChoiceSelect: ChoiceSelectStub } },
  });
  await flushPromises();
  return wrapper;
};

const choice = (wrapper, ariaLabel) =>
  wrapper
    .findAllComponents(ChoiceSelectStub)
    .find(item => item.props('ariaLabel') === ariaLabel);

const choose = async (wrapper, ariaLabel, value) => {
  const item = choice(wrapper, ariaLabel);
  item.vm.$emit('update:modelValue', value);
  item.vm.$emit('change', value);
  await flushPromises();
};

const sendButton = wrapper => wrapper.find('[data-test="crm-send-submit"]');
const summary = wrapper => wrapper.find('[data-test="crm-send-summary"]');

describe('CrmSendModal', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('é uma janela com título e avisa o lançador do Guia enquanto aberta', async () => {
    const wrapper = await mountModal();

    const dialog = wrapper.find('[role="dialog"]');
    expect(dialog.attributes('aria-modal')).toBe('true');
    expect(wrapper.find('h2').text()).toBe('Enviar ao CRM');
    expect(isFixedPanelOpen.value).toBe(true);

    wrapper.unmount();
    expect(isFixedPanelOpen.value).toBe(false);
  });

  it('usa o destino da busca como sugestão e mostra a frase de confirmação', async () => {
    const wrapper = await mountModal({
      leads: leadsNamed(3),
      suggestedPipelineId: 4,
      suggestedStageId: 41,
    });

    expect(choice(wrapper, 'Funil').props('modelValue')).toBe(4);
    expect(choice(wrapper, 'Funil').props('options')).toEqual([
      { value: 3, label: 'Vendas' },
      { value: 4, label: 'Parcerias' },
    ]);
    expect(choice(wrapper, 'Estágio').props('modelValue')).toBe(41);
    expect(wrapper.text()).toContain(
      'Enviando 3 lead(s) para o funil Parcerias, estágio Triagem.'
    );
    expect(sendButton(wrapper).element.disabled).toBe(false);
  });

  it('com mais de um funil e sem sugestão, não escolhe por você', async () => {
    const wrapper = await mountModal();

    expect(choice(wrapper, 'Funil').props('modelValue')).toBe('');
    expect(choice(wrapper, 'Estágio').props('options')).toEqual([]);
    expect(wrapper.text()).not.toContain('Enviando 2 lead(s)');
    expect(wrapper.text()).toContain(
      'Escolha o funil e o estágio para onde os leads vão.'
    );
    expect(sendButton(wrapper).element.disabled).toBe(true);
  });

  it('com um funil só, já escolhe ele e o primeiro estágio', async () => {
    const wrapper = await mountModal({ pipelines: [PIPELINES[0]] });

    expect(choice(wrapper, 'Funil').props('modelValue')).toBe(3);
    expect(choice(wrapper, 'Estágio').props('modelValue')).toBe(31);
    expect(wrapper.text()).toContain(
      'Enviando 2 lead(s) para o funil Vendas, estágio Novo.'
    );
  });

  it('sugestão que não existe mais é ignorada', async () => {
    const wrapper = await mountModal({
      suggestedPipelineId: 99,
      suggestedStageId: 991,
    });

    expect(choice(wrapper, 'Funil').props('modelValue')).toBe('');
    expect(CrmKanbanAPI.getStages).not.toHaveBeenCalled();
  });

  it('trocar o funil carrega os estágios dele e escolhe o primeiro', async () => {
    const wrapper = await mountModal();

    await choose(wrapper, 'Funil', 3);

    expect(CrmKanbanAPI.getStages).toHaveBeenCalledWith(3);
    expect(choice(wrapper, 'Estágio').props('options')).toEqual([
      { value: 31, label: 'Novo' },
      { value: 32, label: 'Contato' },
    ]);
    expect(choice(wrapper, 'Estágio').props('modelValue')).toBe(31);

    await choose(wrapper, 'Estágio', 32);
    expect(wrapper.text()).toContain(
      'Enviando 2 lead(s) para o funil Vendas, estágio Contato.'
    );
  });

  it('sem funil no CRM, explica e leva para criar um, sem botão de enviar', async () => {
    const wrapper = await mountModal({ pipelines: [] });

    expect(wrapper.text()).toContain('Nenhum funil no CRM');
    expect(wrapper.text()).toContain(
      'Os leads entram no CRM como cards de um funil.'
    );
    const link = wrapper.find('[data-test="crm-send-create-pipeline"]');
    expect(link.text()).toBe('Criar funil no CRM');
    expect(link.attributes('href')).toBe('/app/accounts/1/crm');
    expect(sendButton(wrapper).exists()).toBe(false);
    expect(choice(wrapper, 'Funil')).toBeUndefined();
  });

  it('CRM fora do ar ou desligado: diz que não carregou, sem fingir que não há funil', async () => {
    CrmKanbanAPI.getPipelines.mockRejectedValue({
      response: { status: 422, data: { error: 'CRM is disabled' } },
    });
    const wrapper = mount(CrmSendModal, {
      props: { leads: leadsNamed(1) },
      global: { stubs: { ChoiceSelect: ChoiceSelectStub } },
    });
    await flushPromises();

    expect(wrapper.text()).toContain(
      'Não foi possível carregar os funis do CRM.'
    );
    expect(wrapper.text()).not.toContain('Nenhum funil no CRM');
    expect(
      wrapper.find('[data-test="crm-send-create-pipeline"]').attributes('href')
    ).toBe('/app/accounts/1/crm');
    expect(sendButton(wrapper).exists()).toBe(false);
  });

  it('manda 65 leads em lotes de 30 e mostra o resumo dos criados', async () => {
    const wrapper = await mountModal({
      leads: leadsNamed(65),
      suggestedPipelineId: 3,
      suggestedStageId: 31,
    });
    AutonomiaProspectingAPI.createCrmCards.mockImplementation(({ leadIds }) =>
      Promise.resolve(createdFor(leadIds))
    );

    await sendButton(wrapper).trigger('click');
    await flushPromises();

    const calls = AutonomiaProspectingAPI.createCrmCards.mock.calls.map(
      ([params]) => params
    );
    expect(calls.map(params => params.leadIds.length)).toEqual([30, 30, 5]);
    expect(calls[0]).toMatchObject({ pipelineId: 3, stageId: 31 });
    expect(calls[2].leadIds).toEqual([61, 62, 63, 64, 65]);
    expect(summary(wrapper).text()).toContain('Envio concluído');
    expect(summary(wrapper).text()).toContain('65 card(s) criado(s)');
    expect(summary(wrapper).text()).not.toContain('falha');
    expect(wrapper.emitted('sent')[0][0].created).toHaveLength(65);
  });

  it('mostra quanto já foi enquanto envia e não deixa fechar no meio', async () => {
    const wrapper = await mountModal({
      leads: leadsNamed(31),
      suggestedPipelineId: 3,
      suggestedStageId: 31,
    });
    const second = deferred();
    AutonomiaProspectingAPI.createCrmCards
      .mockImplementationOnce(({ leadIds }) =>
        Promise.resolve(createdFor(leadIds))
      )
      .mockReturnValueOnce(second.promise);

    await sendButton(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Enviando 30 de 31...');
    const closeButton = wrapper.find('[data-test="crm-send-close"]');
    expect(closeButton.element.disabled).toBe(true);

    second.resolve(createdFor([31]));
    await flushPromises();
    expect(summary(wrapper).text()).toContain('31 card(s) criado(s)');
  });

  it('resumo junta criados, já existentes e falhas com o motivo de cada lead', async () => {
    const wrapper = await mountModal({
      leads: leadsNamed(4),
      suggestedPipelineId: 3,
      suggestedStageId: 31,
    });
    AutonomiaProspectingAPI.createCrmCards.mockResolvedValue({
      data: {
        payload: {
          created: [{ lead_id: 1, card_id: 10, contact_id: 100 }],
          existing: [{ lead_id: 2, card_id: 20 }],
          failed: [
            {
              lead_id: 3,
              reason_code: 'invalid',
              message: 'Telefone inválido para o contato',
            },
            { lead_id: 4, reason_code: 'not_found', message: null },
          ],
        },
      },
    });

    await sendButton(wrapper).trigger('click');
    await flushPromises();

    const text = summary(wrapper).text();
    expect(text).toContain('Envio concluído com falhas');
    expect(text).toContain('1 card(s) criado(s)');
    expect(text).toContain('1 já estava(m) no CRM');
    expect(text).toContain('2 falha(s)');
    const failures = wrapper
      .findAll('[data-test="crm-send-failure"]')
      .map(item => item.text());
    expect(failures).toEqual([
      'Lead 3 · Telefone inválido para o contato',
      'Lead 4 · Lead não encontrado nesta conta.',
    ]);
  });

  it('quando tudo falha, nunca diz que criou', async () => {
    const wrapper = await mountModal({
      leads: leadsNamed(2),
      suggestedPipelineId: 3,
      suggestedStageId: 31,
    });
    AutonomiaProspectingAPI.createCrmCards.mockRejectedValue({
      response: { data: { error: 'Estágio não pertence ao funil' } },
    });

    await sendButton(wrapper).trigger('click');
    await flushPromises();

    const text = summary(wrapper).text();
    expect(text).toContain('Nenhum lead foi enviado');
    expect(text).not.toContain('criado');
    expect(text).not.toContain('Envio concluído');
    expect(
      wrapper.findAll('[data-test="crm-send-failure"]').map(item => item.text())
    ).toEqual([
      'Lead 1 · Estágio não pertence ao funil',
      'Lead 2 · Estágio não pertence ao funil',
    ]);
  });

  it('sem resposta do servidor, a falha usa o texto da tela', async () => {
    const wrapper = await mountModal({
      leads: leadsNamed(1),
      suggestedPipelineId: 3,
      suggestedStageId: 31,
    });
    AutonomiaProspectingAPI.createCrmCards.mockRejectedValue(
      new Error('Network Error')
    );

    await sendButton(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-test="crm-send-failure"]').text()).toBe(
      'Lead 1 · Não foi possível enviar. Tente de novo.'
    );
  });

  it('fechar e cancelar avisam quem abriu', async () => {
    const wrapper = await mountModal();

    await wrapper.find('[data-test="crm-send-close"]').trigger('click');
    await wrapper.find('[data-test="crm-send-cancel"]').trigger('click');

    expect(wrapper.emitted('close')).toHaveLength(2);
  });
});
