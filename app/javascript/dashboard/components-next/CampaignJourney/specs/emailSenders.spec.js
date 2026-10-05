import fs from 'node:fs';
import path from 'node:path';
import {
  WEBMAIL_DOMAINS,
  hasUsableEmailSender,
  isDirectSendInbox,
} from '../emailSenders';

// Reads `const WEBMAIL_DOMAINS = [ ... ];` from a source file with plain string methods.
const domainsIn = relativePath => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/javascript/dashboard', relativePath),
    'utf8'
  );
  const start = source.indexOf('const WEBMAIL_DOMAINS = [');
  const body = source.slice(
    source.indexOf('[', start) + 1,
    source.indexOf('];', start)
  );
  return body
    .split(',')
    .map(item => item.trim().split("'").join(''))
    .filter(Boolean);
};

describe('e-mail senders the engine can use', () => {
  it('uses the same webmail list as the e-mail campaign dialog (drift guard)', () => {
    expect(
      domainsIn(
        'components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue'
      )
    ).toEqual(WEBMAIL_DOMAINS);
  });

  it('accepts a verified domain or a webmail inbox, nothing else', () => {
    expect(
      hasUsableEmailSender({ senderIdentities: [{ status: 'verified' }] })
    ).toBe(true);
    expect(
      hasUsableEmailSender({ senderIdentities: [{ status: 'verifying' }] })
    ).toBe(false);
    expect(
      isDirectSendInbox({
        channel_type: 'Channel::Email',
        email: 'loja@hotmail.com.br',
      })
    ).toBe(true);
    expect(
      isDirectSendInbox({
        channel_type: 'Channel::Email',
        email: 'vendas@acme.com.br',
      })
    ).toBe(false);
    expect(
      isDirectSendInbox({ channel_type: 'Channel::Api', email: 'a@gmail.com' })
    ).toBe(false);
  });
});
