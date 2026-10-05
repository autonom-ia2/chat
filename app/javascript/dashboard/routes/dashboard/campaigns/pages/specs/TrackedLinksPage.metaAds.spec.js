import { flushPromises, shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import TrackedLinksPage from '../TrackedLinksPage.vue';

// The "Meta campaign names" block (#1034) is for account administrators only.
const isAdmin = ref(true);
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin }),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => ref(true),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn().mockResolvedValue(true) }),
  useMapGetter: () => ref([{ id: 38, name: 'WhatsApp Vendas' }]),
}));
vi.mock('dashboard/api/ctwaTrackedLinks', () => ({
  default: { get: vi.fn().mockResolvedValue({ data: { payload: [] } }) },
}));

const mountPage = async () => {
  const wrapper = shallowMount(TrackedLinksPage);
  await flushPromises();
  return wrapper;
};

describe('TrackedLinksPage · Meta campaign names block', () => {
  it('shows the block to an administrator', async () => {
    isAdmin.value = true;
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsNamesCard' }).exists()).toBe(
      true
    );
  });

  it('hides the block from anyone else', async () => {
    isAdmin.value = false;
    const wrapper = await mountPage();

    expect(wrapper.findComponent({ name: 'MetaAdsNamesCard' }).exists()).toBe(
      false
    );
  });
});
