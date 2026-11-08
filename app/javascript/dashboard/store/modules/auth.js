import types from '../mutation-types';
import authAPI from '../../api/auth';

import {
  setAuthCredentials,
  setUser,
  clearCookiesOnLogout,
} from '../utils/api';
import SessionStorage from 'shared/helpers/sessionStorage';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';

const initialState = {
  currentUser: {
    id: null,
    account_id: null,
    accounts: [],
    email: null,
    name: null,
  },
  uiFlags: {
    isFetching: true,
  },
};

// getters
export const getters = {
  isLoggedIn($state) {
    return !!$state.currentUser.id;
  },

  getCurrentUserID($state) {
    return $state.currentUser.id;
  },

  getUISettings($state) {
    return $state.currentUser.ui_settings || {};
  },

  getAuthUIFlags($state) {
    return $state.uiFlags;
  },

  getCurrentUserAvailability($state, $getters) {
    const { accounts = [] } = $state.currentUser;
    const [currentAccount = {}] = accounts.filter(
      account => account.id === $getters.getCurrentAccountId
    );
    return currentAccount.availability;
  },

  getCurrentUserAutoOffline($state, $getters) {
    const { accounts = [] } = $state.currentUser;
    const [currentAccount = {}] = accounts.filter(
      account => account.id === $getters.getCurrentAccountId
    );
    return currentAccount.auto_offline;
  },

  getCurrentAccountId(_, __, rootState) {
    if (rootState.route.params && rootState.route.params.accountId) {
      return Number(rootState.route.params.accountId);
    }
    return null;
  },

  getCurrentRole($state, $getters) {
    const { accounts = [] } = $state.currentUser;
    const [currentAccount = {}] = accounts.filter(
      account => account.id === $getters.getCurrentAccountId
    );
    return currentAccount.role;
  },

  getCurrentCustomRoleId($state, $getters) {
    const { accounts = [] } = $state.currentUser;
    const [currentAccount = {}] = accounts.filter(
      account => account.id === $getters.getCurrentAccountId
    );
    return currentAccount.custom_role_id;
  },

  getCurrentUser($state) {
    return $state.currentUser;
  },

  getMessageSignature($state) {
    const { message_signature: messageSignature } = $state.currentUser;

    return messageSignature || '';
  },

  getCurrentAccount($state, $getters) {
    const { accounts = [] } = $state.currentUser;
    const [currentAccount = {}] = accounts.filter(
      account => account.id === $getters.getCurrentAccountId
    );
    return currentAccount || {};
  },

  getUserAccounts($state) {
    const { accounts = [] } = $state.currentUser;
    return accounts;
  },
};

// Fork (#2308): o usuário de agora entra na store e é avisado ao widget e à análise (setUser), num lugar só. O
// validityCheck e quem já tem o usuário em mãos (setCurrentUser, a gaveta de Funções) passam por aqui.
const applyCurrentUser = (commit, currentUser) => {
  setUser(currentUser);
  commit(types.SET_CURRENT_USER, currentUser);
};

