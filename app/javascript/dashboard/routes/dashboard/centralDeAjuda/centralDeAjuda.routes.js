import { frontendURL } from '../../../helper/URLHelper';

const CentralDeAjudaInicio = () => import('./pages/CentralDeAjudaInicio.vue');
const CentralDeAjudaAssunto = () => import('./pages/CentralDeAjudaAssunto.vue');
const CentralDeAjudaArtigo = () => import('./pages/CentralDeAjudaArtigo.vue');

// Central de Ajuda da plataforma (#501): qualquer pessoa da conta lê. O que cada uma vê (recurso da
// conta, artigo só de administrador) o servidor decide.
const meta = { permissions: ['administrator', 'agent', 'custom_role'] };

export const routes = [
  {
    path: frontendURL('accounts/:accountId/central-de-ajuda'),
    name: 'central_de_ajuda',
    meta,
    component: CentralDeAjudaInicio,
  },
  // Dois segmentos (assunto/<capítulo>): não cruza com o artigo, que é um segmento só.
  {
    path: frontendURL('accounts/:accountId/central-de-ajuda/assunto/:capitulo'),
    name: 'central_de_ajuda_assunto',
    meta,
    component: CentralDeAjudaAssunto,
  },
  {
    path: frontendURL('accounts/:accountId/central-de-ajuda/:ref'),
    name: 'central_de_ajuda_artigo',
    meta,
    component: CentralDeAjudaArtigo,
  },
];

export default { routes };
