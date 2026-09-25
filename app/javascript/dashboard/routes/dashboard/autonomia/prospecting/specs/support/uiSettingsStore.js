// Store mínimo com as preferências do usuário (ui_settings), onde o tour da
// busca (#682) guarda que já foi mostrado. Guarda cada gravação para o teste
// conferir o que a tela pediu.
import { createStore } from 'vuex';

export const TOUR_ALREADY_SEEN = {
  prospecting_search_tour_seen_at: '2026-09-01T10:00:00.000Z',
};

export const uiSettingsStore = (initial = TOUR_ALREADY_SEEN) => {
  const saved = [];
  const store = createStore({
    state: () => ({ uiSettings: { ...initial } }),
    getters: {
      getUISettings: state => state.uiSettings,
    },
    mutations: {
      setUISettings(state, uiSettings) {
        state.uiSettings = uiSettings;
      },
    },
    actions: {
      updateUISettings({ commit }, { uiSettings }) {
        saved.push(uiSettings);
        commit('setUISettings', uiSettings);
      },
    },
  });
  return { store, saved };
};
