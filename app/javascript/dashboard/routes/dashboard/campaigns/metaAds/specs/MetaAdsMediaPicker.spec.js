import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsMediaPicker from '../components/MetaAdsMediaPicker.vue';
import MetaAdsCarouselCards from '../components/MetaAdsCarouselCards.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { lerMidia } from '../midiaDoAnuncio';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { uploadMedia: vi.fn() },
}));
// O jsdom não decodifica imagem nem vídeo: a leitura do arquivo no navegador fica de fora, o envio é o que importa.
vi.mock('../midiaDoAnuncio', async importOriginal => ({
  ...(await importOriginal()),
  lerMidia: vi.fn(),
  soltarMidia: vi.fn(),
}));

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.MEDIA';
const PHOTO = new File(['x'], 'foto.jpg', { type: 'image/jpeg' });

const choose = async (wrapper, selector, file) => {
  const input = wrapper.find(selector);
  Object.defineProperty(input.element, 'files', {
    value: [file],
    configurable: true,
  });
  await input.trigger('change');
};

const deferred = () => {
  let resolve;
  const promise = new Promise(done => {
    resolve = done;
  });
  return { promise, resolve };
};

const mountPicker = (props = {}) =>
  mount(MetaAdsMediaPicker, {
    props: { modelValue: null, ...props },
    global: { mocks: { $t: key => key }, stubs: { Spinner: true } },
  });

describe('Anúncios da Meta · foto ou vídeo do anúncio (#2198)', () => {
  it('uploads the chosen photo right away, shows it is sending, then keeps the hash', async () => {
    lerMidia.mockResolvedValue({
      kind: 'image',
      url: 'blob:1',
      width: 1,
      height: 1,
    });
    const upload = deferred();
    CrmMetaAdsConnectionAPI.uploadMedia.mockReturnValue(upload.promise);
    const wrapper = mountPicker();

    await choose(wrapper, '[data-create-media-input]', PHOTO);
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.uploadMedia).toHaveBeenCalledWith(PHOTO);
    expect(wrapper.find('[data-create-media-uploading]').text()).toBe(
      `${KEY}.UPLOADING`
    );
    expect(wrapper.emitted('uploading')).toEqual([[true]]);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();

    upload.resolve({ data: { media: { kind: 'image', hash: 'abc' } } });
    await flushPromises();

    expect(wrapper.emitted('update:modelValue')).toEqual([
      [{ kind: 'image', url: 'blob:1', width: 1, height: 1, hash: 'abc' }],
    ]);
    expect(wrapper.emitted('uploading')).toEqual([[true], [false]]);
  });

  it('a failed upload says so and keeps no media', async () => {
    lerMidia.mockResolvedValue({ kind: 'image', url: 'blob:1' });
    CrmMetaAdsConnectionAPI.uploadMedia.mockRejectedValue(new Error('422'));
    const wrapper = mountPicker();

    await choose(wrapper, '[data-create-media-input]', PHOTO);
    await flushPromises();

    expect(wrapper.find('[data-create-media-error]').text()).toBe(
      `${KEY}.ERRORS.UPLOAD`
    );
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('a file the screen refuses never goes up', async () => {
    lerMidia.mockRejectedValue(
      Object.assign(new Error('TYPE'), { code: 'TYPE' })
    );
    const wrapper = mountPicker();

    await choose(wrapper, '[data-create-media-input]', PHOTO);
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.uploadMedia).not.toHaveBeenCalled();
    expect(wrapper.find('[data-create-media-error]').text()).toBe(
      `${KEY}.ERRORS.TYPE`
    );
  });

  it('an image from an old ad already has its hash and uploads nothing', async () => {
    const wrapper = mountPicker({
      library: [{ hash: 'h1', url: 'https://img/1.jpg', width: 1, height: 1 }],
    });

    await wrapper.find('[data-create-media-library-toggle]').trigger('click');
    await wrapper.find('[data-create-image="h1"]').trigger('click');

    expect(CrmMetaAdsConnectionAPI.uploadMedia).not.toHaveBeenCalled();
    expect(wrapper.emitted('update:modelValue')[0][0]).toMatchObject({
      kind: 'image',
      hash: 'h1',
      source: 'library',
    });
  });

  it('each extra carousel card goes up before it joins the carousel', async () => {
    lerMidia.mockResolvedValue({ kind: 'image', url: 'blob:2' });
    CrmMetaAdsConnectionAPI.uploadMedia.mockResolvedValue({
      data: { media: { kind: 'image', hash: 'h2' } },
    });
    const wrapper = mount(MetaAdsCarouselCards, {
      props: { first: { kind: 'image', url: 'blob:1', hash: 'h1' } },
      global: { mocks: { $t: key => key }, stubs: { Spinner: true } },
    });

    await choose(wrapper, '[data-create-carousel-input]', PHOTO);
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.uploadMedia).toHaveBeenCalledWith(PHOTO);
    expect(wrapper.emitted('update:modelValue')).toEqual([
      [[{ kind: 'image', url: 'blob:2', hash: 'h2' }]],
    ]);
    expect(wrapper.emitted('uploading')).toEqual([[true], [false]]);
  });
});
