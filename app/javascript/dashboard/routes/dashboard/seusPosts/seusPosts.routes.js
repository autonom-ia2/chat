import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';

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
    component: () => import('./pages/SeusPostsPage.vue'),
  },
];