// actions
export const actions = {
  async validityCheck(context) {
    try {
      const response = await authAPI.validityCheck();
      applyCurrentUser(context.commit, response.data.payload.data);
    } catch (error) {
      if (error?.response?.status === 401) {
        clearCookiesOnLogout();
      }
    }
  },
  setCurrentUser({ commit }, currentUser) {
    applyCurrentUser(commit, currentUser);
  },
  async setUser({ commit, dispatch }) {
    if (authAPI.hasAuthCookie()) {
      await dispatch('validityCheck');
    } else {
      commit(types.CLEAR_USER);
    }
    commit(types.SET_CURRENT_USER_UI_FLAGS, { isFetching: false });
  },
  async loginWithSso({ commit }, { email, ssoAuthToken }) {
    const response = await authAPI.loginWithSso({ email, ssoAuthToken });
    const currentUser = response.data.data;

    setAuthCredentials(response);
    commit(types.SET_CURRENT_USER, currentUser);
    commit(types.SET_CURRENT_USER_UI_FLAGS, { isFetching: false });

    return currentUser;
  },
  logout({ commit }) {
    commit(types.CLEAR_USER);
  },

  updateProfile: async ({ commit }, params) => {
    // eslint-disable-next-line no-useless-catch
    try {
      const response = await authAPI.profileUpdate(params);
      commit(types.SET_CURRENT_USER, response.data);
    } catch (error) {
      throw error;
    }
  },

  updatePassword: async ({ commit }, params) => {
    // eslint-disable-next-line no-useless-catch
    try {
      const response = await authAPI.profilePasswordUpdate(params);
      commit(types.SET_CURRENT_USER, response.data);
    } catch (error) {
      throw error;
    }
  },

  deleteAvatar: async ({ commit }) => {
    try {
      const response = await authAPI.deleteAvatar();
      commit(types.SET_CURRENT_USER, response.data);
    } catch (error) {
      // Ignore error
    }
  },

  updateUISettings: async ({ commit }, params) => {
    try {
      commit(types.SET_CURRENT_USER_UI_SETTINGS, params);

      const isImpersonating = SessionStorage.get(
        SESSION_STORAGE_KEYS.IMPERSONATION_USER
      );

      if (!isImpersonating) {
        const response = await authAPI.updateUISettings(params);
        commit(types.SET_CURRENT_USER, response.data);
      }
    } catch (error) {
      // Ignore error
    }
  },

  updateAvailability: async (
    { commit, dispatch, getters: _getters },
    params
  ) => {
    const previousStatus = _getters.getCurrentUserAvailability;

    try {
      // optimisticly update current status
      commit(types.SET_CURRENT_USER_AVAILABILITY, params.availability);
      const response = await authAPI.updateAvailability(params);
      const userData = response.data;
      const { id } = userData;
      commit(types.SET_CURRENT_USER, response.data);
      dispatch('agents/updateSingleAgentPresence', {
        id,
        availabilityStatus: params.availability,
      });
    } catch (error) {
      // revert back to previous status if update fails
      commit(types.SET_CURRENT_USER_AVAILABILITY, previousStatus);
    }
  },

  updateAutoOffline: async (
    { commit, getters: _getters },
    { accountId, autoOffline }
  ) => {
    const previousAutoOffline = _getters.getCurrentUserAutoOffline;

    try {
      commit(types.SET_CURRENT_USER_AUTO_OFFLINE, autoOffline);
      const response = await authAPI.updateAutoOffline(accountId, autoOffline);
      commit(types.SET_CURRENT_USER, response.data);
    } catch (error) {
      commit(types.SET_CURRENT_USER_AUTO_OFFLINE, previousAutoOffline);
    }
  },

  setCurrentUserAvailability({ commit, state: $state }, data) {
    if (data[$state.currentUser.id]) {
      commit(types.SET_CURRENT_USER_AVAILABILITY, data[$state.currentUser.id]);
    }
  },

  setActiveAccount: async (_, { accountId }) => {
    try {
      await authAPI.setActiveAccount({ accountId });
    } catch (error) {
      // Ignore error
    }
  },

  resetAccessToken: async ({ commit }) => {
    try {
      const response = await authAPI.resetAccessToken();
      commit(types.SET_CURRENT_USER, response.data);
      return true;
    } catch (error) {
      return false;
    }
  },

  resendConfirmation: async () => {
    try {
      await authAPI.resendConfirmation();
    } catch (error) {
      // Ignore error
    }
  },
};

// mutations
export const mutations = {
  [types.SET_CURRENT_USER_AVAILABILITY](_state, availability) {
    const accounts = _state.currentUser.accounts.map(account => {
      if (account.id === _state.currentUser.account_id) {
        return { ...account, availability, availability_status: availability };
      }
      return account;
    });
    _state.currentUser = {
      ..._state.currentUser,
      accounts,
    };
  },
  [types.SET_CURRENT_USER_AUTO_OFFLINE](_state, autoOffline) {
    const accounts = _state.currentUser.accounts.map(account => {
      if (account.id === _state.currentUser.account_id) {
        return { ...account, autoOffline: autoOffline };
      }
      return account;
    });

    _state.currentUser = {
      ..._state.currentUser,
      accounts,
    };
  },
  [types.RESET_ONBOARDING](_state, accountId) {
    const accounts = _state.currentUser.accounts.map(account => {
      if (account.id === accountId) {
        const { onboarding_step, ...rest } = account;
        return rest;
      }
      return account;
    });

    _state.currentUser = {
      ..._state.currentUser,
      accounts,
    };
  },
  [types.CLEAR_USER](_state) {
    _state.currentUser = initialState.currentUser;
  },
  [types.SET_CURRENT_USER](_state, currentUser) {
    _state.currentUser = currentUser;
  },
  [types.SET_CURRENT_USER_UI_SETTINGS](_state, { uiSettings }) {
    _state.currentUser = {
      ..._state.currentUser,
      ui_settings: {
        ..._state.currentUser.ui_settings,
        ...uiSettings,
      },
    };
  },

  [types.SET_CURRENT_USER_UI_FLAGS](_state, { isFetching }) {
    _state.uiFlags = { isFetching };
  },
};

export default {
  state: initialState,
  getters,
  actions,
  mutations,
};
