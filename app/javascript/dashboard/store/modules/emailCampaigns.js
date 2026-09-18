import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import EmailCampaignsAPI from '../../api/emailCampaigns';

export const state = {
  records: [],
  recipients: [],
  importResult: null,
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isImporting: false,
  },
};

export const getters = {
  getCampaigns(_state) {
    return _state.records;
  },
  getRecipients(_state) {
    return _state.recipients;
  },
  getImportResult(_state) {
    return _state.importResult;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }, { silent = false, status, signal } = {}) => {
    if (!silent) commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isFetching: true });
    try {
      const response = await EmailCampaignsAPI.get({ status, signal });
      if (signal?.aborted) return;
      commit(types.SET_EMAIL_CAMPAIGNS, response.data.payload.campaigns || []);
    } finally {
      if (!silent)
        commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isFetching: false });
    }
  },
  getOne: async ({ commit }, id) => {
    const response = await EmailCampaignsAPI.show(id);
    commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload);
    return response.data.payload;
  },
  retryImport: async ({ commit }, id) => {
    const response = await EmailCampaignsAPI.retryImport(id);
    commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload.campaign);
    return response.data.payload;
  },
  create: async ({ commit }, payload) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isCreating: true });
    try {
      const response = await EmailCampaignsAPI.create({
        email_campaign: payload,
      });
      commit(types.ADD_EMAIL_CAMPAIGN, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isCreating: false });
    }
  },
  duplicate: async ({ commit }, id) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isCreating: true });
    try {
      const response = await EmailCampaignsAPI.duplicate(id);
      commit(types.ADD_EMAIL_CAMPAIGN, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...payload }) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      const response = await EmailCampaignsAPI.update(id, {
        email_campaign: payload,
      });
      commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
  delete: async ({ commit }, id) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isDeleting: true });
    try {
      await EmailCampaignsAPI.delete(id);
      commit(types.DELETE_EMAIL_CAMPAIGN, id);
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isDeleting: false });
    }
  },
  sendNow: async ({ commit }, id) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      const response = await EmailCampaignsAPI.sendNow(id);
      commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
  schedule: async ({ commit }, { id, scheduledAt }) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      const response = await EmailCampaignsAPI.schedule(id, scheduledAt);
      commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
  pause: async ({ commit }, id) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      const response = await EmailCampaignsAPI.pause(id);
      commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
  resume: async ({ commit }, id) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      const response = await EmailCampaignsAPI.resume(id);
      commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
  cancel: async ({ commit }, id) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      const response = await EmailCampaignsAPI.cancel(id);
      commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload);
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
  sendTest: async (_, { id, toEmail }) => {
    const response = await EmailCampaignsAPI.sendTest(id, toEmail);
    return response.data;
  },
  fetchPlaceholders: async (_, id) => {
    const response = await EmailCampaignsAPI.placeholders(id);
    return response.data;
  },
  validateTemplate: async (_, id) => {
    const response = await EmailCampaignsAPI.validate(id);
    return response.data;
  },
  getRecipients: async ({ commit }, { id, page = 1 }) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isFetching: true });
    try {
      const response = await EmailCampaignsAPI.getRecipients(id, page);
      commit(
        types.SET_EMAIL_CAMPAIGN_RECIPIENTS,
        response.data.payload.recipients || []
      );
      if (response.data.payload.campaign) {
        commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload.campaign);
      }
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isFetching: false });
    }
  },
  importRecipients: async ({ commit }, { id, file }) => {
    commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isImporting: true });
    try {
      const response = await EmailCampaignsAPI.importRecipients(id, file);
      if (response.status !== 202) {
        commit(
          types.SET_EMAIL_CAMPAIGN_RECIPIENTS,
          response.data.payload.recipients || []
        );
      }
      commit(
        types.SET_EMAIL_CAMPAIGN_IMPORT_RESULT,
        response.data.payload.import_result || null
      );
      if (response.data.payload.campaign) {
        commit(types.EDIT_EMAIL_CAMPAIGN, response.data.payload.campaign);
      }
      return response.data.payload;
    } finally {
      commit(types.SET_EMAIL_CAMPAIGN_UI_FLAG, { isImporting: false });
    }
  },
};

export const mutations = {
  [types.SET_EMAIL_CAMPAIGN_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.SET_EMAIL_CAMPAIGNS]: MutationHelpers.set,
  [types.ADD_EMAIL_CAMPAIGN]: MutationHelpers.create,
  [types.EDIT_EMAIL_CAMPAIGN]: MutationHelpers.update,
  [types.DELETE_EMAIL_CAMPAIGN]: MutationHelpers.destroy,
  [types.SET_EMAIL_CAMPAIGN_RECIPIENTS](_state, data) {
    _state.recipients = data;
  },
  [types.SET_EMAIL_CAMPAIGN_IMPORT_RESULT](_state, data) {
    _state.importResult = data;
  },
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
