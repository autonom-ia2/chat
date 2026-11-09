import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsAdCare from '../components/MetaAdsAdCare.vue';
import { duplicarAnuncio, trocarCriativo } from '../criacaoNaMeta';
import { useAlert } from 'dashboard/composables';

vi.mock('../criacaoNaMeta', () => ({
  duplicarAnuncio: vi.fn(),
  trocarCriativo: vi.fn(),
  enviarMidia: vi.fn(),
}));
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

  it('without the swap confirmed: "change the photo (makes a copy)" first, duplicate as a link', () => {
    const wrapper = mountCare();

    expect(wrapper.find('[data-ad-care-change]').text()).toContain(
      `${KEY}.SWAP_AS_COPY`
    );
    expect(wrapper.find('button[data-ad-care-duplicate]').exists()).toBe(true);
    expect(wrapper.text()).toContain(`${KEY}.HINT_COPY`);
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

    expect(duplicarAnuncio).toHaveBeenCalledWith('1');
    expect(wrapper.find('[data-ad-care-copy]').text()).toContain(
      `${KEY}.DUPLICATE_DONE`
    );
    expect(wrapper.findComponent(StatusStub).props()).toMatchObject({
      adId: '9',
      activateNote: '',
      gestao: { status: 'PAUSED' },
    });
  });

  it('changing the photo as a copy sends the new photo and text, and the copy reminds to pause this one', async () => {
    duplicarAnuncio.mockResolvedValue(COPY);
    const wrapper = mountCare();

    await changePhoto(wrapper);

    expect(duplicarAnuncio).toHaveBeenCalledWith('1', {
      media: NEW_PHOTO,
      text: 'Texto antigo',
    });
    expect(wrapper.find('[data-ad-care-copy-image]').attributes('src')).toBe(
      'blob:x'
    );
    expect(wrapper.findComponent(StatusStub).props('activateNote')).toBe(
      `${KEY}.SWAP_AS_COPY_ACTIVATE`
    );
  });

  it('with the swap confirmed, changes the ad itself and tells the page it is in review', async () => {
    trocarCriativo.mockResolvedValue({ effective_status: 'PENDING_REVIEW' });
    const wrapper = mountCare({ canSwap: true });

    await changePhoto(wrapper);

    expect(trocarCriativo).toHaveBeenCalledWith('1', {
      media: NEW_PHOTO,
      text: 'Texto antigo',
    });
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
