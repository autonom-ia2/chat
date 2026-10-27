import { getInboxIconByType } from 'dashboard/helper/inbox';
import { iconeDaCaixa } from '../iconeDaCaixa';

describe('iconeDaCaixa (#2202)', () => {
  it('WhatsApp pelo celular (API do WAHA) leva o ícone do WhatsApp; a API comum, o dela', () => {
    const whatsapp = iconeDaCaixa({ channelType: 'Channel::Whatsapp' });
    expect(
      iconeDaCaixa({ channelType: 'Channel::Api', wahaProvider: true })
    ).toBe(whatsapp);
    expect(
      iconeDaCaixa({ channel_type: 'Channel::Api', waha_provider: true })
    ).toBe(whatsapp);
    expect(iconeDaCaixa({ channel_type: 'Channel::Api' })).not.toBe(whatsapp);
  });

  it('as outras caixas: o mesmo ícone de sempre', () => {
    const email = { channel_type: 'Channel::Email', medium: '' };
    expect(iconeDaCaixa(email)).toBe(
      getInboxIconByType('Channel::Email', '', 'line')
    );
  });

  it('sem caixa, sem ícone', () => {
    expect(iconeDaCaixa(null)).toBe('');
  });
});
