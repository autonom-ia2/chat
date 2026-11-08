import { computed } from 'vue';
import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AnunciosSemLogin from '../semLogin/AnunciosSemLogin.vue';
import MetaAdsAdDetail from '../components/MetaAdsAdDetail.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { panel: vi.fn(), panelAd: vi.fn(), panelList: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '6' }, query: {} }),
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name =>
    computed(() =>
      name === 'getCurrentAccountId'
        ? 6
        : () => ({ id: 6, timezone: 'America/Sao_Paulo' })
    ),
}));

// O Intl separa "R$" do número com espaço sem quebra.
const plain = text => text.split(' ').join(' ');

const INBOX = { id: 7, name: 'Vendas', phone: '+5511988887777' };

const result = overrides => ({
  enabled: true,
  official_inboxes: [INBOX],
  ad_touch: true,
  ...overrides,
});

// O painel sem gasto, como o servidor devolve (Panel::Report com source 'whatsapp').
const PANEL = {
  source: 'whatsapp',
  days: 30,
  currency: 'BRL',
  totals: {
    spend: null,
    conversations: 75,
    quotes: 20,
    open_quotes: 14,
    sales: 6,
    sales_value: 4300,
    cost_per_conversation: null,
    cost_per_sale: null,
    return_per_real: null,
  },
  ads: [
    {
      ad_id: '120',
      name: 'Seguro auto sem complicação',
      image_url: '/rails/active_storage/blobs/foto-guardada.png',
      thumbnail_url: 'https://scontent.fbcdn.net/miniatura.jpg',
      spend: null,
      conversations: 44,
      quotes: 12,
      sales: 4,
      cost_per_sale: null,
      verdict: null,
    },
  ],
  response_time: { median_seconds: 240, unanswered: 2, days: 30 },
};

const stubs = {
  Spinner: true,
  // O botão do relatório tem spec próprio (MetaAdsReportButton.spec.js).
  MetaAdsReportButton: true,
  RouterLink: {
    props: ['to'],
    template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
  },
};

const mountPage = async props => {
  const wrapper = mount(AnunciosSemLogin, {
    props: { result: result(), ...props },
    global: { stubs },
  });
  await flushPromises();
  return wrapper;
};

