import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsAdCare from '../components/MetaAdsAdCare.vue';
import { duplicarAnuncio, trocarCriativo } from '../criacaoNaMeta';
import { mudarStatus } from '../gestaoDoAnuncio';
import { useAlert } from 'dashboard/composables';

vi.mock('../criacaoNaMeta', () => ({
  duplicarAnuncio: vi.fn(),
  trocarCriativo: vi.fn(),
  enviarMidia: vi.fn(),
}));
vi.mock('../gestaoDoAnuncio', () => ({ mudarStatus: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.CARE';

// O Dialog real abre um <dialog> nativo; aqui ele mostra o conteúdo e confirma pelo `confirm`.
const DialogStub = {
  props: ['title', 'description'],
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template: '<div data-dialog><slot /><slot name="footer" /></div>',
};
const PickerStub = {
  props: ['modelValue', 'only', 'replacing'],
  emits: ['update:modelValue', 'uploading'],
  template: '<div data-picker />',
};
const StatusStub = {
  props: ['adId', 'gestao', 'budget', 'activateNote'],
  emits: ['changed'],
  template: '<div data-copy-status />',
};

const BUDGET = { kind: 'daily', amount: 30, currency: 'BRL' };
const NEW_PHOTO = {
  kind: 'image',
  hash: 'h2',
  url: 'blob:x',
  source: 'upload',
};
const COPY = {
  ad_id: '9',
  name: 'Bolo - Cópia',
  status: 'PAUSED',
  budget: BUDGET,
};

const mountCare = (props = {}) =>
  mount(MetaAdsAdCare, {
    props: {
      adId: '1',
      adName: 'Bolo',
      image: 'https://x/foto.jpg',
      text: 'Texto antigo',
      budget: BUDGET,
      creativeKind: 'image',
      originalStatus: 'ACTIVE',
      managerUrl: 'https://adsmanager.facebook.com/x',
      ...props,
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Dialog: DialogStub,
        MetaAdsMediaPicker: PickerStub,
        MetaAdsAdStatus: StatusStub,
      },
    },
  });

const dialogs = wrapper => wrapper.findAllComponents(DialogStub);
const refusal = (data, status = 422) =>
  Object.assign(new Error('x'), { response: { status, data } });

// Escolhe a foto nova, continua para a confirmação e confirma.
const changePhoto = async wrapper => {
  await wrapper.find('[data-ad-care-change]').trigger('click');
  wrapper.findComponent(PickerStub).vm.$emit('update:modelValue', NEW_PHOTO);
  await flushPromises();
  dialogs(wrapper)[1].vm.$emit('confirm');
  await flushPromises();
  dialogs(wrapper)[1].vm.$emit('confirm');
  await flushPromises();
};

describe('Anúncios da Meta · cuidar do anúncio (#2778)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('photo or video ad: duplicate and change the photo on the ad itself (#2804)', () => {
    const wrapper = mountCare();

    expect(wrapper.find('[data-ad-care-change]').text()).toContain(
      `${KEY}.CHANGE`
    );
    expect(wrapper.find('[data-ad-care-duplicate]').exists()).toBe(true);
    expect(wrapper.text()).toContain(`${KEY}.HINT`);
    expect(wrapper.findComponent(PickerStub).props('only')).toBe('image');
  });

  it('carousel or boosted post (no creative kind): only duplicate', () => {
    const wrapper = mountCare({ creativeKind: '' });

    expect(wrapper.find('[data-ad-care-change]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-care-duplicate]').text()).toContain(
      `${KEY}.DUPLICATE`
    );
    expect(wrapper.text()).toContain(`${KEY}.HINT_DUPLICATE`);
  });

  it('duplicating shows the paused copy with its own Activate', async () => {
    duplicarAnuncio.mockResolvedValue(COPY);
    const wrapper = mountCare();

    dialogs(wrapper)[0].vm.$emit('confirm');
    await flushPromises();

    expect(duplicarAnuncio).toHaveBeenCalledWith('1', null, { recriar: false });
    expect(wrapper.find('[data-ad-care-copy]').text()).toContain(
      `${KEY}.DUPLICATE_DONE`
    );
    expect(wrapper.findComponent(StatusStub).props()).toMatchObject({
      adId: '9',
      activateNote: '',
      gestao: { status: 'PAUSED' },
    });
  });

  it('changes the ad itself and tells the page it is in review', async () => {
    trocarCriativo.mockResolvedValue({ effective_status: 'PENDING_REVIEW' });
    const wrapper = mountCare();

    await changePhoto(wrapper);

    expect(trocarCriativo).toHaveBeenCalledWith('1', {
      media: NEW_PHOTO,
      text: 'Texto antigo',
    });
    expect(duplicarAnuncio).not.toHaveBeenCalled();
    expect(wrapper.emitted('reviewing')).toEqual([
      [
        {
          effective_status: 'PENDING_REVIEW',
          image: 'blob:x',
          text: 'Texto antigo',
        },
      ],
    ]);
    expect(useAlert).toHaveBeenCalledWith(`${KEY}.CHANGE_DONE`);
  });

  it('Meta refuses the change on the ad: the same dialog offers the paused copy with the new photo', async () => {
    trocarCriativo.mockRejectedValue(
      refusal({ error: 'swap_refused', nothing_created: true })
    );
    duplicarAnuncio.mockResolvedValue(COPY);
    const wrapper = mountCare();

    await changePhoto(wrapper);

    expect(useAlert).not.toHaveBeenCalled();
    expect(dialogs(wrapper)[1].props('title')).toBe(
      `${KEY}.SWAP_AS_COPY_CONFIRM_TITLE`
    );
    expect(wrapper.find('[data-ad-care-change-review]').text()).toContain(
      `${KEY}.SWAP_REFUSED`
    );
    expect(wrapper.find('[data-ad-care-change-save]').text()).toContain(
      `${KEY}.DUPLICATE_CONFIRM`
    );

    dialogs(wrapper)[1].vm.$emit('confirm');
    await flushPromises();

    expect(duplicarAnuncio).toHaveBeenCalledWith(
      '1',
      { media: NEW_PHOTO, text: 'Texto antigo' },
      { recriar: false }
    );
    expect(wrapper.find('[data-ad-care-copy-image]').attributes('src')).toBe(
      'blob:x'
    );
    expect(wrapper.findComponent(StatusStub).props('activateNote')).toBe(
      `${KEY}.SWAP_AS_COPY_ACTIVATE`
    );
  });

  it('other refusals of the change do not offer the copy', async () => {
    trocarCriativo.mockRejectedValue(
      refusal({ error: 'meta_refused', nothing_created: true })
    );
    const wrapper = mountCare();

    await changePhoto(wrapper);

    expect(useAlert).toHaveBeenCalledWith(`${KEY}.CHANGE_ERROR`);
    expect(dialogs(wrapper)[1].props('title')).toBe(
      `${KEY}.CHANGE_CONFIRM_TITLE`
    );
  });

  it('an unconfirmed copy: says to check the Ads Manager and recreates it from the screen', async () => {
    duplicarAnuncio
      .mockRejectedValueOnce(
        refusal({ error: 'unconfirmed', nothing_created: false })
      )
      .mockResolvedValueOnce(COPY);
    const wrapper = mountCare();

    dialogs(wrapper)[0].vm.$emit('confirm');
    await flushPromises();

    const block = wrapper.find('[data-ad-care-unconfirmed]');
    expect(useAlert).not.toHaveBeenCalled();
    // Uma ação só: enquanto a cópia não for resolvida, não dá para criar outra.
    expect(wrapper.find('[data-ad-care-duplicate]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-care-change]').exists()).toBe(false);
    expect(block.text()).toContain(`${KEY}.COPY_UNCONFIRMED`);
    expect(block.find('a').attributes('href')).toBe(
      'https://adsmanager.facebook.com/x'
    );

    await block.find('[data-ad-care-recreate]').trigger('click');
    await flushPromises();

    expect(duplicarAnuncio).toHaveBeenLastCalledWith('1', null, {
      recriar: true,
    });
    expect(wrapper.find('[data-ad-care-unconfirmed]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-care-copy]').exists()).toBe(true);
  });

  it('pause the original: only after the copy with the new photo goes live', async () => {
    trocarCriativo.mockRejectedValue(refusal({ error: 'swap_refused' }));
    duplicarAnuncio.mockResolvedValue(COPY);
    mudarStatus.mockResolvedValue({});
    const wrapper = mountCare();
    await changePhoto(wrapper);
    dialogs(wrapper)[1].vm.$emit('confirm');
    await flushPromises();

    expect(wrapper.find('[data-ad-care-pause-original]').exists()).toBe(false);
    wrapper.findComponent(StatusStub).vm.$emit('changed', 'ACTIVE');
    await flushPromises();

    const button = wrapper.find('[data-ad-care-pause-original]');
    expect(button.text()).toContain(`${KEY}.PAUSE_ORIGINAL`);
    dialogs(wrapper)[2].vm.$emit('confirm');
    await flushPromises();

    expect(mudarStatus).toHaveBeenCalledWith('1', 'PAUSED');
    expect(wrapper.emitted('originalPaused')).toHaveLength(1);
    expect(useAlert).toHaveBeenCalledWith(`${KEY}.PAUSE_ORIGINAL_DONE`);
  });

  it('pause the original: not for a plain duplicate, nor when the original is already paused', async () => {
    duplicarAnuncio.mockResolvedValue(COPY);
    const plain = mountCare();
    dialogs(plain)[0].vm.$emit('confirm');
    await flushPromises();
    plain.findComponent(StatusStub).vm.$emit('changed', 'ACTIVE');
    await flushPromises();
    expect(plain.find('[data-ad-care-pause-original]').exists()).toBe(false);

    trocarCriativo.mockRejectedValue(refusal({ error: 'swap_refused' }));
    const paused = mountCare({ originalStatus: 'PAUSED' });
    await changePhoto(paused);
    dialogs(paused)[1].vm.$emit('confirm');
    await flushPromises();
    paused.findComponent(StatusStub).vm.$emit('changed', 'ACTIVE');
    await flushPromises();
    expect(paused.find('[data-ad-care-pause-original]').exists()).toBe(false);
  });

  it('errors: an ended ad says so; no answer from Meta asks to check the Ads Manager', async () => {
    duplicarAnuncio
      .mockRejectedValueOnce(refusal({ error: 'invalid_dates' }))
      .mockRejectedValueOnce(refusal({ nothing_created: false }))
      .mockRejectedValueOnce(
        refusal({ error: 'meta_refused', nothing_created: true })
      )
      .mockRejectedValueOnce(new Error('Network Error'))
      .mockRejectedValueOnce(refusal({ error: 'in_progress' }, 409));
    const wrapper = mountCare();

    for (let attempt = 0; attempt < 5; attempt += 1) {
      dialogs(wrapper)[0].vm.$emit('confirm');
      // eslint-disable-next-line no-await-in-loop
      await flushPromises();
    }

    expect(useAlert.mock.calls).toEqual([
      [`${KEY}.ENDED`],
      [`${KEY}.UNSURE`],
      [`${KEY}.DUPLICATE_ERROR`],
      [`${KEY}.UNSURE`],
      [`${KEY}.UNSURE`],
    ]);
    expect(wrapper.find('[data-ad-care-copy]').exists()).toBe(false);
  });
});
