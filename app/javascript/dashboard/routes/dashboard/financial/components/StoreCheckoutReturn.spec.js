import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/financial.json';
import StoreAPI from 'dashboard/api/autonomia/store';
import StoreCheckoutReturn from './StoreCheckoutReturn.vue';

vi.mock('dashboard/api/autonomia/store', () => ({
  default: { checkoutStatus: vi.fn(), reconcileCheckout: vi.fn() },
}));
const wrappers = [];
const id = '11111111-1111-4111-8111-111111111111';
const key = 'fictitious-buyer-scope';
const intent = {
  operationId: id,
  clientIntent: 'fictitious-client-intent',
  priceId: 'fictitious-price',
};
const render = async () => {
  const wrapper = mount(StoreCheckoutReturn, {
    props: { operationId: id, buyerScope: key },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });
  wrappers.push(wrapper);
  await flushPromises();
  return wrapper;
};
beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.setItem(key, JSON.stringify(intent));
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  sessionStorage.clear();
});

it('keeps an expired intent until Financial confirms that a new purchase is eligible', async () => {
  StoreAPI.checkoutStatus.mockResolvedValue({
    data: { operation: { id, state: 'expired', canStartNewCheckout: false } },
  });
  const wrapper = await render();
  expect(sessionStorage.getItem(key)).not.toBeNull();
  expect(StoreAPI.reconcileCheckout).not.toHaveBeenCalled();
  expect(wrapper.text()).toContain(en.FINANCIAL.STORE.RECONCILE_PAYMENT);
});

it('requests verification only after a click, not after a return or cancel navigation', async () => {
  StoreAPI.checkoutStatus.mockResolvedValue({
    data: { operation: { id, state: 'expired', canStartNewCheckout: false } },
  });
  StoreAPI.reconcileCheckout.mockResolvedValue({
    data: { operation: { id, state: 'expired' } },
  });
  const wrapper = await render();
  await wrapper
    .findAll('button')
    .find(button => button.text() === en.FINANCIAL.STORE.RECONCILE_PAYMENT)
    .trigger('click');
  await flushPromises();
  expect(StoreAPI.reconcileCheckout).toHaveBeenCalledWith(id);
  expect(sessionStorage.getItem(key)).not.toBeNull();
  expect(wrapper.emitted('confirmed')).toBeUndefined();
});

it('clears only a proven closed checkout without starting another purchase', async () => {
  StoreAPI.checkoutStatus.mockResolvedValue({
    data: { operation: { id, state: 'expired', canStartNewCheckout: true } },
  });
  const wrapper = await render();
  expect(sessionStorage.getItem(key)).toBeNull();
  expect(wrapper.text()).not.toContain(en.FINANCIAL.STORE.RECONCILE_PAYMENT);
  expect(StoreAPI.reconcileCheckout).not.toHaveBeenCalled();
});

it('confirms access navigation only after canonical completed state, not the reconciliation receipt', async () => {
  StoreAPI.checkoutStatus.mockResolvedValue({
    data: { operation: { id, state: 'completed', canStartNewCheckout: false } },
  });
  const wrapper = await render();
  expect(wrapper.emitted('confirmed')).toHaveLength(1);
  expect(sessionStorage.getItem(key)).toBeNull();
});
