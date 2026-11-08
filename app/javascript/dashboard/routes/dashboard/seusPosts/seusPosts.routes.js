import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { comFlags, comFlagsDaRota } from 'dashboard/helper/comFlags';
import { flagsDoCuidado, redeDoPerfil } from './seusPostsDados';

export const ensureSeusPostsEnabled = comFlags(FEATURE_FLAGS.SEUS_POSTS);
// O post aqui dentro (F2, #2305): também com a flag dos comentários.
export const ensureSeusPostsComentariosEnabled = comFlags(
  FEATURE_FLAGS.SEUS_POSTS,
  FEATURE_FLAGS.SEUS_POSTS_COMENTARIOS
);
// Cuidar dos comentários de um post (#2212, B1): a régua do cuidado (#2520), a mesma do servidor: a tela
// (seus_posts), a flag do cuidado e a dos comentários da rede do perfil (?perfil=instagram-12). A
// seus_posts_comentarios é só a do post por dentro.
export const ensureCuidarEnabled = comFlagsDaRota(to => {
  const doCuidado = flagsDoCuidado(redeDoPerfil(to.query?.perfil));
  return doCuidado && [FEATURE_FLAGS.SEUS_POSTS, ...doCuidado];
});

// Seus posts (#2302): página própria em Crescer, atrás da flag seus_posts. Administrador ou posts_view/posts_manage
// (parecer da Funções, 27/10). O post, com os comentários, é da F2 (#2305): o perfil vai em ?perfil=.
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
  {
    path: frontendURL('accounts/:accountId/seus-posts/:postId'),
    name: 'seus_posts_post',
    meta: {
      featureFlag: FEATURE_FLAGS.SEUS_POSTS_COMENTARIOS,
      permissions: ['administrator', 'posts_view', 'posts_manage'],
    },
    beforeEnter: ensureSeusPostsComentariosEnabled,
    component: () => import('./pages/SeusPostPage.vue'),
  },
  {
    path: frontendURL('accounts/:accountId/seus-posts/:postId/cuidar'),
    name: 'seus_posts_cuidar',
    meta: {
      featureFlag: FEATURE_FLAGS.META_ADS_COMENTARIOS_IA,
      permissions: ['administrator', 'posts_view', 'posts_manage'],
    },
    beforeEnter: ensureCuidarEnabled,
    component: () => import('./pages/CuidarComentariosPage.vue'),
  },
];
