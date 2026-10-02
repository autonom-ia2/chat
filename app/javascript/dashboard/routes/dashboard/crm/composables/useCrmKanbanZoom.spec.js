import { mount } from '@vue/test-utils';
import { defineComponent, h, nextTick, ref } from 'vue';
import { LocalStorage } from 'shared/helpers/localStorage';
import { useCrmKanbanZoom } from './useCrmKanbanZoom';
import {
  KANBAN_ZOOM_CLASSES,
  KANBAN_ZOOM_PRESETS,
} from '../helpers/kanbanZoom';

const currentUser = ref({ id: 7 });
const accountId = ref(16);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => (key === 'getCurrentUser' ? currentUser : accountId),
}));

const KEY = 'chat2you.crm.kanban.zoom.v1:7:16';
const wrappers = [];
const mountZoom = () => {
  let zoom;
  const wrapper = mount(
    defineComponent({
      setup() {
        zoom = useCrmKanbanZoom();
        return () => h('div', String(zoom.zoom.value));
      },
    })
  );
  wrappers.push(wrapper);
  return zoom;
};

beforeEach(() => {
  localStorage.clear();
  currentUser.value = { id: 7 };
  accountId.value = 16;
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.restoreAllMocks();
});

describe('Kanban zoom preference', () => {
  it('starts at 100 and provides exactly the approved presets', () => {
    expect(mountZoom().zoom.value).toBe(100);
    expect(KANBAN_ZOOM_PRESETS).toEqual([80, 90, 100, 110, 120]);
  });

  it.each(Array.from({ length: 61 }, (_, index) => index + 70))(
    'persists and restores the exact integer %i',
    value => {
      const first = mountZoom();
      first.setZoom(value);
      expect(first.zoom.value).toBe(value);
      expect(mountZoom().zoom.value).toBe(value);
      expect(first.zoomClass.value).toBe(KANBAN_ZOOM_CLASSES[value]);
      expect(KANBAN_ZOOM_CLASSES[value]).toContain('[zoom:');
    }
  );

  it('increments by one, clamps both limits and never allows 69 or 131', () => {
    const state = mountZoom();
    state.setZoom(state.zoom.value - 1);
    expect(state.zoom.value).toBe(99);
    state.setZoom(state.zoom.value + 1);
    expect(state.zoom.value).toBe(100);
    state.setZoom(69);
    expect(state.zoom.value).toBe(70);
    state.setZoom(131);
    expect(state.zoom.value).toBe(130);
  });

  it.each([null, '87', 87.5, NaN, Infinity, {}, []])(
    'rejects invalid interaction value %j',
    value => {
      const state = mountZoom();
      state.setZoom(value);
      expect(state.zoom.value).toBe(100);
      expect(localStorage.getItem(KEY)).toBeNull();
    }
  );

  it.each(['broken', 'null', '69', '131', '87.5', '{}', '"87"'])(
    'restores the default for corrupt stored value %s',
    raw => {
      localStorage.setItem(KEY, raw);
      expect(mountZoom().zoom.value).toBe(100);
    }
  );

  it('isolates accounts and users and restores the previous scope', async () => {
    const state = mountZoom();
    state.setZoom(87);
    accountId.value = 18;
    await nextTick();
    expect(state.zoom.value).toBe(100);
    state.setZoom(117);
    currentUser.value = { id: 8 };
    await nextTick();
    expect(state.zoom.value).toBe(100);
    currentUser.value = { id: 7 };
    await nextTick();
    expect(state.zoom.value).toBe(117);
    accountId.value = 16;
    await nextTick();
    expect(state.zoom.value).toBe(87);
  });

  it('does not write an anonymous preference before authentication is available', async () => {
    currentUser.value = {};
    const state = mountZoom();
    state.setZoom(87);
    expect(localStorage.length).toBe(0);
    currentUser.value = { id: 7 };
    await nextTick();
    expect(state.zoom.value).toBe(100);
  });

  it('reports unavailable persistence without breaking the presentation', () => {
    vi.spyOn(LocalStorage, 'set').mockImplementation(() => {
      throw new DOMException('blocked', 'SecurityError');
    });
    const state = mountZoom();
    state.setZoom(87);
    expect(state.zoom.value).toBe(87);
    expect(state.persistenceFailed.value).toBe(true);
  });

  it('does not rewrite an unchanged preference', () => {
    const spy = vi.spyOn(LocalStorage, 'set');
    const state = mountZoom();
    state.setZoom(87);
    state.setZoom(87);
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it('updates from another tab only for the current user/account', () => {
    const state = mountZoom();
    localStorage.setItem(KEY, '93');
    window.dispatchEvent(new StorageEvent('storage', { key: KEY }));
    expect(state.zoom.value).toBe(93);
    window.dispatchEvent(new StorageEvent('storage', { key: KEY + ':other' }));
    expect(state.zoom.value).toBe(93);
    localStorage.clear();
    window.dispatchEvent(new StorageEvent('storage', { key: null }));
    expect(state.zoom.value).toBe(100);
  });
});
