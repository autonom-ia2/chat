import { describe, expect, it } from 'vitest';

import {
  MAX_TEST_RECIPIENTS,
  parseTestRecipients,
  testSendAddress,
  testSendErrorMessage,
} from '../emailTestSend';

const BUILDER = 'CAMPAIGN.EMAIL_CAMPAIGN.BUILDER';

describe('emailTestSend', () => {
  it('starts with the logged-in user address', () => {
    expect(testSendAddress({ email: ' gestora@empresa.com.br ' })).toBe(
      'gestora@empresa.com.br'
    );
    expect(testSendAddress(null)).toBe('');
  });

  // #1093: any typed address, up to 5, one per line or separated by comma or space.
  it('reads addresses split by line, comma or space, without repeats', () => {
    expect(
      parseTestRecipients(
        'gestora@empresa.com.br\n socio@outra.com.br, cliente@gmail.com  Socio@Outra.com.br;'
      )
    ).toEqual({
      emails: [
        'gestora@empresa.com.br',
        'socio@outra.com.br',
        'cliente@gmail.com',
      ],
      invalid: [],
      isEmpty: false,
      isTooMany: false,
    });
  });

  it('points out what is not an e-mail, an empty field and more than 5', () => {
    expect(parseTestRecipients('certo@empresa.com.br errado@').invalid).toEqual(
      ['errado@']
    );
    expect(parseTestRecipients('  \n ').isEmpty).toBe(true);
    const six = Array.from(
      { length: MAX_TEST_RECIPIENTS + 1 },
      (_, index) => `pessoa${index}@empresa.com.br`
    ).join('\n');
    expect(MAX_TEST_RECIPIENTS).toBe(5);
    expect(parseTestRecipients(six).isTooMany).toBe(true);
  });

  it('maps each backend refusal to its own message, with the address when there is one', () => {
    const refusal = data => ({ response: { data } });

    expect(
      testSendErrorMessage(
        refusal({
          error: 'email_campaign.test_send_suppressed',
          email: 'saiu@empresa.com.br',
        })
      )
    ).toEqual({
      key: `${BUILDER}.SEND_TEST_SUPPRESSED`,
      params: { email: 'saiu@empresa.com.br' },
    });
    expect(
      testSendErrorMessage(
        refusal({ error: 'email_campaign.invalid_email', email: 'errado@' })
      )
    ).toEqual({
      key: `${BUILDER}.SEND_TEST_INVALID`,
      params: { email: 'errado@' },
    });
    expect(
      testSendErrorMessage(
        refusal({ error: 'email_campaign.test_send_too_many', limit: 5 })
      ).key
    ).toBe(`${BUILDER}.SEND_TEST_TOO_MANY`);
    expect(
      testSendErrorMessage(
        refusal({ error: 'email_campaign.test_send_rate_limited' })
      ).key
    ).toBe(`${BUILDER}.SEND_TEST_RATE_LIMITED`);
    expect(testSendErrorMessage(new Error('network')).key).toBe(
      `${BUILDER}.SEND_TEST_ERROR`
    );
  });
});
