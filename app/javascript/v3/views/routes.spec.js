import routes from './routes';

describe('authentication routes', () => {
  const ssoLoginRoute = routes.find(route => route.name === 'sso_login');

  // Fork (upgrade 4.19.1, #3119): the login route and view stay the fork's; the upstream Shopify redirect tests were removed.
  it('passes the login redirect into SAML sign-in', () => {
    const props = ssoLoginRoute.props({
      query: {
        redirect_url:
          'settings/billing?plan_handle=growth&shop=store.myshopify.com',
      },
    });

    expect(props.redirectUrl).toBe(
      'settings/billing?plan_handle=growth&shop=store.myshopify.com'
    );
  });
});
