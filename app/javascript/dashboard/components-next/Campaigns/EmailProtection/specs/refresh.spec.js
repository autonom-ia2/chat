import { mount, flushPromises } from '@vue/test-utils';
import { ref, nextTick } from 'vue';
import { useEmailReportRefresh } from '../useEmailReportRefresh';
import { hasActiveEmailWork } from '../presentation';

let wrapper;
beforeEach(() => {
  vi.useFakeTimers();
  vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
});
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
  vi.useRealTimers();
});
it.each([
  { status: 'sending' },
  { status: 'scheduled' },
  { recipient_import: { status: 'processing' } },
  { preflight: { status: 'analysing' } },
  { preflight: { counts: { unchecked: 1 } } },
  { protection: { state: 'paused' } },
  { ai_status: 'processing' },
])('continues past ten cycles for active work %j', async campaign => {
  const refresh = vi.fn().mockResolvedValue();
  wrapper = mount({
    setup() {
      useEmailReportRefresh(refresh, () => hasActiveEmailWork(campaign));
    },
    template: '<div />',
  });
  await vi.advanceTimersByTimeAsync(12 * 60000);
  expect(refresh).toHaveBeenCalledTimes(12);
  wrapper.unmount();
  await vi.advanceTimersByTimeAsync(600000);
  expect(refresh).toHaveBeenCalledTimes(12);
});
it('bounds idle backoff, stays live and resumes minute updates on new work', async () => {
  const active = ref(false);
  const refresh = vi.fn().mockResolvedValue();
  wrapper = mount({
    setup() {
      useEmailReportRefresh(refresh, () => active.value);
    },
    template: '<div />',
  });
  await vi.advanceTimersByTimeAsync(12 * 60000);
  expect(refresh).toHaveBeenCalledTimes(4); // 1, 3, 7, 12 minutes
  await vi.advanceTimersByTimeAsync(50 * 60000);
  expect(refresh).toHaveBeenCalledTimes(14);
  active.value = true;
  await nextTick();
  await vi.advanceTimersByTimeAsync(60000);
  expect(refresh).toHaveBeenCalledTimes(15);
});
it('does not overlap requests or restart after an in-flight unmount', async () => {
  let resolve;
  const refresh = vi.fn(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  wrapper = mount({
    setup() {
      useEmailReportRefresh(refresh, () => true);
    },
    template: '<div />',
  });
  await vi.advanceTimersByTimeAsync(20 * 60000);
  expect(refresh).toHaveBeenCalledTimes(1);
  wrapper.unmount();
  resolve();
  await flushPromises();
  await vi.advanceTimersByTimeAsync(20 * 60000);
  expect(refresh).toHaveBeenCalledTimes(1);
  expect(vi.getTimerCount()).toBe(0);
});
