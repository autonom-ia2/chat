import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h, reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/financial.json';
import StoreAPI from 'dashboard/api/autonomia/store';
import fixture from '../../../../../../../spec/fixtures/autonomia_store/lifecycle.v1.json';
import StoreRenewalDialog from './StoreRenewalDialog.vue';

const route = reactive({ params: { accountId: '17' } });
vi.mock('vue-router', () => ({ useRoute: () => route }));
vi.mock('dashboard/api/autonomia/store', () => ({
  default: {
    cancellationCapability: vi.fn(),
    subscriptionCommand: vi.fn(),
    commandStatus: vi.fn(),
    retryCommand: vi.fn(),
  },
}));
const DialogStub = defineComponent({
  props: {
    disableConfirmButton: Boolean,
    confirmButtonLabel: { type: String, default: '' },
  },
  emits: ['confirm', 'close'],
  methods: {
    open() {},
    close() {
      this.$emit('close');
    },
  },
  render() {
    return h('div', [
      this.$slots.default?.(),
      h(
        'button',
        {
          'data-test': 'confirm',
          disabled: this.disableConfirmButton,
          onClick: () => this.$emit('confirm'),
        },
        this.confirmButtonLabel
      ),
    ]);
  },
});
const wrappers = [];
const entry = {
  service: { name: 'Fictitious service' },
  subscription: {
    id: fixture.cancellationCapability.data.serviceSubscriptionId,
  },
};
const render = async () => {
  const wrapper = mount(StoreRenewalDialog, {
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: { Dialog: DialogStub },
    },
  });
  wrappers.push(wrapper);
  await wrapper.vm.open(entry);
  await flushPromises();
  return wrapper;
};
beforeEach(() => {
  vi.useFakeTimers();
  vi.clearAllMocks();
  route.params.accountId = '17';
  StoreAPI.cancellationCapability.mockResolvedValue({
    data: { ...fixture.cancellationCapability, localCommand: null },
  });
  StoreAPI.subscriptionCommand.mockResolvedValue({
    data: { data: { id: 'command-1', state: 'pending' } },
  });
  StoreAPI.commandStatus.mockResolvedValue({
    data: { data: { id: 'command-1', state: 'pending' } },
  });
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.useRealTimers();
});

it('displays the paid end date and scope, but waits for explicit confirmation', async () => {
  const wrapper = await render();
  expect(wrapper.text()).toContain('Paid access until');
  expect(wrapper.text()).toContain(en.FINANCIAL.STORE.CANCELLATION.SCOPE);
  expect(wrapper.text()).not.toContain('fictitious-e4-buyer');
  expect(StoreAPI.subscriptionCommand).not.toHaveBeenCalled();
  await wrapper.get('[data-test="confirm"]').trigger('click');
  await flushPromises();
  expect(StoreAPI.subscriptionCommand).toHaveBeenCalledWith(
    entry.subscription.id,
    'schedule',
    {
      clientIntent: expect.any(String),
      expectedVersion: 1,
    }
  );
  await vi.advanceTimersByTimeAsync(65000);
  expect(StoreAPI.subscriptionCommand).toHaveBeenCalledTimes(1);
  expect(wrapper.text()).toContain(en.FINANCIAL.STORE.COMMAND_PENDING);
  expect(wrapper.emitted('changed')).toBeUndefined();
});

it('only updates renewal after the saved command is confirmed and fresh capability is read', async () => {
  const wrapper = await render();
  StoreAPI.commandStatus.mockResolvedValue({
    data: { data: { id: 'command-1', state: 'confirmed' } },
  });
  StoreAPI.cancellationCapability.mockResolvedValue({
    data: {
      data: fixture.cancellationCommandResponse.data,
      localCommand: null,
    },
  });
  await wrapper.get('[data-test="confirm"]').trigger('click');
  await flushPromises();
  expect(wrapper.emitted('changed')).toHaveLength(1);
  expect(wrapper.text()).toContain(en.FINANCIAL.STORE.CANCELLATION.SCHEDULED);
  expect(wrapper.get('[data-test="confirm"]').text()).toBe(
    en.FINANCIAL.STORE.CANCELLATION.RESUME
  );
});

it('keeps an unknown existing command separate from a new cancellation or reversal', async () => {
  StoreAPI.cancellationCapability.mockResolvedValue({
    data: {
      ...fixture.cancellationCapability,
      localCommand: { id: 'command-existing', state: 'pending' },
    },
  });
  StoreAPI.retryCommand.mockResolvedValue({
    data: { data: { id: 'command-existing', state: 'pending' } },
  });
  const wrapper = await render();
  expect(
    wrapper.get('[data-test="confirm"]').attributes('disabled')
  ).toBeDefined();
  await wrapper
    .findAll('button')
    .find(
      button => button.text() === en.FINANCIAL.STORE.CANCELLATION.RETRY_COMMAND
    )
    .trigger('click');
  await flushPromises();
  expect(StoreAPI.retryCommand).toHaveBeenCalledWith('command-existing');
  expect(StoreAPI.subscriptionCommand).not.toHaveBeenCalled();
});

it('does not invent trial cancellation eligibility or display private upstream errors', async () => {
  const data = {
    ...fixture.cancellationCapability.data,
    canSchedule: false,
    blockingReason: 'trial_policy_not_defined',
    accessUntil: null,
  };
  StoreAPI.cancellationCapability.mockResolvedValue({
    data: { data, localCommand: null },
  });
  const wrapper = await render();
  expect(
    wrapper.get('[data-test="confirm"]').attributes('disabled')
  ).toBeDefined();
  expect(wrapper.text()).toContain(
    en.FINANCIAL.STORE.CANCELLATION.BLOCKERS.TRIAL
  );
  expect(StoreAPI.subscriptionCommand).not.toHaveBeenCalled();
});

it('requires refreshing a version conflict instead of automatically replaying with a newer version', async () => {
  StoreAPI.commandStatus.mockResolvedValue({
    data: {
      data: { id: 'command-1', state: 'blocked', errorCode: 'CONFLICT' },
    },
  });
  const wrapper = await render();
  await wrapper.get('[data-test="confirm"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain(en.FINANCIAL.STORE.COMMAND_CONFLICT);
  expect(
    wrapper.get('[data-test="confirm"]').attributes('disabled')
  ).toBeDefined();
  await vi.advanceTimersByTimeAsync(65000);
  expect(StoreAPI.subscriptionCommand).toHaveBeenCalledTimes(1);
});
