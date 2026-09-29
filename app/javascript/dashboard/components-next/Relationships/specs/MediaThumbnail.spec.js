import { mount, flushPromises } from '@vue/test-utils';
import axios from 'axios';
import MediaThumbnail from '../MediaThumbnail.vue';

const observer = vi.hoisted(() => ({ callback: null }));
vi.mock('axios', () => ({ default: { get: vi.fn() } }));
vi.mock('@vueuse/core', () => ({
  useIntersectionObserver: (_target, callback) => {
    observer.callback = callback;
  },
}));

beforeEach(() => {
  vi.useFakeTimers();
  vi.clearAllMocks();
});
afterEach(() => {
  vi.useRealTimers();
});

it('loads only visible rows, polls beyond converter timeout and stops when leaving viewport', async () => {
  axios.get.mockResolvedValue({
    status: 202,
    data: new Blob(['pending'], { type: 'application/json' }),
  });
  const wrapper = mount(MediaThumbnail, {
    props: { url: '/preview/1', name: 'video.mp4', type: 'video' },
  });
  await flushPromises();
  expect(axios.get).not.toHaveBeenCalled();
  expect(wrapper.find('.i-lucide-video').exists()).toBe(true);
  observer.callback([{ isIntersecting: true }]);
  await flushPromises();
  await vi.advanceTimersByTimeAsync(20000);
  expect(axios.get.mock.calls.length).toBe(5);
  observer.callback([{ isIntersecting: false }]);
  await flushPromises();
  await vi.advanceTimersByTimeAsync(30000);
  expect(axios.get.mock.calls.length).toBe(5);
  wrapper.unmount();
});

it('keeps a permanently unavailable preview on the file fallback without retry', async () => {
  axios.get.mockResolvedValue({
    status: 200,
    data: new Blob([JSON.stringify({ status: 'unavailable' })], {
      type: 'application/json; charset=utf-8',
    }),
  });
  const wrapper = mount(MediaThumbnail, {
    props: { url: '/preview/1', name: 'audio.mp3', type: 'audio' },
  });
  observer.callback([{ isIntersecting: true }]);
  await flushPromises();
  await flushPromises();
  expect(wrapper.find('.i-lucide-music').exists()).toBe(true);
  expect(wrapper.find('button').exists()).toBe(false);
  wrapper.unmount();
});

it('offers an explicit retry and never creates an object URL for a late response', async () => {
  axios.get.mockRejectedValueOnce(new Error('offline'));
  const wrapper = mount(MediaThumbnail, {
    props: { url: '/preview/1', name: 'audio.mp3', type: 'audio' },
  });
  observer.callback([{ isIntersecting: true }]);
  await flushPromises();
  expect(wrapper.find('.i-lucide-music').exists()).toBe(true);
  let resolve;
  axios.get.mockImplementation(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  await wrapper.find('button').trigger('click');
  const create = vi.fn();
  vi.stubGlobal(
    'URL',
    class extends URL {
      static createObjectURL = create;
    }
  );
  wrapper.unmount();
  resolve({
    status: 200,
    data: new Blob(['synthetic'], { type: 'image/jpeg' }),
  });
  await flushPromises();
  expect(create).not.toHaveBeenCalled();
  vi.unstubAllGlobals();
});

// Match the dashboard bootstrap: feature requests use the configured global client.
const originalDashboardClient = window.axios;
beforeEach(() => {
  window.axios = axios;
});
afterEach(() => {
  window.axios = originalDashboardClient;
});
