import types from '../../../mutation-types';
import { mutations } from '../../campaignImports';

// #2834: "Públicos salvos" (meta.count) cai junto com a linha excluída.
describe('#mutations', () => {
  describe('#DELETE_CAMPAIGN_IMPORT', () => {
    it('removes the record and lowers meta.count', () => {
      const state = {
        records: [{ id: 1 }, { id: 2 }],
        meta: { count: 6, currentPage: 1 },
      };
      mutations[types.DELETE_CAMPAIGN_IMPORT](state, 1);
      expect(state.records).toEqual([{ id: 2 }]);
      expect(state.meta).toEqual({ count: 5, currentPage: 1 });
    });

    it('keeps meta.count when the record is not in the list', () => {
      const state = { records: [{ id: 2 }], meta: { count: 6 } };
      mutations[types.DELETE_CAMPAIGN_IMPORT](state, 9);
      expect(state.records).toEqual([{ id: 2 }]);
      expect(state.meta.count).toBe(6);
    });

    it('never goes below zero', () => {
      const state = { records: [{ id: 1 }], meta: { count: 0 } };
      mutations[types.DELETE_CAMPAIGN_IMPORT](state, 1);
      expect(state.meta.count).toBe(0);
    });
  });
});
