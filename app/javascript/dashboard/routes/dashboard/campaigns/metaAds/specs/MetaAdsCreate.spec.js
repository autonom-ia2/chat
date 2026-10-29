import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsCreate from '../components/MetaAdsCreate.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { esquecerTentativas } from '../criacaoNaMeta';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    createOptions: vi.fn(),
    createAd: vi.fn(),
    uploadMedia: vi.fn(),
    setAdStatus: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const routing = vi.hoisted(() => ({ replace: vi.fn(), push: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '18' }, query: {} }),
  useRouter: () => routing,
}));
vi.mock('../useMetaAdsFacebookLogin', async () => {
  const { ref } = await import('vue');
  return {
    useMetaAdsFacebookLogin: () => ({
      isConnecting: ref(false),
      connect: vi.fn(),
    }),
  };
});

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR';

const OPTIONS = {
  needs_login: false,
  facebook_login: { app_id: '1', api_version: 'v23.0', configuration_id: '2' },
  kinds: ['ad'],
  pages: [{ id: '110000000002161', name: 'Loja' }],
  instagram: null,
  whatsapp_numbers: [
    { id: '+5511900002161', name: 'Loja', phone: '+5511900002161' },
  ],
  posts: [],
  images: [{ hash: 'h1', url: 'https://img/1.jpg', width: 600, height: 600 }],
  currency: 'BRL',
  // Hoje no fuso da conta de anúncios, como o servidor manda: longe do relógio do teste, para provar que vale este.
  today: '2030-01-15',
  time_zone: 'America/Sao_Paulo',
  min_daily: 6,
  max_daily: 500,
  destinations: ['WHATSAPP', 'WEBSITE'],
  placements_by_destination: {
    WHATSAPP: ['AUTO'],
    WEBSITE: ['AUTO', 'INSTAGRAM', 'FACEBOOK'],
  },
};

const CREATED = {
  ad_id: '120000000000990001',
  name: 'Bolo',
  status: 'PAUSED',
  budget: {
    kind: 'daily',
    amount: 20,
    currency: 'BRL',
    start_time: '2026-10-27',
    end_time: null,
    active_ads_count: 0,
  },
};

// O Dialog real abre um <dialog> nativo (e lê a loja); aqui só mostra o conteúdo.
const DialogStub = {
  methods: { open() {}, close() {} },
  template: '<div data-dialog />',
};
const STUBS = { Spinner: true, RouterLink: true, Dialog: DialogStub };

let mounted = null;
const mountCreate = async (options = OPTIONS) => {
  CrmMetaAdsConnectionAPI.createOptions.mockResolvedValue({
    data: { options },
  });
  mounted = mount(MetaAdsCreate, {
    global: {
      mocks: { $t: key => key },
      stubs: STUBS,
    },
  });
  await flushPromises();
  return mounted;
};

const step = wrapper =>
  wrapper.find('[data-create-form]').attributes('data-create-step');
const submit = async wrapper => {
  await wrapper.find('[data-create-form]').trigger('submit');
  await flushPromises();
};

// Do primeiro passo até a conferência, com a foto de um anúncio antigo (já tem `hash`, não sobe nada).
const fillUntilReview = async wrapper => {
  await wrapper.find('input[data-create-offer]').setValue('bolo de pote');
  await wrapper.find('[data-create-media-library-toggle]').trigger('click');
  await wrapper.find('[data-create-image="h1"]').trigger('click');
  await submit(wrapper);
  await wrapper.find('[data-create-special="false"]').trigger('click');
  await submit(wrapper);
  await submit(wrapper);
  expect(step(wrapper)).toBe('REVIEW');
};

const refusal = (status, data) =>
  Object.assign(new Error('refused'), { response: { status, data } });

