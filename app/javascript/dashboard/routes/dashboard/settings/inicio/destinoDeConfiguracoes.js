import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  getUserPermissions,
  hasPermissions,
} from 'dashboard/helper/permissionsHelper';
import { defaultRedirectPage } from 'dashboard/helper/routeHelpers';
import { contaDaRota } from '../../autonomia/contaDaRota';
import { menuNovoLigado } from './inicio.routes';

// Para onde vai `settings_home` (/settings). Antes era um `redirect` síncrono: no carregamento frio (endereço
// digitado ou F5) ele rodava antes de a conta e o usuário chegarem, não achava destino e quebrava em
// `landing.name` (tela branca, nas contas com e sem o menu novo). Agora é um `beforeEnter`: roda depois do guarda
// global que carrega o usuário, espera a conta (contaDaRota, #1618) e só então decide.
// - Menu novo ligado (#1617): a página de cartões.
// - Senão, a regra de sempre: administrador sem função vai para a Conta; os outros, para a primeira tela que
//   podem abrir (`landings`, na ordem do menu).
// - Sem nenhuma permitida, o mesmo destino do app quando falta permissão (defaultRedirectPage); nunca quebra.
export const destinoDeConfiguracoes = async (to, landings) => {
  const { params } = to;
  await contaDaRota(to);
  if (menuNovoLigado(store, params.accountId)) {
    return { name: 'settings_inicio', params };
  }
  if (
    store.getters.getCurrentRole === 'administrator' &&
    store.getters.getCurrentCustomRoleId === null
  ) {
    return { name: 'general_settings_index', params };
  }
  const permissions = getUserPermissions(
    store.getters.getCurrentUser,
    params.accountId
  );
  const landing = landings.find(page =>
    hasPermissions(page.permissions, permissions)
  );
  if (landing) return { name: landing.name, params };
  return frontendURL(defaultRedirectPage(to, permissions));
};
