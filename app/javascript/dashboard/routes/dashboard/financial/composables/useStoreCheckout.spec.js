import { mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import StoreAPI from 'dashboard/api/autonomia/store';
import { useStoreCheckout } from './useStoreCheckout';
import { readCheckoutIntent } from '../helpers/storeCheckout';

vi.mock('dashboard/api/autonomia/store', () => ({
  default: { checkout: vi.fn(), resolveCheckout: vi.fn() },
}));

const wrappers = [];
const render = () => {
  const scope = ref('autonomia-store-checkout:1:17');
  const navigate = vi.fn();
  let checkout;
  wrappers.push(
    mount(
      defineComponent({
        setup() {
          checkout = useStoreCheckout(scope);
          return () => h('div');
        },
      }),
      { global: { provide: { storeCheckoutNavigate: navigate } } }
    )
  );
  return { scope, navigate, checkout };
};
const result = {
  data: {
    operation: { id: 'operation-1', state: 'created' },
    checkoutUrl: 'https://financial.example.test/checkout',
  },
};

beforeEach(() => {
  sessionStorage.clear();
  vi.clearAllMocks();
  StoreAPI.checkout.mockResolvedValue(result);
  StoreAPI.resolveCheckout.mockResolvedValue(result);
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

describe('Store checkout recovery', () => {
  it('persists the intent before sending and never saves an access token or payment URL', async () => {
    const { scope, checkout, navigate } = render();
    StoreAPI.checkout.mockImplementationOnce(async body => {
      expect(readCheckoutIntent(scope.value).clientIntent).toBe(
        body.clientIntent
      );
      expect(body.limits).toEqual([]);
      return result;
    });
    await checkout.start('price-1');
    const stored = readCheckoutIntent(scope.value);
    expect(Object.keys(stored).sort()).toEqual([
      'clientIntent',
      'operationId',
      'priceId',
    ]);
    expect(navigate).toHaveBeenCalledWith(
      result.data.checkoutUrl,
      'operation-1'
    );
  });

  it('resolves a failed attempt using its same intent without creating another charge', async () => {
    StoreAPI.checkout.mockRejectedValueOnce(new Error('lost response'));
    const { scope, checkout } = render();
    await checkout.start('price-1');
    const intent = readCheckoutIntent(scope.value).clientIntent;
    await checkout.resumePending();
    expect(StoreAPI.resolveCheckout).toHaveBeenCalledWith(intent);
    expect(StoreAPI.checkout).toHaveBeenCalledTimes(1);
    expect(readCheckoutIntent(scope.value).clientIntent).toBe(intent);
  });

  it('keeps the original intent even when resolve has no local record yet', async () => {
    StoreAPI.checkout.mockRejectedValueOnce(new Error('lost response'));
    const { scope, checkout } = render();
    await checkout.start('price-1');
    const intent = readCheckoutIntent(scope.value).clientIntent;
    StoreAPI.resolveCheckout.mockRejectedValueOnce({
      response: { status: 404 },
    });
    await checkout.resumePending();
    expect(StoreAPI.checkout.mock.calls[1][0].clientIntent).toBe(intent);
  });

  it('does not start another plan while an earlier checkout is unresolved', async () => {
    const { checkout } = render();
    await checkout.start('price-1');
    await checkout.start('price-2');
    expect(checkout.errorCode.value).toBe('PENDING_OTHER_PLAN');
    expect(StoreAPI.checkout).toHaveBeenCalledTimes(1);
  });

  it('keeps an expired intent while the server has not confirmed the subscription is canceled', async () => {
    const { scope, checkout } = render();
    await checkout.start('price-1');
    const intent = readCheckoutIntent(scope.value).clientIntent;
    StoreAPI.resolveCheckout.mockResolvedValueOnce({
      data: {
        operation: {
          id: 'operation-1',
          state: 'expired',
          canStartNewCheckout: false,
        },
      },
    });
    await checkout.resumePending();
    expect(readCheckoutIntent(scope.value).clientIntent).toBe(intent);
    expect(StoreAPI.checkout).toHaveBeenCalledTimes(1);
    expect(checkout.errorCode.value).toBe('CHECKOUT_PENDING');
  });

  it('clears a confirmed canceled purchase without automatically creating its replacement', async () => {
    const { scope, checkout, navigate } = render();
    await checkout.start('price-1');
    const original = readCheckoutIntent(scope.value).clientIntent;
    StoreAPI.resolveCheckout.mockResolvedValueOnce({
      data: {
        operation: {
          id: 'operation-1',
          state: 'expired',
          canStartNewCheckout: true,
        },
      },
    });
    await checkout.resumePending();
    expect(readCheckoutIntent(scope.value)).toBeNull();
    expect(StoreAPI.checkout).toHaveBeenCalledTimes(1);
    expect(navigate).toHaveBeenCalledTimes(1);
    expect(checkout.errorCode.value).toBe('CHECKOUT_ENDED');
    await checkout.start('price-1');
    expect(StoreAPI.checkout.mock.calls[1][0].clientIntent).not.toBe(original);
  });

  it('does not navigate after the popup closes while preserving the returned operation', async () => {
    let complete;
    StoreAPI.checkout.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    const { scope, checkout, navigate } = render();
    const pending = checkout.start('price-1');
    checkout.stop();
    complete(result);
    await pending;
    expect(navigate).not.toHaveBeenCalled();
    expect(readCheckoutIntent(scope.value).operationId).toBe('operation-1');
  });

  it('does not apply a late response to a different buyer/account scope', async () => {
    let complete;
    StoreAPI.checkout.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    const { scope, checkout, navigate } = render();
    const pending = checkout.start('price-1');
    scope.value = 'autonomia-store-checkout:2:18';
    complete(result);
    await pending;
    expect(navigate).not.toHaveBeenCalled();
    expect(readCheckoutIntent(scope.value)).toBeNull();
  });
});
