import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsCreate from '../components/MetaAdsCreate.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { esquecerTentativas } from '../criacaoNaMeta';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    createOptions: vi.fn(),
    boostPosts: vi.fn(),
    createAd: vi.fn(),
    uploadMedia: vi.fn(),
    setAdStatus: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: { value: { timezone: 'America/Sao_Paulo' } },
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '18' }, query: {} }),
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
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
const PAGE = '110000000002161';
const NUMBER = '+5511900002161';

const OPTIONS = {
  needs_login: false,
  facebook_login: { app_id: '1', api_version: 'v23.0', configuration_id: '2' },
  kinds: ['ad', 'post'],
  pages: [
    { id: PAGE, name: 'Loja', instagram: { id: '178', username: 'loja' } },
  ],
  instagram: { id: '178', username: 'loja', publish_left: null },
  whatsapp_numbers: [{ id: NUMBER, name: 'Loja', phone: NUMBER }],
  images: [],
  currency: 'BRL',
  today: '2030-01-15',
  min_daily: 6,
  max_daily: 500,
  destinations: ['WHATSAPP', 'WEBSITE'],
  placements_by_destination: {
    WHATSAPP: ['AUTO'],
    WEBSITE: ['AUTO', 'INSTAGRAM', 'FACEBOOK'],
  },
};

const pagePost = (id, extra = {}) => ({
  id: `${PAGE}_${id}`,
  message: `Post ${id}`,
  created_time: '2030-01-10T12:00:00+0000',
  image_url: `https://img/${id}.jpg`,
  reactions: 9,
  comments: 2,
  eligible: true,
  reason: null,
  ...extra,
});

const igPost = (id, extra = {}) => ({
  id,
  caption: `Legenda ${id}`,
  timestamp: '2030-01-11T12:00:00+0000',
  image_url: `https://img/${id}.jpg`,
  likes: 30,
  comments: 4,
  eligible: true,
  reason: null,
  ...extra,
});

const BOOST = {
  posts: [
    pagePost('901'),
    pagePost('902', { eligible: false, reason: 'profile_or_cover' }),
    pagePost('903'),
  ],
  instagram_posts: [igPost('1790', { eligible: false }), igPost('1791')],
  posts_error: null,
};

const CREATED = {
  ad_id: '120000000000990001',
  name: 'Impulsionar',
  status: 'PAUSED',
  budget: {
    kind: 'daily',
    amount: 20,
    currency: 'BRL',
    start_time: '2030-01-15',
    end_time: null,
    active_ads_count: 0,
  },
};

const DialogStub = {
  methods: { open() {}, close() {} },
  template: '<div data-dialog />',
};

