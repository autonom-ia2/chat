import { frontendURL } from '../../../helper/URLHelper';
import CentralDeAjudaInicio from './pages/CentralDeAjudaInicio.vue';
import CentralDeAjudaArtigo from './pages/CentralDeAjudaArtigo.vue';

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
  {
    path: frontendURL('accounts/:accountId/central-de-ajuda/:ref'),
    name: 'central_de_ajuda_artigo',
    meta,
    component: CentralDeAjudaArtigo,
  },
];

export default { routes };
