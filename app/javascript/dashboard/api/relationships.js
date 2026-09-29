// Resolve the application client at request time. It owns apiHost and session headers.
// Importing the raw axios package here would bypass the authenticated dashboard client.
const client = () => {
  if (!window.axios)
    throw new Error('Dashboard HTTP client is not initialized');
  return window.axios;
};

export default {
  get: (...args) => client().get(...args),
  patch: (...args) => client().patch(...args),
  post: (...args) => client().post(...args),
};
