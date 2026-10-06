// "Enviar teste" goes only to the logged-in user (#999, PRD D8). The editor's address field is
// filled with that address and locked; these helpers keep the rule testable outside the page.
const BUILDER = 'CAMPAIGN.EMAIL_CAMPAIGN.BUILDER';

const ERROR_KEYS = {
  'email_campaign.test_send_only_self': `${BUILDER}.SEND_TEST_ONLY_SELF`,
  'email_campaign.test_send_rate_limited': `${BUILDER}.SEND_TEST_RATE_LIMITED`,
};

export const testSendAddress = currentUser =>
  typeof currentUser?.email === 'string' ? currentUser.email.trim() : '';

export const testSendErrorKey = error =>
  ERROR_KEYS[error?.response?.data?.error] || `${BUILDER}.SEND_TEST_ERROR`;