let mounted = null;
const mountCreate = async ({ options = OPTIONS, boost = BOOST } = {}) => {
  CrmMetaAdsConnectionAPI.createOptions.mockResolvedValue({
    data: { options },
  });
  CrmMetaAdsConnectionAPI.boostPosts.mockResolvedValue({ data: boost });
  mounted = mount(MetaAdsCreate, {
    global: {
      mocks: { $t: key => key },
      stubs: { Spinner: true, RouterLink: true, Dialog: DialogStub },
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
const choosePost = async wrapper => {
  await wrapper.find('[data-create-kind="post"]').trigger('click');
  await flushPromises();
};
const untilReview = async wrapper => {
  await submit(wrapper);
  await wrapper.find('[data-create-special="false"]').trigger('click');
  await submit(wrapper);
  await submit(wrapper);
  expect(step(wrapper)).toBe('REVIEW');
};

describe('Anúncios da Meta · impulsionar post (#2339)', () => {
  beforeEach(() => {
    esquecerTentativas();
    vi.spyOn(crypto, 'randomUUID').mockReturnValue('key-1');
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
    vi.restoreAllMocks();
  });

  it('offers "Boost a post" and reads the posts of the chosen Page only when the post step opens', async () => {
    const wrapper = await mountCreate();

    expect(wrapper.find('[data-create-kind="post"]').exists()).toBe(true);
    expect(CrmMetaAdsConnectionAPI.boostPosts).not.toHaveBeenCalled();

    await choosePost(wrapper);

    expect(step(wrapper)).toBe('POST');
    expect(CrmMetaAdsConnectionAPI.boostPosts).toHaveBeenCalledWith(PAGE);
  });

  it('opens on the Instagram tab with the first post Meta lets boost already chosen', async () => {
    const wrapper = await mountCreate();
    await choosePost(wrapper);

    expect(
      wrapper
        .find('[data-create-post-source="instagram"]')
        .attributes('aria-selected')
    ).toBe('true');
    expect(
      wrapper.find('[data-create-post="1791"]').attributes('aria-checked')
    ).toBe('true');
    expect(
      wrapper.find('[data-create-next="POST"]').attributes('disabled')
    ).toBeUndefined();
  });

  it('shows the profile or cover photo greyed out with the reason, and it cannot be chosen', async () => {
    const wrapper = await mountCreate();
    await choosePost(wrapper);
    await wrapper.find('[data-create-post-source="facebook"]').trigger('click');

    const cover = wrapper.find(`[data-create-post="${PAGE}_902"]`);
    expect(cover.attributes('aria-disabled')).toBe('true');
    expect(cover.find('[data-create-post-not-eligible]').text()).toBe(
      `${KEY}.POST.REASONS.PROFILE_OR_COVER`
    );

    await cover.trigger('click');
    expect(cover.attributes('aria-checked')).toBe('false');
    expect(wrapper.find('[data-create-block-reason]').text()).toBe(
      `${KEY}.POST.NEED_POST`
    );
  });

  it('when the posts cannot be read, says so (never "no posts") and tries again', async () => {
    const wrapper = await mountCreate({
      boost: {
        posts: [],
        instagram_posts: [],
        posts_error: 'posts_unreadable',
      },
    });
    await choosePost(wrapper);

    expect(wrapper.find('[data-create-post-failed]').exists()).toBe(true);
    expect(wrapper.find('[data-create-blocker]').exists()).toBe(false);

    CrmMetaAdsConnectionAPI.boostPosts.mockResolvedValue({ data: BOOST });
    await wrapper.find('[data-create-post-retry]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.boostPosts).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-create-post="1791"]').exists()).toBe(true);
  });

  it('without any post on either side, offers the new ad instead', async () => {
    const wrapper = await mountCreate({
      boost: { posts: [], instagram_posts: [], posts_error: null },
    });
    await choosePost(wrapper);

    expect(
      wrapper.find('[data-create-blocker]').attributes('data-create-blocker')
    ).toBe('NO_POST');

    await wrapper
      .find('[data-create-blocker-action="NO_POST"]')
      .trigger('click');
    await flushPromises();

    expect(step(wrapper)).toBe('CONTENT');
  });

  it('without any post and no way to make a new ad, does not offer the new ad', async () => {
    const wrapper = await mountCreate({
      options: { ...OPTIONS, destinations: [] },
      boost: { posts: [], instagram_posts: [], posts_error: null },
    });
    await choosePost(wrapper);

    expect(
      wrapper.find('[data-create-blocker]').attributes('data-create-blocker')
    ).toBe('NO_POST');
    expect(
      wrapper.find('[data-create-blocker-action="NO_POST"]').exists()
    ).toBe(false);
  });

  it('shows the day the post went out in the account time zone, not in UTC', async () => {
    const wrapper = await mountCreate({
      boost: {
        posts: [pagePost('904', { created_time: '2030-01-11T01:30:00Z' })],
        instagram_posts: [],
        posts_error: null,
      },
    });
    await choosePost(wrapper);

    const card = wrapper.find(`[data-create-post="${PAGE}_904"]`).text();
    expect(card).toContain('10');
    expect(card).not.toContain('11');
  });

  it('with every post greyed out, the first one still takes the Tab to read why', async () => {
    const wrapper = await mountCreate({
      boost: {
        posts: [
          pagePost('905', { eligible: false }),
          pagePost('906', { eligible: false }),
        ],
        instagram_posts: [],
        posts_error: null,
      },
    });
    await choosePost(wrapper);

    expect(
      wrapper.find(`[data-create-post="${PAGE}_905"]`).attributes('tabindex')
    ).toBe('0');
    expect(
      wrapper.find(`[data-create-post="${PAGE}_906"]`).attributes('tabindex')
    ).toBe('-1');
  });

  it('Instagram post: creates paused with the post and the WhatsApp number', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockResolvedValue({ data: CREATED });
    const wrapper = await mountCreate();
    await choosePost(wrapper);
    await untilReview(wrapper);

    expect(wrapper.find('[data-create-next="REVIEW"]').text()).toBe(
      `${KEY}.CREATE_BOOST`
    );
    expect(wrapper.find('[data-create-review-what]').text()).toBe(
      `${KEY}.REVIEW.WHAT_POST.INSTAGRAM`
    );

    await submit(wrapper);

    const pedido = CrmMetaAdsConnectionAPI.createAd.mock.calls[0][0];
    expect(pedido).toMatchObject({
      kind: 'post',
      page_id: PAGE,
      post_source: 'instagram',
      post_id: '1791',
      whatsapp_number: NUMBER,
      region: 'BR',
      idempotency_key: 'key-1',
    });
    expect(pedido).not.toHaveProperty('media');
    expect(wrapper.find('[data-create-form]').exists()).toBe(false);
  });

  it('Page post: no WhatsApp number, Facebook only, preview without the Stories tab', async () => {
    CrmMetaAdsConnectionAPI.createAd.mockResolvedValue({ data: CREATED });
    const wrapper = await mountCreate();
    await choosePost(wrapper);
    await wrapper.find('[data-create-post-source="facebook"]').trigger('click');
    await wrapper.find(`[data-create-post="${PAGE}_901"]`).trigger('click');
    await untilReview(wrapper);

    expect(wrapper.find('[data-create-review-where]').text()).toBe(
      `${KEY}.PLACEMENT.FACEBOOK_POST`
    );
    expect(wrapper.find('[data-create-preview-place]').exists()).toBe(false);

    await submit(wrapper);

    expect(CrmMetaAdsConnectionAPI.createAd.mock.calls[0][0]).toMatchObject({
      kind: 'post',
      post_source: 'facebook',
      post_id: `${PAGE}_901`,
      whatsapp_number: null,
    });
  });

  it('with two WhatsApp numbers, asks the Page and the number before the post', async () => {
    const wrapper = await mountCreate({
      options: {
        ...OPTIONS,
        whatsapp_numbers: [
          { id: NUMBER, name: 'Loja', phone: NUMBER },
          { id: '+5511900002162', name: 'Loja 2', phone: '+5511900002162' },
        ],
      },
    });
    await choosePost(wrapper);

    expect(step(wrapper)).toBe('WHERE');
    expect(CrmMetaAdsConnectionAPI.boostPosts).not.toHaveBeenCalled();
  });

  it('arrow keys move the choice to the next post Meta lets boost, skipping the greyed one', async () => {
    const wrapper = await mountCreate();
    await choosePost(wrapper);
    await wrapper.find('[data-create-post-source="facebook"]').trigger('click');

    const first = wrapper.find(`[data-create-post="${PAGE}_901"]`);
    expect(first.attributes('tabindex')).toBe('0');
    expect(
      wrapper.find(`[data-create-post="${PAGE}_902"]`).attributes('tabindex')
    ).toBe('-1');

    await first.trigger('keydown', { key: 'ArrowRight' });

    expect(
      wrapper
        .find(`[data-create-post="${PAGE}_903"]`)
        .attributes('aria-checked')
    ).toBe('true');
  });

  describe('with two Pages', () => {
    const OTHER = '220000000002161';
    const TWO_PAGES = {
      ...OPTIONS,
      pages: [...OPTIONS.pages, { id: OTHER, name: 'Outra', instagram: null }],
    };
    const pickPage = async (wrapper, id) => {
      const select = wrapper
        .findAllComponents(ChoiceSelect)
        .find(item => item.attributes('data-create-page') !== undefined);
      select.vm.$emit('update:modelValue', id);
      await flushPromises();
    };

    it('the Page without Instagram has no Instagram tab', async () => {
      const wrapper = await mountCreate({
        options: TWO_PAGES,
        boost: {
          posts: [pagePost('901')],
          instagram_posts: [],
          posts_error: null,
        },
      });
      await choosePost(wrapper);
      expect(step(wrapper)).toBe('WHERE');
      await pickPage(wrapper, OTHER);
      await submit(wrapper);

      expect(step(wrapper)).toBe('POST');
      expect(CrmMetaAdsConnectionAPI.boostPosts).toHaveBeenCalledWith(OTHER);
      expect(wrapper.find('[data-create-post-source]').exists()).toBe(false);
    });

    it('a late answer for the Page chosen before is dropped', async () => {
      let answerFirst;
      const wrapper = await mountCreate({ options: TWO_PAGES, boost: BOOST });
      // A Página escolhida antes responde por último.
      CrmMetaAdsConnectionAPI.boostPosts.mockImplementation(pageId =>
        pageId === PAGE
          ? new Promise(resolve => {
              answerFirst = resolve;
            })
          : Promise.resolve({
              data: {
                posts: [pagePost('777')],
                instagram_posts: [],
                posts_error: null,
              },
            })
      );
      await choosePost(wrapper);
      await pickPage(wrapper, PAGE);
      await submit(wrapper);
      expect(step(wrapper)).toBe('POST');

      await wrapper.find('[data-create-back]').trigger('click');
      await pickPage(wrapper, OTHER);
      await submit(wrapper);
      answerFirst({ data: BOOST });
      await flushPromises();

      expect(wrapper.find(`[data-create-post="${PAGE}_777"]`).exists()).toBe(
        true
      );
      expect(wrapper.find('[data-create-post="1791"]').exists()).toBe(false);
    });
  });
});
