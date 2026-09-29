import { createStore } from 'vuex';
import axios from 'axios';
import attributes from 'dashboard/store/modules/attributes';

vi.mock('axios', () => ({ default: { get: vi.fn() } }));
beforeEach(() => {
  vi.stubGlobal('axios', axios);
});
afterEach(() => {
  vi.unstubAllGlobals();
});

it('a legacy definitions read cannot overwrite a confirmed relationships definition in the real Vuex store', async () => {
  const store = createStore({
    modules: {
      attributes: {
        ...attributes,
        state: () => ({ records: [], revision: 0, uiFlags: {} }),
      },
    },
  });
  let resolve;
  axios.get.mockImplementation(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const pending = store.dispatch('attributes/get');
  store.commit('attributes/SET_CUSTOM_ATTRIBUTE', [
    { id: 1, attribute_display_name: 'Confirmed' },
  ]);
  resolve({ data: [{ id: 1, attribute_display_name: 'Stale' }] });
  await pending;
  expect(store.getters['attributes/getAttributes']).toEqual([
    { id: 1, attribute_display_name: 'Confirmed' },
  ]);
  expect(store.getters['attributes/getUIFlags'].isFetching).toBe(false);
});
