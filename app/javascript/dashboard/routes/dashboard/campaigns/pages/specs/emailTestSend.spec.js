import { describe, expect, it } from 'vitest';

import { testSendAddress, testSendErrorKey } from '../emailTestSend';

describe('emailTestSend', () => {
  it('uses the logged-in user address', () => {
    expect(testSendAddress({ email: ' gestora@empresa.com.br ' })).toBe(
      'gestora@empresa.com.br'
    );
    expect(testSendAddress(null)).toBe('');
  });

  it('maps the backend refusals to their own messages', () => {
    const refusal = code => ({ response: { data: { error: code } } });

    expect(
      testSendErrorKey(refusal('email_campaign.test_send_only_self'))
    ).toBe('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST_ONLY_SELF');
    expect(
      testSendErrorKey(refusal('email_campaign.test_send_rate_limited'))
    ).toBe('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST_RATE_LIMITED');
    expect(testSendErrorKey(new Error('network'))).toBe(
      'CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SEND_TEST_ERROR'
    );
  });
});
