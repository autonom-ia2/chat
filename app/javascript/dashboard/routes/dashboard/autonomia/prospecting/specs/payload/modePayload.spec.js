// Pedaço do pedido da busca que pertence à frente de modo e jogadas (#677,
// E1): score_mode e scoring_profile_id no metadata.
import { choose, settingsFixture } from '../support/searchPageHarness';
import {
  openNewSearchForm,
  submitMinimalSearch,
} from '../support/searchFormHelpers';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: {} }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => true) };
});
vi.mock('dashboard/api/autonomiaProspecting', async () =>
  (await import('../support/searchPageMocks')).prospectingApiMock()
);
vi.mock('dashboard/api/crmKanban', async () =>
  (await import('../support/searchPageMocks')).crmKanbanApiMock()
);

describe('Pedido da busca · frente de modo', () => {
  it('manda o modo das configurações e o perfil de pontuação', async () => {
    const wrapper = await openNewSearchForm();

    const payload = await submitMinimalSearch(wrapper);

    expect(payload.metadata).toMatchObject({
      score_mode: 'general',
      scoring_profile_id: 9,
    });
  });

  it('manda o modo escolhido no formulário', async () => {
    const wrapper = await openNewSearchForm();
    await choose(wrapper, 'PROSPECTING.SEARCH.FIELDS.SCORE_MODE', 'gbp');

    const payload = await submitMinimalSearch(wrapper);

    expect(payload.metadata.score_mode).toBe('gbp');
  });

  it('sem modo nas configurações cai em gbp', async () => {
    const wrapper = await openNewSearchForm({
      settings: settingsFixture({
        search_score_mode: undefined,
        scoring_profile_id: undefined,
      }),
    });

    const payload = await submitMinimalSearch(wrapper);

    expect(payload.metadata.score_mode).toBe('gbp');
    expect(payload.metadata.scoring_profile_id).toBeUndefined();
  });
});
