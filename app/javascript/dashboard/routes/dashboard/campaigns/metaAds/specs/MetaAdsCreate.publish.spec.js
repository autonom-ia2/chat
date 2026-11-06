import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsCreate from '../components/MetaAdsCreate.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { esquecerTentativas } from '../criacaoNaMeta';
import { lerMidia } from '../midiaDoAnuncio';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    createOptions: vi.fn(),
    boostPosts: vi.fn(),
    createAd: vi.fn(),
    uploadMedia: vi.fn(),
    uploadPostMedia: vi.fn(),
    publishPost: vi.fn(),
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
// O jsdom não decodifica imagem: a leitura do arquivo fica de fora, o envio é o que importa.
vi.mock('../midiaDoAnuncio', async importOriginal => ({
  ...(await importOriginal()),
  lerMidia: vi.fn(),
  soltarMidia: vi.fn(),
}));

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR';
const PAGE = '110000000002161';
const PHOTO = new File(['x'], 'foto.png', { type: 'image/png' });

const OPTIONS = {
  needs_login: false,
  facebook_login: { app_id: '1', api_version: 'v23.0', configuration_id: '2' },
  kinds: ['ad', 'post', 'publish'],
  publish: { facebook: true, instagram: true },
  pages: [
    {
      id: PAGE,
      name: 'Loja',
      instagram: { id: '178', username: 'loja', publish_left: 97 },
    },
  ],
  whatsapp_numbers: [],
  images: [],
  currency: 'BRL',
  today: '2030-01-15',
  min_daily: 6,
  max_daily: 500,
  destinations: ['WEBSITE'],
  placements_by_destination: { WEBSITE: ['AUTO'] },
};

const PUBLISHED = {
  instagram: {
    id: '1799',
    permalink: 'https://www.instagram.com/p/x/',
    boostable: true,
  },
  facebook: {
    id: `${PAGE}_950`,
    permalink: 'https://www.facebook.com/x',
    boostable: true,
  },
  failed: [],
  errors: {},
};

// Abre o <dialog> nativo de verdade não dá no jsdom: aqui o "Publicar" da confirmação é um botão que emite.
const DialogStub = {
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template:
    '<div data-dialog><button data-dialog-confirm @click="$emit(\'confirm\')" /></div>',
};

let mounted = null;
const mountCreate = async (options = OPTIONS) => {
  CrmMetaAdsConnectionAPI.createOptions.mockResolvedValue({
    data: { options },
  });
  mounted = mount(MetaAdsCreate, {
    global: {
      mocks: { $t: key => key },
      stubs: { Spinner: true, RouterLink: true, Dialog: DialogStub },
    },
  });
  await flushPromises();
  return mounted;
};

const choosePublish = async wrapper => {
  await wrapper.find('[data-create-kind="publish"]').trigger('click');
  await flushPromises();
};
const pickPhoto = async wrapper => {
  const input = wrapper.find('[data-create-media-input]');
  Object.defineProperty(input.element, 'files', {
    value: [PHOTO],
    configurable: true,
  });
  await input.trigger('change');
  await flushPromises();
};
const publishStep = wrapper =>
  wrapper
    .find('[data-create-publish-flow]')
    .attributes('data-create-publish-step');
const toReview = async wrapper => {
  await choosePublish(wrapper);
  await pickPhoto(wrapper);
  await wrapper.find('[data-create-caption] textarea').setValue('Bolo de pote');
  await wrapper.find('[data-create-publish-flow] form').trigger('submit');
  await flushPromises();
};
const confirm = async wrapper => {
  await wrapper.find('[data-dialog-confirm]').trigger('click');
  await flushPromises();
};

