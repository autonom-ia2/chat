import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import StoreAPI from 'dashboard/api/autonomia/store';
import { useStoreActivation } from './useStoreActivation';

vi.mock('dashboard/api/autonomia/store', () => ({
  default: { activation: vi.fn() },
}));
const wrappers = [];
const pending = {
  data: { data: { id: 'activation-1', state: 'preparing', available: false } },
};
const render = () => {
  let activation;
  const settled = vi.fn();
  const wrapper = mount(
    defineComponent({
      setup() {
        activation = useStoreActivation(settled);
        return () => h('div');
      },
    })
  );
  wrappers.push(wrapper);
  return { activation, settled, wrapper };
};

beforeEach(() => {
  vi.useFakeTimers();
  vi.clearAllMocks();
  StoreAPI.activation.mockResolvedValue(pending);
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.useRealTimers();
});

describe('Store activation polling', () => {
  it('stops after a bounded number of reads without inventing success', async () => {
    const { activation, settled } = render();
    await activation.execute(async () => pending);
    await vi.advanceTimersByTimeAsync(65000);
    expect(StoreAPI.activation).toHaveBeenCalledTimes(13);
    expect(activation.busy.value).toBe(false);
    expect(activation.errorCode.value).toBe('ACTIVATION_PENDING');
    expect(settled).not.toHaveBeenCalled();
  });

  it('aborts an in-flight read and stops timers when the screen closes', async () => {
    let signal;
    let complete;
    StoreAPI.activation.mockImplementationOnce((id, requestSignal) => {
      signal = requestSignal;
      return new Promise(resolve => {
        complete = resolve;
      });
    });
    const { activation, settled, wrapper } = render();
    const processing = activation.execute(async () => pending);
    await flushPromises();
    wrapper.unmount();
    wrappers.splice(wrappers.indexOf(wrapper), 1);
    expect(signal.aborted).toBe(true);
    complete({
      data: { data: { id: 'activation-1', state: 'ready', available: true } },
    });
    await processing;
    await vi.advanceTimersByTimeAsync(65000);
    expect(settled).not.toHaveBeenCalled();
    expect(StoreAPI.activation).toHaveBeenCalledTimes(1);
  });

  it('does not continue polling after a read failure', async () => {
    StoreAPI.activation.mockRejectedValueOnce(new Error('read failed'));
    const { activation, settled } = render();
    await activation.execute(async () => pending);
    await vi.advanceTimersByTimeAsync(65000);
    expect(activation.errorCode.value).toBe('ACTIVATION_ERROR');
    expect(StoreAPI.activation).toHaveBeenCalledTimes(1);
    expect(settled).not.toHaveBeenCalled();
  });

  it('shows capacity exhaustion without declaring success or continuing to poll', async () => {
    StoreAPI.activation.mockResolvedValueOnce({
      data: {
        data: {
          id: 'activation-1',
          state: 'preparing',
          available: false,
          errorCode: 'USAGE_LIMIT_EXCEEDED',
        },
      },
    });
    const { activation, settled } = render();
    await activation.execute(async () => pending);
    await vi.advanceTimersByTimeAsync(65000);
    expect(activation.errorCode.value).toBe('LIMIT_EXCEEDED');
    expect(activation.busy.value).toBe(false);
    expect(StoreAPI.activation).toHaveBeenCalledTimes(1);
    expect(settled).not.toHaveBeenCalled();
  });

  it('shows an expired session during status reading without exposing upstream errors', async () => {
    StoreAPI.activation.mockRejectedValueOnce({
      response: { status: 401, data: { error: 'private upstream content' } },
    });
    const { activation } = render();
    await activation.execute(async () => pending);
    expect(activation.errorCode.value).toBe('SESSION_EXPIRED');
    expect(activation.busy.value).toBe(false);
  });

  it('requires an explicit new activation when the reservation expires', async () => {
    StoreAPI.activation.mockResolvedValueOnce({
      data: {
        data: {
          id: 'activation-1',
          state: 'failed',
          available: false,
          errorCode: 'RESERVATION_EXPIRED',
        },
      },
    });
    const { activation, settled } = render();
    await activation.execute(async () => pending);
    await vi.advanceTimersByTimeAsync(65000);
    expect(activation.errorCode.value).toBe('RESERVATION_EXPIRED');
    expect(activation.busy.value).toBe(false);
    expect(StoreAPI.activation).toHaveBeenCalledTimes(1);
    expect(settled).toHaveBeenCalledWith(
      expect.objectContaining({ state: 'failed', available: false })
    );
  });
});
