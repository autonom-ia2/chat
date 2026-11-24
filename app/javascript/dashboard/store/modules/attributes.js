import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import AttributeAPI from '../../api/attributes';
import camelcaseKeys from 'camelcase-keys';
import {
  chavesInternasDaConta,
  semChavesInternas,
} from 'dashboard/helper/chavesInternas';

// Fork (#2138, #3176): as definições das chaves internas (WAHA e controle da
// Prospecção; a lista vem do servidor, na resposta da conta) não saem para
// nenhuma tela. Ficam em records (e no servidor), só os getters as deixam de
// fora. Sem a lista (getters chamados sem os outros getters), nada a mais sai.
const visiveis = (records, moduleGetters) =>
  semChavesInternas(records, moduleGetters?.getChavesInternas);

export const state = {
  records: [],
  revision: 0,
  uiFlags: {
    isFetching: false,
    // Fork (#2744): a lista não veio. Quem diz "a conta não tem campo" precisa
    // distinguir lista vazia de lista que não carregou.
    fetchFailed: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getRevision: currentState => currentState.revision,
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  // As chaves internas da conta aberta (helper/chavesInternas.js).
  getChavesInternas: (_state, _getters, _rootState, rootGetters) =>
    chavesInternasDaConta(
      rootGetters?.['accounts/getAccount']?.(rootGetters?.getCurrentAccountId)
    ),
  getAttributes: (_state, _getters) => {
    return visiveis(_state.records, _getters);
  },
  getConversationAttributes: (_state, _getters) => {
    return visiveis(_state.records, _getters)
      .filter(record => record.attribute_model === 'conversation_attribute')
      .map(camelcaseKeys);
  },
  getContactAttributes: (_state, _getters) => {
    return visiveis(_state.records, _getters)
      .filter(record => record.attribute_model === 'contact_attribute')
      .map(camelcaseKeys);
  },
  getCompanyAttributes: (_state, _getters) => {
    return visiveis(_state.records, _getters)
      .filter(record => record.attribute_model === 'company_attribute')
      .map(camelcaseKeys);
  },
  getCardAttributes: (_state, _getters) => {
    return visiveis(_state.records, _getters)
      .filter(record => record.attribute_model === 'card_attribute')
      .map(camelcaseKeys);
  },
  getAttributesByModel: (_state, _getters) => attributeModel => {
    return visiveis(_state.records, _getters).filter(
      record => record.attribute_model === attributeModel
    );
  },
};

export const actions = {
  get: async function getAttributesByModel({ commit, state: currentState }) {
    commit(types.SET_CUSTOM_ATTRIBUTE_UI_FLAG, {
      isFetching: true,
      fetchFailed: false,
    });
    try {
      const revision = currentState.revision;
      const response = await AttributeAPI.getAttributesByModel();
      if (revision === currentState.revision)
        commit(types.SET_CUSTOM_ATTRIBUTE, response.data);
    } catch {
      commit(types.SET_CUSTOM_ATTRIBUTE_UI_FLAG, { fetchFailed: true });
    } finally {
      commit(types.SET_CUSTOM_ATTRIBUTE_UI_FLAG, { isFetching: false });
    }
  },
  create: async function createAttribute({ commit }, attributeObj) {
    commit(types.SET_CUSTOM_ATTRIBUTE_UI_FLAG, { isCreating: true });
    try {
      const response = await AttributeAPI.create(attributeObj);
      commit(types.ADD_CUSTOM_ATTRIBUTE, response.data);
    } catch (error) {
      const errorMessage = error?.response?.data?.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.SET_CUSTOM_ATTRIBUTE_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...updateObj }) => {
    commit(types.SET_CUSTOM_ATTRIBUTE_UI_FLAG, { isUpdating: true });
    try {
      const response = await AttributeAPI.update(id, updateObj);
      commit(types.EDIT_CUSTOM_ATTRIBUTE, response.data);
    } catch (error) {
      const errorMessage = error?.response?.data?.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.SET_CUSTOM_ATTRIBUTE_UI_FLAG, { isUpdating: false });
    }
  },
  delete: async ({ commit }, id) => {
    commit(types.SET_CUSTOM_ATTRIBUTE_UI_FLAG, { isDeleting: true });
    try {
      await AttributeAPI.delete(id);
      commit(types.DELETE_CUSTOM_ATTRIBUTE, id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CUSTOM_ATTRIBUTE_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_CUSTOM_ATTRIBUTE_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.ADD_CUSTOM_ATTRIBUTE](_state, data) {
    _state.revision += 1;
    MutationHelpers.create(_state, data);
  },
  [types.SET_CUSTOM_ATTRIBUTE](_state, data) {
    _state.revision += 1;
    MutationHelpers.set(_state, data);
  },
  [types.EDIT_CUSTOM_ATTRIBUTE](_state, data) {
    _state.revision += 1;
    MutationHelpers.update(_state, data);
  },
  [types.DELETE_CUSTOM_ATTRIBUTE](_state, data) {
    _state.revision += 1;
    MutationHelpers.destroy(_state, data);
  },
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
