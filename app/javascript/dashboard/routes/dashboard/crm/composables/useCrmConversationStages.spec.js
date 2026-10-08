import { flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import {
  useCrmConversationStage,
  refreshCrmConversationStage,
} from './useCrmConversationStages';

vi.mock('dashboard/api/crmKanban', () => ({
  default: { getConversationCardStages: vi.fn() },
}));

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

const answer = payload => ({ data: { payload } });

it('refreshes a badge and never lets an older answer overwrite the new one', async () => {
  let resolveFirst;
  CrmKanbanAPI.getConversationCardStages
    .mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirst = resolve;
        })
    )
    .mockResolvedValueOnce(answer({ 501: { title: 'Novo assunto' } }));

  const stage = useCrmConversationStage(ref(501));
  vi.advanceTimersByTime(60);

  refreshCrmConversationStage(501);
  vi.advanceTimersByTime(60);
  await flushPromises();
  expect(stage.value).toEqual({ title: 'Novo assunto' });

  resolveFirst(answer({ 501: { title: 'Assunto antigo' } }));
  await flushPromises();
  expect(stage.value).toEqual({ title: 'Novo assunto' });
});
