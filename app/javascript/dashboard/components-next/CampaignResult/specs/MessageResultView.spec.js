import { mount, flushPromises, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import enResult from 'dashboard/i18n/locale/en/resultJourney.json';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import enDuasVersoes from 'dashboard/i18n/locale/en/duasVersoes.json';
import enReenvio from 'dashboard/i18n/locale/en/reenvioHorario.json';

const api = vi.hoisted(() => ({
  getResult: vi.fn(),
  getRecipients: vi.fn(),
  exportResult: vi.fn(),
  escolherVersao: vi.fn(),
}));
vi.mock('dashboard/api/campaignResults', () => ({ default: api }));
const alert = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alert }));
vi.mock(
  'dashboard/components-next/Campaigns/EmailProtection/presentation',
  () => ({
    downloadCsv: vi.fn(),
  })
);
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryBreakdown.vue',
  () => ({ default: { name: 'CampaignDeliveryBreakdown', render: () => null } })
);

const { default: MessageResultView } = await import('../MessageResultView.vue');

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const result = (overrides = {}) => ({
  campaign: {
    id: 5,
    channel: 'whatsapp_official',
    name: 'Renovação auto',
    status: 'completed',
    processing: false,
    inbox: { id: 1, name: 'Oficial' },
    scheduled_at: '2026-10-06T12:00:00Z',
    template_name: 'renovacao_auto_v2',
    audience: { id: 3, name: 'Auto vencendo' },
    ...overrides.campaign,
  },
  totals: {
    audience: 4,
    sent: 2,
    delivered: 2,
    read: 1,
    failed: 1,
    skipped: 1,
    queued: 0,
    replied: 1,
    ...overrides.totals,
  },
  filters: overrides.filters || [
    'queued',
    'sent',
    'delivered',
    'read',
    'failed',
    'skipped',
    'replied',
  ],
  crm: {
    source_id: 'campaign:whatsapp:11',
    enabled: true,
    deals: {
      cards: 3,
      won: 1,
      won_value: [{ currency: 'BRL', cents: 180000 }],
    },
  },
});

const rows = [
  {
    id: 1,
    contact: { id: 1, name: 'Ana', phone_number: '+55119****4321' },
    status: 'read',
    replied: true,
    message_content: 'Olá Ana',
    conversation_display_id: 42,
  },
  {
    id: 2,
    contact: { id: 2, name: 'Caio', phone_number: '+55319****4323' },
    status: 'failed',
    error_code: '131026',
    error_title: 'Número sem WhatsApp',
    conversation_display_id: null,
  },
];

const mountView = ({ channel = 'whatsapp_official', customRole } = {}) => {
  const dispatched = [];
  const store = createStore({
    getters: {
      getCurrentUser: () => ({
        accounts: [{ id: 1, permissions: customRole || [] }],
      }),
      getCurrentCustomRoleId: () => (customRole ? 7 : null),
      getCurrentAccountId: () => 1,
    },
    modules: {
      whatsappApiCampaigns: {
        namespaced: true,
        actions: {
          pause: (_, id) => dispatched.push(['pause', id]),
        },
      },
    },
  });
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: { ...enJourney, ...enResult, ...enDuasVersoes, ...enReenvio },
    },
    missingWarn: false,
    fallbackWarn: false,
  });
  const wrapper = mount(MessageResultView, {
    props: { channel, campaignId: '5' },
    global: {
      plugins: [store, i18n],
      stubs: {
        'router-link': {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
        Dialog: { template: '<div><slot /></div>' },
      },
    },
  });
  return { wrapper, dispatched };
};

