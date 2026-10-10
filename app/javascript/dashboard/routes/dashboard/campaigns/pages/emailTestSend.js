// "Enviar teste" (#999, #1093): goes to any typed address, up to 5 per test, for who manages
// campaigns. The field starts with the logged-in user's address. These helpers keep the rules
// testable outside the page; the server checks the same rules again (TestSendsController).
import { email as emailRule } from '@vuelidate/validators';

const BUILDER = 'CAMPAIGN.EMAIL_CAMPAIGN.BUILDER';

export const MAX_TEST_RECIPIENTS = 5;

// What separates two addresses in the field: a new line, a comma, a semicolon or a space.
const SEPARATORS = [',', ';', ' ', '\t', '\r'];

const ERROR_KEYS = {
  'email_campaign.test_send_rate_limited': `${BUILDER}.SEND_TEST_RATE_LIMITED`,
  'email_campaign.test_send_too_many': `${BUILDER}.SEND_TEST_TOO_MANY`,
  'email_campaign.test_send_no_recipient': `${BUILDER}.SEND_TEST_EMPTY`,
  'email_campaign.invalid_email': `${BUILDER}.SEND_TEST_INVALID`,
  'email_campaign.test_send_suppressed': `${BUILDER}.SEND_TEST_SUPPRESSED`,
};

export const testSendAddress = currentUser =>
  typeof currentUser?.email === 'string' ? currentUser.email.trim() : '';

const isEmail = value => emailRule.$validator(value);

// Splits the field into addresses (String methods only), without repeats (case-insensitive).
export const parseTestRecipients = text => {
  const parts = SEPARATORS.reduce(
    (pieces, separator) => pieces.flatMap(piece => piece.split(separator)),
    String(text || '').split('\n')
  )
    .map(piece => piece.trim())
    .filter(Boolean);
  const seen = new Set();
  const emails = parts.filter(part => {
    const key = part.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return {
    emails,
    invalid: emails.filter(part => !isEmail(part)),
    isEmpty: emails.length === 0,
    isTooMany: emails.length > MAX_TEST_RECIPIENTS,
  };
};

// The message to show for the field as typed, or null when it can be sent.
export const testRecipientsProblem = ({ invalid, isEmpty, isTooMany }) => {
  if (isEmpty) return { key: `${BUILDER}.SEND_TEST_EMPTY`, params: {} };
  if (isTooMany) return { key: `${BUILDER}.SEND_TEST_TOO_MANY`, params: {} };
  if (invalid.length) {
    return {
      key: `${BUILDER}.SEND_TEST_INVALID`,
      params: { email: invalid[0] },
    };
  }
  return null;
};

export const testSendErrorMessage = error => {
  const data = error?.response?.data || {};
  const key = ERROR_KEYS[data.error] || `${BUILDER}.SEND_TEST_ERROR`;
  return { key, params: data.email ? { email: data.email } : {} };
};
