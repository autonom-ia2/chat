import customRoleRoutes from '../customRole.routes';

describe('customRole routes', () => {
  it('does not cache the editor, so it never reopens with stale data', () => {
    const [parent] = customRoleRoutes.routes;

    expect(parent.props).toEqual({ keepAlive: false });
    expect(parent.children.map(route => route.name).filter(Boolean)).toEqual([
      'custom_roles_list',
      'custom_roles_new',
      'custom_roles_edit',
    ]);
  });
});
