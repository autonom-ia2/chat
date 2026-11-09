import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import CampaignImportsAPI from '../../api/campaignImports';

export const state = {
  records: [],
  meta: {
    count: 0,
    currentPage: 1,
  },
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isConfirming: false,
    isUndoing: false,
    isDeleting: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getCampaignImports(_state) {
    return _state.records;
  },
  getMeta(_state) {
    return _state.meta;
  },
};

export const actions = {
  get: async ({ commit }, { page = 1, silent = false } = {}) => {
    if (!silent) {
      commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isFetching: true });
    }
    try {
      const response = await CampaignImportsAPI.get(page);
      commit(types.SET_CAMPAIGN_IMPORTS, response.data.payload || []);
      commit(types.SET_CAMPAIGN_IMPORT_META, response.data.meta || {});
    } finally {
      if (!silent) {
        commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isFetching: false });
      }
    }
  },

  create: async ({ commit }, payload) => {
    commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isCreating: true });
    try {
      const response = await CampaignImportsAPI.createImport(payload);
      commit(types.ADD_CAMPAIGN_IMPORT, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isCreating: false });
    }
  },

  confirm: async ({ commit }, id) => {
    commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isConfirming: true });
    try {
      const response = await CampaignImportsAPI.confirm(id);
      commit(types.EDIT_CAMPAIGN_IMPORT, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isConfirming: false });
    }
  },

  undoLabels: async ({ commit }, id) => {
    commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isUndoing: true });
    try {
      const response = await CampaignImportsAPI.undoLabels(id);
      commit(types.EDIT_CAMPAIGN_IMPORT, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isUndoing: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isDeleting: true });
    try {
      await CampaignImportsAPI.deleteImport(id);
      commit(types.DELETE_CAMPAIGN_IMPORT, id);
    } finally {
      commit(types.SET_CAMPAIGN_IMPORT_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_CAMPAIGN_IMPORT_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.SET_CAMPAIGN_IMPORT_META](_state, data) {
    _state.meta = {
      ..._state.meta,
      ...data,
    };
  },
  [types.ADD_CAMPAIGN_IMPORT]: MutationHelpers.create,
  [types.SET_CAMPAIGN_IMPORTS]: MutationHelpers.set,
  [types.EDIT_CAMPAIGN_IMPORT]: MutationHelpers.update,
  // O total de "Públicos salvos" vem do meta da listagem; ao excluir, ele cai
  // junto com a linha, sem esperar a próxima busca (#2834).
  [types.DELETE_CAMPAIGN_IMPORT](_state, id) {
    const existed = _state.records.some(record => record.id === id);
    MutationHelpers.destroy(_state, id);
    if (!existed) return;
    _state.meta = {
      ..._state.meta,
      count: Math.max((_state.meta.count || 0) - 1, 0),
    };
  },
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
