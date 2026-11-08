export const FACEBOOK_PAGE_SCOPES = [
  'pages_manage_metadata',
  'business_management',
  'pages_messaging',
  'pages_show_list',
  'pages_read_engagement',
];

export const INSTAGRAM_SCOPES = [
  'instagram_basic',
  'instagram_manage_messages',
];

// extraScopes: asked only by the screen that needs them, behind its flag, until
// Meta approves them for everyone (Your posts #2199: read_insights).
export const buildFacebookLoginScopes = ({
  includeInstagramScopes = false,
  extraScopes = [],
} = {}) => {
  const scopes = [...FACEBOOK_PAGE_SCOPES];
  if (includeInstagramScopes) {
    scopes.push(...INSTAGRAM_SCOPES);
  }
  scopes.push(...extraScopes);
  return scopes.join(',');
};