describe('Anúncios sem login (#1960, degrau 0)', () => {
  const globalPlugins = config.global.plugins;
  beforeAll(() => {
    config.global.plugins = [
      createI18n({
        legacy: false,
        locale: 'pt_BR',
        messages: { en, pt_BR: ptBR },
      }),
    ];
  });
  afterAll(() => {
    config.global.plugins = globalPlugins;
  });
  beforeEach(() => {
    vi.clearAllMocks();
    CrmMetaAdsConnectionAPI.panel.mockResolvedValue({ data: { panel: PANEL } });
  });

  describe('tela "pronto": WhatsApp oficial, sem anúncio em 90 dias', () => {
    it('shows the formatted phone and never loads the panel', async () => {
      const wrapper = await mountPage({
        result: result({ ad_touch: false }),
      });

      expect(wrapper.find('[data-ready-text]').text()).toContain(
        '(11) 98888-7777'
      );
      expect(CrmMetaAdsConnectionAPI.panel).not.toHaveBeenCalled();
    });

    it('opens the panel with marked example numbers, without opening ads or lists, and goes back', async () => {
      const wrapper = await mountPage({
        result: result({ ad_touch: false }),
      });

      await wrapper.find('[data-see-example]').trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-anuncios-exemplo-selo]').text()).toBe(
        'Exemplo'
      );
      expect(wrapper.find('[data-panel-headline]').text()).toBe(
        'Pelo WhatsApp, vieram 36 conversas de anúncio e 4 vendas.'
      );
      expect(wrapper.findAll('[data-panel-ad]')).toHaveLength(3);
      expect(wrapper.find('[data-panel-ad-open]').exists()).toBe(false);
      expect(wrapper.find('[data-panel-path-open]').exists()).toBe(false);
      expect(CrmMetaAdsConnectionAPI.panel).not.toHaveBeenCalled();

      await wrapper.find('[data-panel-period="7d"]').trigger('click');
      expect(wrapper.find('[data-panel-headline]').text()).toBe(
        'Pelo WhatsApp, vieram 9 conversas de anúncio e 1 venda.'
      );

      await wrapper.find('[data-anuncios-exemplo-voltar]').trigger('click');
      expect(wrapper.find('[data-ready-text]').exists()).toBe(true);
    });
  });

  describe('com gente de anúncio: o painel da conta conectada, sem gasto', () => {
    it('shows conversations, quotes and sales without spend, cost, verdict or confidence', async () => {
      const wrapper = await mountPage();

      expect(CrmMetaAdsConnectionAPI.panel).toHaveBeenCalledWith('30d');
      expect(wrapper.find('[data-panel-headline]').text()).toBe(
        'Pelo WhatsApp, vieram 75 conversas de anúncio e 6 vendas.'
      );
      expect(
        wrapper
          .findAll('[data-panel-path]')
          .map(step => step.attributes('data-panel-path'))
      ).toEqual(['SPEND', 'CONVERSATIONS', 'QUOTES', 'SALES']);
      // Sem gasto ainda (#2054): o investimento é o convite para conectar.
      expect(
        wrapper.find('[data-panel-path="SPEND"] [data-panel-connect]').exists()
      ).toBe(true);
      expect(wrapper.find('[data-panel-response-time]').exists()).toBe(true);
      expect(wrapper.find('[data-verdict]').exists()).toBe(false);
      expect(wrapper.find('[data-summary-confidence]').exists()).toBe(false);
      expect(plain(wrapper.find('[data-panel-ad="120"]').text())).not.toContain(
        'Investido'
      );
      expect(wrapper.find('[data-panel-ad-open="120"]').exists()).toBe(true);
      // 12 propostas, 4 já viraram venda: 8 abertas.
      expect(wrapper.find('[data-panel-ad="120"]').text()).toContain(
        '8 propostas abertas'
      );
    });

    it('shows the stored photo first and the Meta one when the stored does not open', async () => {
      const wrapper = await mountPage();
      const image = () => wrapper.find('[data-panel-ad-image]');

      expect(image().attributes('src')).toBe(
        '/rails/active_storage/blobs/foto-guardada.png'
      );
      await image().trigger('error');
      expect(image().attributes('src')).toBe(
        'https://scontent.fbcdn.net/miniatura.jpg'
      );
      await image().trigger('error');
      expect(image().exists()).toBe(false);
      expect(wrapper.find('[data-panel-ad-placeholder]').exists()).toBe(true);
    });

    it('opens the list of conversations of the period', async () => {
      CrmMetaAdsConnectionAPI.panelList.mockResolvedValue({
        data: {
          list: { step: 'conversations', days: 30, total: 0, items: [] },
        },
      });
      const wrapper = await mountPage();

      await wrapper
        .find('[data-panel-path-open="conversations"]')
        .trigger('click');
      await flushPromises();

      expect(CrmMetaAdsConnectionAPI.panelList).toHaveBeenCalledWith(
        'conversations',
        '30d'
      );
    });
  });

  describe('dentro do anúncio, sem gasto', () => {
    const AD = {
      ...PANEL.ads[0],
      days: 30,
      currency: 'BRL',
      reason: null,
      daily: [
        { date: '2026-10-19', spend: 0, conversations: 2 },
        { date: '2026-10-20', spend: 0, conversations: 1 },
      ],
      quotes_list: [],
      people: [
        {
          conversation_id: 91,
          title: 'Marina Souza',
          status: 'won',
          value: 400,
          stage_name: 'Fechado',
          touched_at: '2026-10-20T02:30:00Z',
          answered: true,
        },
        {
          conversation_id: 92,
          title: 'Ricardo Reis',
          status: null,
          value: null,
          stage_name: null,
          touched_at: '2026-10-19T15:00:00Z',
          answered: false,
        },
      ],
    };

    it('lists who came from the ad, in the account time zone, with situation and the conversation', async () => {
      CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue({ data: { ad: AD } });
      const wrapper = mount(MetaAdsAdDetail, {
        props: { adId: '120', period: '30d' },
        global: { stubs },
      });
      await flushPromises();

      const people = wrapper.findAll('[data-ad-detail-person]');
      expect(people.map(row => row.attributes('data-situation'))).toEqual([
        'BOUGHT',
        'NO_ANSWER',
      ]);
      // 02:30 UTC de 20/10 ainda é 19/10 em São Paulo.
      expect(plain(people[0].text())).toContain('19/10');
      expect(plain(people[0].text())).toContain('Comprou R$ 400');
      expect(people[1].find('a').attributes('data-to')).toContain('92');
      expect(wrapper.find('[data-ad-detail-image]').attributes('src')).toBe(
        '/rails/active_storage/blobs/foto-guardada.png'
      );
      expect(wrapper.find('[data-verdict]').exists()).toBe(false);
      expect(wrapper.find('[data-ad-detail-why]').exists()).toBe(false);
      expect(wrapper.find('[data-ad-detail-tile="SPEND"]').exists()).toBe(
        false
      );
      expect(wrapper.find('[data-ad-detail-chart-scale]').exists()).toBe(false);
      expect(wrapper.find('[data-ad-detail-quotes]').exists()).toBe(false);
    });
  });

  describe('conectar a conta de anúncios (#2054)', () => {
    const ConectarStub = {
      name: 'ConectarAnuncios',
      props: ['connection', 'resume'],
      emits: ['back', 'connected'],
      template: '<div data-conectar-stub />',
    };
    const mountWithConnect = props =>
      mount(AnunciosSemLogin, {
        props: { result: result(), connection: { partner: {} }, ...props },
        global: { stubs: { ...stubs, ConectarAnuncios: ConectarStub } },
      });

    it('"Ver quanto gastei" opens the connection and its end goes back to the page', async () => {
      const wrapper = mountWithConnect();
      await flushPromises();

      await wrapper.find('[data-panel-connect]').trigger('click');
      const connect = wrapper.findComponent(ConectarStub);
      expect(connect.exists()).toBe(true);
      expect(connect.props('resume')).toBeNull();

      connect.vm.$emit('connected');
      expect(wrapper.emitted('connected')).toHaveLength(1);
    });

    it('a connection stopped in the middle shows the notice and continues from where it stopped', async () => {
      const wrapper = mountWithConnect({
        result: result({
          connection_state: 'choosing',
          connection_mode: 'facebook_login',
        }),
      });
      await flushPromises();

      expect(wrapper.find('[data-anuncios-conexao="choosing"]').exists()).toBe(
        true
      );
      await wrapper.find('[data-anuncios-conexao-continuar]').trigger('click');

      expect(wrapper.findComponent(ConectarStub).props('resume')).toEqual({
        state: 'choosing',
        mode: 'facebook_login',
      });
    });

    it('with nobody from an ad yet, the "ready" screen also connects (#2190)', async () => {
      const wrapper = mountWithConnect({ result: result({ ad_touch: false }) });
      await flushPromises();

      expect(wrapper.find('[data-see-example]').exists()).toBe(true);
      await wrapper
        .find('[data-anuncios-vazio-conectar-botao]')
        .trigger('click');

      expect(wrapper.findComponent(ConectarStub).exists()).toBe(true);
      expect(wrapper.find('[data-anuncios-vazio]').exists()).toBe(false);

      wrapper.findComponent(ConectarStub).vm.$emit('back');
      await flushPromises();
      expect(
        wrapper.find('[data-anuncios-vazio-conectar-botao]').exists()
      ).toBe(true);
    });

    it('with a connection stopped in the middle, the "ready" screen keeps only the notice (#2190)', async () => {
      const wrapper = mountWithConnect({
        result: result({
          ad_touch: false,
          connection_state: 'choosing',
          connection_mode: 'facebook_login',
        }),
      });
      await flushPromises();

      expect(wrapper.find('[data-anuncios-conexao="choosing"]').exists()).toBe(
        true
      );
      expect(wrapper.find('[data-anuncios-vazio-conectar]').exists()).toBe(
        false
      );
    });

    it('read-only on the "ready" screen does not see the way to connect (#2190)', async () => {
      const wrapper = mountWithConnect({
        readOnly: true,
        result: result({ ad_touch: false }),
      });
      await flushPromises();

      expect(wrapper.find('[data-see-example]').exists()).toBe(true);
      expect(wrapper.find('[data-anuncios-vazio-conectar]').exists()).toBe(
        false
      );
    });

    it('read-only sees neither the notice nor the way to connect', async () => {
      const wrapper = mountWithConnect({
        readOnly: true,
        result: result({
          connection_state: 'broken',
          connection_mode: 'partner',
        }),
      });
      await flushPromises();

      expect(wrapper.find('[data-anuncios-conexao]').exists()).toBe(false);
      expect(wrapper.find('[data-panel-connect]').exists()).toBe(false);
    });
  });

  it('has the same keys in en and pt_BR', () => {
    const keys = (node, prefix = '') =>
      Object.entries(node).flatMap(([key, value]) =>
        typeof value === 'object'
          ? keys(value, `${prefix}${key}.`)
          : [`${prefix}${key}`]
      );
    expect(keys(en.CRM_KANBAN.META_ADS_HUB.SEM_LOGIN)).toEqual(
      keys(ptBR.CRM_KANBAN.META_ADS_HUB.SEM_LOGIN)
    );
    expect(ptBR.CRM_KANBAN.META_ADS_HUB.PAGE.TITLE).toBe('Anúncios');
    expect(en.CRM_KANBAN.META_ADS_HUB.PAGE.TITLE).toBe('Ads');
  });
});