describe('Anúncios da Meta · criar post (#2653)', () => {
  beforeEach(() => {
    esquecerTentativas();
    vi.spyOn(crypto, 'randomUUID').mockReturnValue('key-post');
    lerMidia.mockResolvedValue({
      kind: 'image',
      url: 'blob:1',
      width: 1,
      height: 1,
    });
    CrmMetaAdsConnectionAPI.uploadPostMedia.mockResolvedValue({
      data: { media: { kind: 'image', signed_id: 'sig-1' } },
    });
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
    vi.clearAllMocks();
    vi.restoreAllMocks();
  });

  it('marks Instagram and Facebook, uploads the photo to our storage (not the ad account) and asks for it before going on', async () => {
    const wrapper = await mountCreate();
    await choosePublish(wrapper);

    expect(publishStep(wrapper)).toBe('EDIT');
    const checked = network =>
      wrapper
        .find(`[data-create-publish-network="${network}"]`)
        .attributes('aria-checked');
    expect(checked('instagram')).toBe('true');
    expect(checked('facebook')).toBe('true');
    expect(wrapper.find('[data-create-block-reason]').text()).toBe(
      `${KEY}.PUBLISH.NEED_MEDIA`
    );

    await pickPhoto(wrapper);

    expect(CrmMetaAdsConnectionAPI.uploadPostMedia).toHaveBeenCalledWith(PHOTO);
    expect(CrmMetaAdsConnectionAPI.uploadMedia).not.toHaveBeenCalled();
    expect(wrapper.find('[data-create-block-reason]').exists()).toBe(false);
  });

  it('publishes on both networks with one key and shows the links; tapping again never publishes twice', async () => {
    CrmMetaAdsConnectionAPI.publishPost.mockResolvedValue({ data: PUBLISHED });
    const wrapper = await mountCreate();
    await toReview(wrapper);

    expect(publishStep(wrapper)).toBe('REVIEW');
    await confirm(wrapper);

    expect(CrmMetaAdsConnectionAPI.publishPost).toHaveBeenCalledWith({
      idempotency_key: 'key-post',
      page_id: PAGE,
      networks: ['instagram', 'facebook'],
      caption: 'Bolo de pote',
      media_id: 'sig-1',
    });
    expect(publishStep(wrapper)).toBe('DONE');
    expect(
      wrapper
        .find('[data-create-published-link="instagram"]')
        .attributes('href')
    ).toBe('https://www.instagram.com/p/x/');
    expect(wrapper.find('[data-create-published-boost]').exists()).toBe(true);
  });

  it('one network failed: says which and tries again only there, with the same key', async () => {
    CrmMetaAdsConnectionAPI.publishPost
      .mockResolvedValueOnce({
        data: {
          facebook: PUBLISHED.facebook,
          failed: ['instagram'],
          errors: { instagram: 'processing' },
        },
      })
      .mockResolvedValueOnce({
        data: { instagram: PUBLISHED.instagram, failed: [], errors: {} },
      });
    const wrapper = await mountCreate();
    await toReview(wrapper);
    await confirm(wrapper);

    const partial = wrapper.find('[data-create-published-partial="instagram"]');
    expect(partial.text()).toContain(`${KEY}.PUBLISHED.PROCESSING.INSTAGRAM`);

    await wrapper
      .find('[data-create-published-retry="instagram"]')
      .trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.publishPost.mock.calls[1][0]).toMatchObject({
      idempotency_key: 'key-post',
      networks: ['instagram'],
    });
    expect(wrapper.find('[data-create-published-partial]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-create-published-link="facebook"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-create-published-link="instagram"]').exists()
    ).toBe(true);
  });

  it('nothing published: says so and stays on the review to try again', async () => {
    CrmMetaAdsConnectionAPI.publishPost.mockRejectedValue({
      response: { status: 422, data: { error: 'meta_refused' } },
    });
    const wrapper = await mountCreate();
    await toReview(wrapper);
    await confirm(wrapper);

    expect(publishStep(wrapper)).toBe('REVIEW');
    expect(wrapper.find('[data-create-publish-error]').text()).toBe(
      `${KEY}.PUBLISH_REVIEW.ERRORS.UNKNOWN`
    );
  });

  it('no answer: keeps the same key (Meta may have published) until the person says they checked', async () => {
    crypto.randomUUID.mockReturnValueOnce('key-1').mockReturnValueOnce('key-2');
    CrmMetaAdsConnectionAPI.publishPost
      .mockRejectedValueOnce(new Error('offline'))
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce({ data: PUBLISHED });
    const wrapper = await mountCreate();
    await toReview(wrapper);
    await confirm(wrapper);

    expect(wrapper.find('[data-create-publish-error]').text()).toBe(
      `${KEY}.PUBLISH_REVIEW.ERRORS.NETWORK`
    );
    await confirm(wrapper);
    const keys = () =>
      CrmMetaAdsConnectionAPI.publishPost.mock.calls.map(
        ([body]) => body.idempotency_key
      );
    expect(keys()).toEqual(['key-1', 'key-1']);

    await wrapper.find('[data-create-publish-checked]').trigger('click');
    await confirm(wrapper);

    expect(keys()).toEqual(['key-1', 'key-1', 'key-2']);
  });

  it('"Boost this post" goes to the boost flow with the Instagram post just published already chosen', async () => {
    CrmMetaAdsConnectionAPI.publishPost.mockResolvedValue({ data: PUBLISHED });
    CrmMetaAdsConnectionAPI.boostPosts.mockResolvedValue({
      data: {
        posts: [],
        instagram_posts: [
          { id: '1700', caption: 'Antigo', eligible: true },
          { id: '1799', caption: 'Bolo de pote', eligible: true },
        ],
        posts_error: null,
      },
    });
    const wrapper = await mountCreate();
    await toReview(wrapper);
    await confirm(wrapper);
    await wrapper.find('[data-create-published-boost]').trigger('click');
    await flushPromises();

    expect(
      wrapper.find('[data-create-form]').attributes('data-create-step')
    ).toBe('POST');
    expect(CrmMetaAdsConnectionAPI.boostPosts).toHaveBeenCalledWith(PAGE);
    expect(
      wrapper.find('[data-create-post="1799"]').attributes('aria-checked')
    ).toBe('true');
  });

  it('Instagram greyed out with the reason: no account on the Page, daily limit or no permission', async () => {
    const cases = [
      [
        { ...OPTIONS.pages[0], instagram: null },
        OPTIONS.publish,
        'NO_INSTAGRAM',
      ],
      [
        {
          ...OPTIONS.pages[0],
          instagram: { id: '178', username: 'loja', publish_left: 0 },
        },
        OPTIONS.publish,
        'LIMIT',
      ],
      [OPTIONS.pages[0], { facebook: true, instagram: false }, 'NO_PERMISSION'],
    ];
    // eslint-disable-next-line no-restricted-syntax
    for (const [page, publish, reason] of cases) {
      // eslint-disable-next-line no-await-in-loop
      const wrapper = await mountCreate({ ...OPTIONS, pages: [page], publish });
      // eslint-disable-next-line no-await-in-loop
      await choosePublish(wrapper);
      const card = wrapper.find('[data-create-publish-network="instagram"]');
      expect(card.attributes('aria-checked')).toBe('false');
      expect(card.attributes('aria-disabled')).toBe('true');
      expect(
        card
          .find('[data-create-publish-reason]')
          .attributes('data-create-publish-reason')
      ).toBe(reason);
      mounted.unmount();
      mounted = null;
    }
  });
});