describe('Anúncios da Meta · anúncio novo (#2198)', () => {
  beforeEach(() => {
    esquecerTentativas();
    let count = 0;
    vi.spyOn(crypto, 'randomUUID').mockImplementation(() => {
      count += 1;
      return `key-${count}`;
    });
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
    vi.restoreAllMocks();
  });

  it('with only one kind offered, enters it directly, without "What to do"', async () => {
    const wrapper = await mountCreate();

    expect(CrmMetaAdsConnectionAPI.createOptions).toHaveBeenCalledTimes(1);
    expect(step(wrapper)).toBe('CONTENT');
    expect(wrapper.find('[data-create-kind]').exists()).toBe(false);
    expect(wrapper.find('[data-create-back]').text()).toBe(
      `${KEY}.BACK_TO_PANEL`
    );
  });

  it('without a confirmed destination, shows the kind as unavailable with the reason', async () => {
    const wrapper = await mountCreate({ ...OPTIONS, destinations: [] });

    expect(step(wrapper)).toBe('KIND');
    expect(wrapper.find('[data-create-kind-unavailable="ad"]').exists()).toBe(
      true
    );
  });

  it('asks to sign in again before anything when the token cannot create', async () => {
    const wrapper = await mountCreate({ ...OPTIONS, needs_login: true });

    expect(
      wrapper.find('[data-create-blocker]').attributes('data-create-blocker')
    ).toBe('LOGIN');
  });

  it('an ad account in another currency stops before the steps: limits and values are in reais', async () => {
    const wrapper = await mountCreate({ ...OPTIONS, currency: 'USD' });

    expect(
      wrapper.find('[data-create-blocker]').attributes('data-create-blocker')
    ).toBe('CURRENCY');
    expect(wrapper.find('[data-create-form]').exists()).toBe(false);
  });

  it('without a confirmed currency, never assumes reais', async () => {
    const wrapper = await mountCreate({ ...OPTIONS, currency: null });

    expect(
      wrapper.find('[data-create-blocker]').attributes('data-create-blocker')
    ).toBe('CURRENCY');
  });

  it('Meta down while reading permissions (422 meta_unavailable) is a failure to retry, not a sign-in', async () => {
    CrmMetaAdsConnectionAPI.createOptions
      .mockRejectedValueOnce(refusal(422, { error: 'meta_unavailable' }))
      .mockResolvedValueOnce({ data: { options: OPTIONS } });
    mounted = mount(MetaAdsCreate, {
      global: { mocks: { $t: key => key }, stubs: STUBS },
    });
    await flushPromises();

    expect(mounted.find('[data-create-failed]').exists()).toBe(true);
    expect(mounted.find('[data-create-blocker]').exists()).toBe(false);

    await mounted.find('[data-create-failed] button').trigger('click');
    await flushPromises();
    expect(step(mounted)).toBe('CONTENT');
  });

  it('without an ad account (404 not_connected) asks to choose it, never "could not reach Meta" (#2338)', async () => {
    CrmMetaAdsConnectionAPI.createOptions.mockRejectedValue(
      refusal(404, { error: 'not_connected' })
    );
    mounted = mount(MetaAdsCreate, {
      global: { mocks: { $t: key => key }, stubs: STUBS },
    });
    await flushPromises();

    expect(mounted.find('[data-create-failed]').exists()).toBe(false);
    expect(mounted.find('[data-create-blocker]').attributes()).toMatchObject({
      'data-create-blocker': 'NO_AD_ACCOUNT',
    });
    expect(mounted.text()).toContain(`${KEY}.BLOCKERS.NO_AD_ACCOUNT.TITLE`);

    routing.replace.mockClear();
    await mounted.find('[data-create-blocker-action]').trigger('click');
    expect(routing.replace).toHaveBeenCalledWith({
      query: { aba: 'conexao', volta: 'criar' },
    });
  });

  it('a failed read says so and lets the person try again', async () => {
    CrmMetaAdsConnectionAPI.createOptions.mockRejectedValue(new Error('down'));
    mounted = mount(MetaAdsCreate, {
      global: { mocks: { $t: key => key }, stubs: STUBS },
    });
    await flushPromises();

    expect(mounted.find('[data-create-failed]').exists()).toBe(true);
  });

  it('creates the paused ad with what the screen showed, then offers to activate', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockResolvedValue({ data: CREATED });
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);

    await submit(wrapper);

    expect(CrmMetaAdsConnectionAPI.createAd).toHaveBeenCalledTimes(1);
    expect(CrmMetaAdsConnectionAPI.createAd).toHaveBeenCalledWith(
      expect.objectContaining({
        idempotency_key: 'key-1',
        destination: 'WHATSAPP',
        page_id: '110000000002161',
        whatsapp_number: '+5511900002161',
        site_url: null,
        text: `${KEY}.CONTENT.TEXT_FROM_OFFER.WHATSAPP`,
        placement: 'AUTO',
        region: 'BR',
        states: [],
        age_min: 18,
        age_max: 65,
        special_category: false,
        daily_amount: '20.00',
        start_date: '2030-01-15',
        end_date: '',
        media: { kind: 'image', hash: 'h1' },
        cards: [],
      })
    );
    expect(wrapper.find('[data-create-done]').exists()).toBe(true);
    expect(wrapper.find('[data-ad-status-toggle]').exists()).toBe(true);
  });

  // #2354: anúncio novo passa pela análise da Meta antes; o cartão de criado avisa em vez de oferecer o Ativar.
  it('a new ad still under Meta review shows the review note instead of activate', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockResolvedValue({
      data: { ...CREATED, in_review: true },
    });
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);

    await submit(wrapper);

    expect(wrapper.find('[data-create-done]').exists()).toBe(true);
    expect(wrapper.find('[data-ad-status-toggle]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-status-review]').exists()).toBe(true);
  });

  it('sends the same idempotency key again after a network failure of the same attempt', async () => {
    CrmMetaAdsConnectionAPI.createAd
      .mockRejectedValueOnce(new Error('Network Error'))
      .mockResolvedValueOnce({ data: CREATED });
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);

    await submit(wrapper);
    expect(wrapper.find('[data-create-error]').text()).toBe(
      `${KEY}.ERRORS.NETWORK`
    );
    await submit(wrapper);

    const keys = CrmMetaAdsConnectionAPI.createAd.mock.calls.map(
      ([body]) => body.idempotency_key
    );
    expect(keys).toEqual(['key-1', 'key-1']);
    expect(wrapper.find('[data-create-done]').exists()).toBe(true);
  });

  it('keeps the key while the server says the same attempt is still in progress (409)', async () => {
    CrmMetaAdsConnectionAPI.createAd
      .mockRejectedValueOnce(refusal(409, { error: 'in_progress' }))
      .mockResolvedValueOnce({ data: CREATED });
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);

    await submit(wrapper);
    expect(wrapper.find('[data-create-error]').text()).toBe(
      `${KEY}.ERRORS.IN_PROGRESS`
    );
    await submit(wrapper);

    const keys = CrmMetaAdsConnectionAPI.createAd.mock.calls.map(
      ([body]) => body.idempotency_key
    );
    expect(keys).toEqual(['key-1', 'key-1']);
  });

  it('leaving the flow forgets the attempt: coming back starts a new one', async () => {
    CrmMetaAdsConnectionAPI.createAd
      .mockRejectedValueOnce(new Error('Network Error'))
      .mockResolvedValueOnce({ data: CREATED });
    const first = await mountCreate();
    await fillUntilReview(first);
    await submit(first);
    first.unmount();

    const again = await mountCreate();
    await fillUntilReview(again);
    await submit(again);

    const keys = CrmMetaAdsConnectionAPI.createAd.mock.calls.map(
      ([body]) => body.idempotency_key
    );
    expect(keys).toEqual(['key-1', 'key-2']);
  });

  it('a refusal that left something at Meta (nothing_created false) keeps the same key', async () => {
    CrmMetaAdsConnectionAPI.createAd
      .mockRejectedValueOnce(
        refusal(422, { error: 'meta_refused', nothing_created: false })
      )
      .mockResolvedValueOnce({ data: CREATED });
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);

    await submit(wrapper);
    await submit(wrapper);

    const keys = CrmMetaAdsConnectionAPI.createAd.mock.calls.map(
      ([body]) => body.idempotency_key
    );
    expect(keys).toEqual(['key-1', 'key-1']);
  });

  it('a refusal with nothing created ends the attempt: tapping again uses a new key', async () => {
    CrmMetaAdsConnectionAPI.createAd
      .mockRejectedValueOnce(
        refusal(422, { error: 'meta_unavailable', nothing_created: true })
      )
      .mockResolvedValueOnce({ data: CREATED });
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);

    await submit(wrapper);
    await submit(wrapper);

    const keys = CrmMetaAdsConnectionAPI.createAd.mock.calls.map(
      ([body]) => body.idempotency_key
    );
    expect(keys).toEqual(['key-1', 'key-2']);
  });

  it('says "Nothing was created" only when the server guarantees it', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockRejectedValueOnce(
      refusal(422, { error: 'meta_refused', nothing_created: true })
    );
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);
    await submit(wrapper);

    expect(wrapper.find('[data-create-error]').text()).toBe(
      `${KEY}.ERRORS.META_REFUSED ${KEY}.ERRORS.NOTHING_CREATED`
    );
  });

  it('unconfirmed at Meta: says to check Ads Manager, never "Nothing was created"', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockRejectedValueOnce(
      refusal(422, { error: 'unconfirmed', nothing_created: false })
    );
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);
    await submit(wrapper);

    expect(wrapper.find('[data-create-error]').text()).toBe(
      `${KEY}.ERRORS.UNCONFIRMED`
    );
  });

  it('only the person releases creating again after checking: same key, with the release', async () => {
    CrmMetaAdsConnectionAPI.createAd
      .mockRejectedValueOnce(
        refusal(422, { error: 'unconfirmed', nothing_created: false })
      )
      .mockResolvedValueOnce({ data: CREATED });
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);
    await submit(wrapper);

    expect(wrapper.find('[data-create-recreate]').exists()).toBe(true);
    await wrapper.find('[data-create-recreate]').trigger('click');
    await flushPromises();

    const [first, second] = CrmMetaAdsConnectionAPI.createAd.mock.calls.map(
      ([body]) => body
    );
    expect(first.recreate_unconfirmed).toBeUndefined();
    expect(second).toMatchObject({
      idempotency_key: first.idempotency_key,
      recreate_unconfirmed: true,
    });
    expect(wrapper.find('[data-create-done]').exists()).toBe(true);
  });

  it('while unconfirmed, nothing in the draft can change and creating again sends the saved request', async () => {
    CrmMetaAdsConnectionAPI.createAd
      .mockRejectedValueOnce(
        refusal(422, { error: 'unconfirmed', nothing_created: false })
      )
      .mockResolvedValueOnce({ data: CREATED });
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);
    await submit(wrapper);

    expect(
      wrapper.find('[data-create-fields]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.find('[data-create-next="REVIEW"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.find('[data-create-back]').attributes('disabled')
    ).toBeDefined();
    await submit(wrapper);
    expect(CrmMetaAdsConnectionAPI.createAd).toHaveBeenCalledTimes(1);

    await wrapper.find('[data-create-recreate]').trigger('click');
    await flushPromises();
    const [first, second] = CrmMetaAdsConnectionAPI.createAd.mock.calls.map(
      ([body]) => body
    );
    expect(second).toEqual({ ...first, recreate_unconfirmed: true });
  });

  it('other refusals never offer to create again', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockRejectedValueOnce(
      refusal(422, { error: 'meta_refused', nothing_created: false })
    );
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);
    await submit(wrapper);

    expect(wrapper.find('[data-create-recreate]').exists()).toBe(false);
  });

  it('without that guarantee, asks to check Meta and never says nothing was created', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockRejectedValueOnce(
      refusal(422, { error: 'meta_refused', nothing_created: false })
    );
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);
    await submit(wrapper);

    const text = wrapper.find('[data-create-error]').text();
    expect(text).toBe(`${KEY}.ERRORS.META_REFUSED ${KEY}.ERRORS.CHECK_META`);
    expect(text).not.toContain('NOTHING_CREATED');
  });

  it('a video still processing at Meta asks to try again in a minute', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockRejectedValueOnce(
      refusal(422, { error: 'video_processing', nothing_created: true })
    );
    const wrapper = await mountCreate();
    await fillUntilReview(wrapper);
    await submit(wrapper);

    expect(wrapper.find('[data-create-error]').text()).toBe(
      `${KEY}.ERRORS.VIDEO_PROCESSING ${KEY}.ERRORS.NOTHING_CREATED`
    );
  });

  it('a website ad sends the address with https and no WhatsApp number', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockResolvedValue({ data: CREATED });
    const wrapper = await mountCreate();
    await wrapper.find('[data-create-destination-change]').trigger('click');
    await wrapper
      .find('[data-create-destination-option="WEBSITE"]')
      .trigger('click');
    await wrapper.find('input[data-create-site-url]').setValue('loja.com.br');
    await fillUntilReview(wrapper);

    await submit(wrapper);

    expect(CrmMetaAdsConnectionAPI.createAd).toHaveBeenCalledWith(
      expect.objectContaining({
        destination: 'WEBSITE',
        site_url: 'https://loja.com.br',
        site_action: 'LEARN_MORE',
        whatsapp_number: null,
        ready_message: null,
      })
    );
  });
});
