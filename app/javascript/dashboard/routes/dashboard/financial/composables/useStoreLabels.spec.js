import { mount } from '@vue/test-utils';
import { defineComponent, h, nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/financial.json';
import pt from 'dashboard/i18n/locale/pt_BR/financial.json';
import { useStoreLabels } from './useStoreLabels';

const wrappers = [];
const render = () => {
  let labels;
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en, pt_BR: pt },
  });
  wrappers.push(
    mount(
      defineComponent({
        setup() {
          labels = useStoreLabels();
          return () => h('div');
        },
      }),
      { global: { plugins: [i18n] } }
    )
  );
  return { labels, i18n };
};
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('has translated labels for every displayed store operation and configured metric kind', () => {
  const { labels } = render();
  expect(Object.keys(labels.value.checkout)).toEqual([
    'pending',
    'created',
    'payment_pending',
    'confirmation_pending',
    'reconciling',
    'completed',
    'expired',
    'failed',
  ]);
  [
    'groups',
    'cycles',
    'usage',
    'reset',
    'activation',
    'checkout',
    'features',
    'errors',
  ].forEach(group => {
    expect(
      Object.values(labels.value[group]).every(
        value => value && !value.startsWith('FINANCIAL.')
      )
    ).toBe(true);
  });
  expect(labels.value.activation.ready).toBe(
    en.FINANCIAL.STORE.ACTIVATION_STATES.READY
  );
  expect(labels.value.activation.suspended).toBe(
    en.FINANCIAL.STORE.ACTIVATION_STATES.SUSPENDED
  );
  expect(labels.value.errors.RESERVATION_EXPIRED).toBe(
    en.FINANCIAL.STORE.RESERVATION_EXPIRED
  );
});

it('updates the shared labels when the locale changes without rebuilding the component', async () => {
  const { labels, i18n } = render();
  i18n.global.locale.value = 'pt_BR';
  await nextTick();
  expect(labels.value.groups.feature).toBe(pt.FINANCIAL.STORE.GROUPS.FEATURE);
  expect(labels.value.cycles.monthly).toBe(pt.FINANCIAL.STORE.CYCLES.MONTHLY);
  expect(labels.value.errors.SESSION_EXPIRED).toBe(
    pt.FINANCIAL.STORE.SESSION_EXPIRED
  );
});
