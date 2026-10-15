// SLA em Configurações (#1618): o fork tirou settings/sla do roteador quando o
// SLA foi para o CRM, mas a página inicial de Configurações ainda mandava quem
// só tem sla_manage para 'sla_list', rota que não existe. A tela de SLA é
// CRM › SLA, e ela precisa aceitar a mesma chave que a API do SLA confere.
import { createRouter, createMemoryHistory } from 'vue-router';
import settingsRoutes from '../settings.routes';
import { routes as crmRoutes } from '../../crm/crm.routes';

const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));
vi.mock('../../../../store', () => ({ default: store }));

const home = settingsRoutes.routes.find(
  route => route.name === 'settings_home'
);

const funcaoSo = permissions => {
  store.getters.getCurrentRole = 'agent';
  store.getters.getCurrentCustomRoleId = 7;
  store.getters.getCurrentUser = {
    accounts: [{ id: 9, custom_role_id: 7, permissions }],
  };
};

const destinoDe = permissions => {
  funcaoSo(permissions);
  return home.redirect({ params: { accountId: 9 } });
};

describe('página inicial de Configurações para a função só com SLA', () => {
  it('leva para CRM › SLA', () => {
    expect(destinoDe(['sla_manage'])).toEqual({
      name: 'crm_sla_index',
      params: { accountId: 9 },
    });
  });

  it('todo destino da página inicial é uma rota registrada', () => {
    const vazio = { render: () => null };
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/', name: 'home', component: vazio },
        ...settingsRoutes.routes,
        ...crmRoutes,
      ],
    });
    const destinos = [
      ['canned_response_manage'],
      ['inbox_view'],
      ['label_manage'],
      ['attribute_manage'],
      ['automation_view'],
      ['macro_manage'],
      ['sla_manage'],
    ].map(permissions => destinoDe(permissions).name);

    destinos.forEach(name => expect(router.hasRoute(name)).toBe(true));
  });

  it('CRM › SLA abre para sla_manage e continua abrindo para crm_admin', () => {
    const sla = crmRoutes.find(route => route.name === 'crm_sla_index');
    expect(sla.meta.permissions).toEqual([
      'administrator',
      'crm_admin',
      'sla_manage',
    ]);
  });
});
