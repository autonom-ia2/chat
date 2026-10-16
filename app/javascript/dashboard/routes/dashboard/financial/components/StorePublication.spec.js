import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import StoreAPI from 'dashboard/api/autonomia/store';
import en from 'dashboard/i18n/locale/en/financial.json';
import StoreDraftDialog from './StoreDraftDialog.vue';
import StorePublicationRow from './StorePublicationRow.vue';

vi.mock('dashboard/api/autonomia/store', () => ({
  default: { createService: vi.fn(), publication: vi.fn(), publish: vi.fn() },
}));
const target = { agentId: 10 };
const service = { id: 'example-id', name: 'Principal agent' };
const mounted = [];
const render = (component, props) => {
  const wrapper = mount(component, {
    props,
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: {
        Dialog: {
          props: ['disableConfirmButton'],
          template:
            '<div><slot /><button :disabled="disableConfirmButton" @click="$emit(\'confirm\')">Confirm</button></div>',
          methods: { open: vi.fn(), close: vi.fn() },
        },
      },
    },
  });
  mounted.push(wrapper);
  return wrapper;
};
afterEach(() => mounted.splice(0).forEach(wrapper => wrapper.unmount()));

describe('Store publication controls', () => {
  it('retries a failed draft with the same intent and keeps upstream errors private', async () => {
    StoreAPI.createService.mockRejectedValueOnce({
      response: { data: { error: 'secret-example' } },
    });
    StoreAPI.createService.mockResolvedValueOnce({ data: { service } });
    const wrapper = render(StoreDraftDialog, { target });
    wrapper.vm.open('Principal agent');
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.text()).not.toContain('secret-example');
    const first = StoreAPI.createService.mock.calls[0][1];
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(StoreAPI.createService.mock.calls[1][1]).toEqual(first);
    expect(first.idempotencyKey).toMatch(/^[a-f0-9-]{36}$/);
    expect(wrapper.emitted('created')).toEqual([[service]]);
  });

  it('rejects a one-character draft before sending it', async () => {
    const wrapper = render(StoreDraftDialog, { target });
    wrapper.vm.open('A');
    await flushPromises();
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    await wrapper.get('button').trigger('click');
    expect(StoreAPI.createService).not.toHaveBeenCalled();
  });

  it('shows a commercial eligibility conflict without marking the service published', async () => {
    StoreAPI.publication.mockRejectedValue({ response: { status: 404 } });
    StoreAPI.publish.mockRejectedValue({
      response: { status: 409, data: { error: 'secret-example' } },
    });
    const wrapper = render(StorePublicationRow, { target, service });
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(StoreAPI.publish).toHaveBeenCalledWith(target, service.id, {
      status: 'active',
      displayOrder: 0,
    });
    expect(wrapper.text()).toContain(en.FINANCIAL.STORE.PUBLICATION_INELIGIBLE);
    expect(wrapper.text()).toContain('Not published');
    expect(wrapper.text()).not.toContain('secret-example');
  });

  it('keeps the service published until Financial confirms unpublication', async () => {
    StoreAPI.publication.mockResolvedValue({
      data: { publication: { status: 'active', displayOrder: 2 } },
    });
    let resolve;
    StoreAPI.publish.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = render(StorePublicationRow, { target, service });
    await flushPromises();
    await wrapper.get('button').trigger('click');
    expect(StoreAPI.publish).toHaveBeenCalledWith(target, service.id, {
      status: 'inactive',
      displayOrder: 2,
    });
    expect(wrapper.text()).toContain('Published');
    resolve({ data: { publication: { status: 'inactive', displayOrder: 2 } } });
    await flushPromises();
    expect(wrapper.text()).toContain('Not published');
  });

  it('does not publish with an out-of-contract display order', async () => {
    StoreAPI.publication.mockRejectedValue({ response: { status: 404 } });
    const wrapper = render(StorePublicationRow, { target, service });
    await flushPromises();
    await wrapper.get('input').setValue('1000001');
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    await wrapper.get('button').trigger('click');
    expect(StoreAPI.publish).not.toHaveBeenCalled();
  });
});
