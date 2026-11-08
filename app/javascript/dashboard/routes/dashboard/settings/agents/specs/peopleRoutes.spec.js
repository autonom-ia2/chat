import agentRoutes from '../agent.routes';
import teamsRoutes from '../../teams/teams.routes';

const namedRoutes = routes =>
  routes.flatMap(route => [
    ...(route.name ? [route] : []),
    ...namedRoutes(route.children || []),
  ]);

describe('rotas de Pessoas (#1931)', () => {
  it('abre agentes e todos os passos de times para quem tem people_manage', () => {
    const routes = namedRoutes([...agentRoutes.routes, ...teamsRoutes.routes]);

    expect(routes.map(route => route.name)).toEqual(
      expect.arrayContaining(['agent_list', 'settings_teams_list'])
    );
    routes.forEach(route =>
      expect(route.meta.permissions).toEqual(['administrator', 'people_manage'])
    );
  });
});