describe('message campaign result (#1007, PRD §6.5, O2)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.getResult.mockResolvedValue({ data: { payload: result() } });
    api.getRecipients.mockResolvedValue({
      data: { payload: { rows, meta: { total_pages: 1 } } },
    });
    api.exportResult.mockResolvedValue({ data: new Blob(['csv']) });
  });

  it('shows every number of WhatsApp Oficial and the E1 sum', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    const kpis = wrapper
      .findAll('[data-kpi]')
      .map(item => [item.attributes('data-kpi'), item.text()]);
    expect(kpis.map(([key]) => key)).toEqual([
      'audience',
      'sent',
      'delivered',
      'read',
      'replied',
      'failed',
      'skipped',
    ]);
    expect(kpis[4][1]).toContain('marked in the CRM');
    expect(wrapper.find('[data-balance]').text()).toBe(
      'Sent 2 + Failed 1 + Skipped 1 + Queued 0 = Audience 4'
    );
    expect(wrapper.find('[data-balance]').classes()).not.toContain(
      'text-n-ruby-11'
    );
  });

  it('WhatsApp API has no Entregues nor Lidas', async () => {
    api.getResult.mockResolvedValue({
      data: {
        payload: result({
          campaign: { channel: 'whatsapp_api', status: 'running' },
          filters: ['queued', 'sent', 'failed', 'skipped', 'replied'],
        }),
      },
    });
    const { wrapper } = mountView({ channel: 'whatsapp_api' });
    await flushPromises();

    const keys = wrapper
      .findAll('[data-kpi]')
      .map(item => item.attributes('data-kpi'));
    expect(keys).toEqual(['audience', 'sent', 'replied', 'failed', 'skipped']);
    expect(wrapper.find('[data-tab="read"]').exists()).toBe(false);
  });

  it('"Ver no CRM" opens the Kanban filtered by the campaign mark (K6)', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    expect(wrapper.find('[data-crm-band]').text()).toContain(
      'Campaign: Renovação auto'
    );
    // #3063: what the campaign turned into in the CRM, with the R$ of the won cards.
    expect(wrapper.find('[data-crm-deals]').text()).toContain(
      '3 cards · 1 became a sale'
    );
    expect(wrapper.find('[data-crm-won-value]').text()).toBe(
      'R$1,800 in closed sales'
    );
    expect(
      JSON.parse(wrapper.find('[data-crm-link]').attributes('data-to'))
    ).toEqual({
      name: 'crm_kanban_index',
      query: { campaign_source_ids: 'campaign:whatsapp:11' },
    });
  });

  it('opens the conversation of who replied and shows code and reason (E3)', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    const links = wrapper.findAll('[data-open-conversation]');
    expect(links.length).toBeGreaterThan(0);
    expect(JSON.parse(links[0].attributes('data-to'))).toEqual({
      name: 'inbox_conversation',
      params: { conversation_id: 42 },
    });
    const table = wrapper.find('[data-people-rows]').text();
    expect(table).toContain('Número sem WhatsApp');
    expect(table).toContain('code 131026');
    expect(table).toContain('Replied');
  });

  it('downloads the result of the chosen tab (E4)', async () => {
    const { wrapper } = mountView();
    await flushPromises();

    await wrapper.find('[data-tab="failed"]').trigger('click');
    await flushPromises();
    expect(api.getRecipients).toHaveBeenLastCalledWith(
      'whatsapp_official',
      '5',
      { status: 'failed', page: 1 }
    );
    await wrapper.find('[data-export]').trigger('click');
    await flushPromises();

    expect(api.exportResult).toHaveBeenCalledWith('whatsapp_official', '5', {
      status: 'failed',
    });
  });

  it('A4: campaign_view sees the result but no download nor actions', async () => {
    api.getResult.mockResolvedValue({
      data: {
        payload: result({
          campaign: { channel: 'whatsapp_api', status: 'running' },
        }),
      },
    });
    const viewer = mountView({
      channel: 'whatsapp_api',
      customRole: ['campaign_view'],
    }).wrapper;
    const manager = mountView({ channel: 'whatsapp_api' }).wrapper;
    await flushPromises();

    expect(viewer.find('[data-kpi="sent"]').exists()).toBe(true);
    expect(viewer.find('[data-export]').exists()).toBe(false);
    expect(viewer.find('[data-action="pause"]').exists()).toBe(false);
    expect(manager.find('[data-export]').exists()).toBe(true);
    expect(manager.find('[data-action="pause"]').exists()).toBe(true);
    expect(manager.find('[data-action="cancel"]').exists()).toBe(true);
  });

  it('E2: while sending, shows the band and refreshes every 15 seconds', async () => {
    vi.useFakeTimers();
    api.getResult.mockResolvedValue({
      data: {
        payload: result({
          campaign: { status: 'processing', processing: true },
          totals: { queued: 3 },
        }),
      },
    });
    const { wrapper } = mountView();
    await flushPromises();

    expect(wrapper.find('[data-processing]').text()).toContain(
      'Still queued: 3'
    );
    expect(api.getResult).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(15000);
    expect(api.getResult).toHaveBeenCalledTimes(2);
    wrapper.unmount();
    vi.useRealTimers();
  });

  it('SMS without per-person records says so instead of an empty result', async () => {
    api.getResult.mockResolvedValue({
      data: {
        payload: result({
          campaign: { channel: 'sms' },
          totals: {
            audience: 0,
            sent: 0,
            delivered: 0,
            read: null,
            failed: 0,
            skipped: 0,
            replied: 0,
          },
        }),
      },
    });
    const { wrapper } = mountView({ channel: 'sms' });
    await flushPromises();

    expect(wrapper.find('[data-sms-partial]').exists()).toBe(true);
  });

  // #3099: o bloco das duas versões vem no resultado; escolher a versão do resto é disparo (campaign_send).
  describe('duas versões da mensagem', () => {
    const duasVersoes = {
      estado: 'esperando_voce',
      criterio: 'eu_escolho',
      escolhe_em: 1795000000,
      vencedora: null,
      escolhida_por: null,
      escolhida_em: null,
      resto: 1080,
      versoes: [
        {
          numero: 1,
          texto: 'Oi! Seu seguro vence logo.',
          receberam: 135,
          responderam: 11,
          compraram: 0,
          valor: null,
        },
        {
          numero: 2,
          texto: 'Seu seguro vence: quer renovar?',
          receberam: 135,
          responderam: 24,
          compraram: 0,
          valor: null,
        },
      ],
    };
    const comVersoes = () => ({ ...result(), duas_versoes: duasVersoes });

    it('mostra o resultado abaixo dos números e manda a versão escolhida para o resto', async () => {
      api.getResult.mockResolvedValue({ data: { payload: comVersoes() } });
      api.escolherVersao.mockResolvedValue({ data: { payload: duasVersoes } });
      const { wrapper } = mountView();
      await flushPromises();

      const bloco = wrapper.find('[data-duas-versoes-resultado]');
      expect(bloco.find('[data-situacao="esperando_voce"]').exists()).toBe(
        true
      );
      const cartao = bloco.find('[data-cartao-versao="2"]');
      await cartao.find('[data-escolher-versao]').trigger('click');
      await cartao.find('[data-sim-mandar]').trigger('click');
      await flushPromises();

      expect(api.escolherVersao).toHaveBeenCalledWith(
        'whatsapp_official',
        '5',
        2
      );
      // Mandou: o resultado é lido de novo, com a escolha gravada.
      expect(api.getResult).toHaveBeenCalledTimes(2);
    });

    it('outra versão já escolhida (422): avisa e recarrega o resultado', async () => {
      api.getResult.mockResolvedValue({ data: { payload: comVersoes() } });
      api.escolherVersao.mockRejectedValue({ response: { status: 422 } });
      const { wrapper } = mountView();
      await flushPromises();

      const cartao = wrapper.find('[data-cartao-versao="1"]');
      await cartao.find('[data-escolher-versao]').trigger('click');
      await cartao.find('[data-sim-mandar]').trigger('click');
      await flushPromises();

      expect(alert).toHaveBeenCalledWith(
        enDuasVersoes.DUAS_VERSOES.RESULTADO.JA_ESCOLHIDA
      );
      expect(api.getResult).toHaveBeenCalledTimes(2);
    });

    it('sem a chave de disparar, vê os números mas não escolhe', async () => {
      api.getResult.mockResolvedValue({ data: { payload: comVersoes() } });
      const { wrapper } = mountView({ customRole: ['campaign_view'] });
      await flushPromises();

      expect(wrapper.find('[data-duas-versoes-resultado]').exists()).toBe(true);
      expect(wrapper.find('[data-escolher-versao]').exists()).toBe(false);
      expect(wrapper.find('[data-sem-permissao]').text()).toBe(
        enDuasVersoes.DUAS_VERSOES.RESULTADO.SEM_PERMISSAO
      );
    });

    it('campanha sem duas versões não mostra o bloco', async () => {
      const { wrapper } = mountView();
      await flushPromises();
      expect(wrapper.find('[data-duas-versoes-resultado]').exists()).toBe(
        false
      );
    });
  });

  // #3101: a segunda mensagem do "Mandar de novo" no resultado da primeira.
  describe('segunda mensagem', () => {
    it('mostra quantos receberam e responderam, com o caminho para a campanha nova', async () => {
      api.getResult.mockResolvedValue({
        data: {
          payload: {
            ...result(),
            segunda_mensagem: {
              status: 'enviado',
              dias: 3,
              quem: 'nao_respondeu',
              previsto_em: 1764000000,
              campanha: {
                channel: 'whatsapp_official',
                id: 9,
                name: 'Renovação auto · second message',
                processing: false,
                receberam: 12,
                responderam: 1,
              },
            },
          },
        },
      });
      const { wrapper } = mountView();
      await flushPromises();

      const bloco = wrapper.get('[data-segunda-mensagem="enviado"]');
      expect(bloco.text()).toContain('Second message');
      expect(bloco.get('[data-frase]').text()).toBe('12 got it, 1 replied');
      expect(
        JSON.parse(bloco.get('[data-ver-segunda]').attributes('data-to'))
      ).toEqual({
        name: 'campaigns_journey_result',
        params: { channel: 'whatsapp_official', campaignId: '9' },
      });
    });

    it('campanha sem segunda mensagem não mostra o bloco', async () => {
      const { wrapper } = mountView();
      await flushPromises();
      expect(wrapper.find('[data-segunda-mensagem]').exists()).toBe(false);
    });
  });
});
