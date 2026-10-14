import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/financial.json';
import fixture from '../../../../../../../spec/fixtures/autonomia_store/checkout.v1.json';
import StoreOwnedService from './StoreOwnedService.vue';

vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
const wrappers = [];
const render = activation => {
  const wrapper = mount(StoreOwnedService, {
    props: {
      entry: fixture.serviceSubscriptionDetailResponse.data,
      activations: activation ? [activation] : [],
      accounts: [{ id: 17, name: 'Example account' }],
    },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('renders a service with no activations', () => {
  expect(render().text()).toContain(
    fixture.serviceSubscriptionDetailResponse.data.service.name
  );
});

it('explains expiry and offers explicit enable, not a replay of the expired reservation', async () => {
  const wrapper = render({
    id: 'activation-1',
    accountId: 17,
    serviceSubscriptionId:
      fixture.serviceSubscriptionDetailResponse.data.subscription.id,
    state: 'failed',
    available: false,
    errorCode: 'RESERVATION_EXPIRED',
  });
  expect(wrapper.text()).toContain(en.FINANCIAL.STORE.RESERVATION_EXPIRED);
  expect(
    wrapper
      .findAll('button')
      .some(
        button =>
          button.attributes('aria-label') ===
          en.FINANCIAL.STORE.PUBLICATION.RETRY
      )
  ).toBe(false);
  await wrapper
    .findAll('button')
    .find(button => button.text() === en.FINANCIAL.STORE.ACTIVATE)
    .trigger('click');
  expect(wrapper.emitted('activate')).toHaveLength(1);
  expect(wrapper.emitted('resume')).toBeUndefined();
});

it('shows ready-but-unavailable as suspended and can request a projection refresh', async () => {
  const wrapper = render({
    id: 'activation-1',
    accountId: 17,
    serviceSubscriptionId:
      fixture.serviceSubscriptionDetailResponse.data.subscription.id,
    state: 'ready',
    available: false,
  });
  expect(wrapper.text()).toContain(
    en.FINANCIAL.STORE.ACTIVATION_STATES.SUSPENDED
  );
  await wrapper
    .findAll('button')
    .find(
      button =>
        button.attributes('aria-label') === en.FINANCIAL.STORE.PUBLICATION.RETRY
    )
    .trigger('click');
  expect(wrapper.emitted('resume')).toHaveLength(1);
});
