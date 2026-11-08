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

  it('opens to administrators and to whoever builds roles (#1931)', () => {
    const [parent] = customRoleRoutes.routes;
    parent.children
      .filter(route => route.name)
      .forEach(route =>
        expect(route.meta.permissions).toEqual([
          'administrator',
          'custom_role_manage',
        ])
      );
  });
});
