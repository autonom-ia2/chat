import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import * as types from '../mutation-types';
import CustomRoleAPI from '../../api/customRole';

// Guarda os campos recusados, o código do erro e o status (#2185, #2308): o editor mostra o nome repetido ao lado
// do campo, a lista abre a pergunta do destino quando o servidor diz que a função tem gente, e a conversa guiada
// separa o 401 (alcance, flag ou a própria função, pelo código no corpo) da sessão vencida.
const throwWithAttributes = error => {
  const failure = new Error(parseAPIErrorResponse(error));
  failure.attributes = error?.response?.data?.attributes || [];
  failure.code = error?.response?.data?.error;
  failure.status = error?.response?.status;
  throw failure;
};

export const state = {
  records: [],
  uiFlags: {
    fetchingList: false,
    // A lista nova de Funções (#2308) mostra o erro de rede em vez de uma lista vazia.
    fetchingListFailed: false,
    creatingItem: false,
    updatingItem: false,
    deletingItem: false,
  },
};

export const getters = {
  getCustomRoles($state) {
    return $state.records;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  getCustomRole: async function getCustomRole({ commit }) {
    commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { fetchingList: true });
    try {
      const response = await CustomRoleAPI.get();
      commit(types.default.SET_CUSTOM_ROLE, response.data);
      commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, {
        fetchingList: false,
        fetchingListFailed: false,
      });
    } catch (error) {
      commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, {
        fetchingList: false,
        fetchingListFailed: true,
      });
    }
  },

  createCustomRole: async function createCustomRole({ commit }, customRoleObj) {
    commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { creatingItem: true });
    try {
      const response = await CustomRoleAPI.create(customRoleObj);
      commit(types.default.ADD_CUSTOM_ROLE, response.data);
      commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { creatingItem: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { creatingItem: false });
      return throwWithAttributes(error);
    }
  },

  updateCustomRole: async function updateCustomRole(
    { commit },
    { id, ...updateObj }
  ) {
    commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { updatingItem: true });
    try {
      const response = await CustomRoleAPI.update(id, updateObj);
      commit(types.default.EDIT_CUSTOM_ROLE, response.data);
      commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { updatingItem: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { updatingItem: false });
      return throwWithAttributes(error);
    }
  },

  deleteCustomRole: async function deleteCustomRole(
    { commit },
    { id, destinationRoleId }
  ) {
    commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { deletingItem: true });
    try {
      await CustomRoleAPI.delete(id, destinationRoleId);
      commit(types.default.DELETE_CUSTOM_ROLE, id);
      commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { deletingItem: true });
      return id;
    } catch (error) {
      commit(types.default.SET_CUSTOM_ROLE_UI_FLAG, { deletingItem: true });
      return throwWithAttributes(error);
    }
  },
};

export const mutations = {
  [types.default.SET_CUSTOM_ROLE_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.default.SET_CUSTOM_ROLE]: MutationHelpers.set,
  [types.default.ADD_CUSTOM_ROLE]: MutationHelpers.create,
  [types.default.EDIT_CUSTOM_ROLE]: MutationHelpers.update,
  [types.default.DELETE_CUSTOM_ROLE]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
