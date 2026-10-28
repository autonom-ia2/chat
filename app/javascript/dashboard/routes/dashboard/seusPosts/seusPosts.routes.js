import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';
import store from 'dashboard/store';

// Link direto / F5: o guarda roda antes de a store ter a conta. Carrega a conta antes de decidir (mesmo cuidado de
// booking.routes.js); sem conta, ou com a flag desligada, vai para home.
export const ensureSeusPostsEnabled = async (to, _from, next) => {
  const accountId = Number(to.params.accountId);
  const ligada = () =>
    store.getters['accounts/isFeatureEnabledonAccount'](
      accountId,
      FEATURE_FLAGS.SEUS_POSTS
    );
  if (!store.getters['accounts/getAccount'](accountId)?.id) {
    try {
      await store.dispatch('accounts/get');
    } catch {
      next({ name: 'home', params: to.params });
      return;
    }
  }
  if (ligada()) next();
  else next({ name: 'home', params: to.params });
};

// Seus posts (#2302): página própria em Crescer, atrás da flag seus_posts. Administrador ou posts_view/posts_manage
// (parecer da Funções, 27/10). O detalhe do post chega na F2 (#2305).
export const routes = [
  {
    path: frontendURL('accounts/:accountId/seus-posts'),
    name: 'seus_posts_index',
    meta: {
      featureFlag: FEATURE_FLAGS.SEUS_POSTS,
      permissions: ['administrator', 'posts_view', 'posts_manage'],
    },
    beforeEnter: ensureSeusPostsEnabled,
    component: () => import('./pages/SeusPostsPage.vue'),
  },
];
