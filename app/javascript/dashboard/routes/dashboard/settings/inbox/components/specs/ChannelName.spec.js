import { mount } from '@vue/test-utils';
import ChannelName from '../ChannelName.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ 'globalConfig/get': { value: {} } }),
}));

const nomeDoCanal = props => mount(ChannelName, { props }).text();

describe('ChannelName (#2255)', () => {
  it('a caixa API ligada ao WAHA é o WhatsApp do celular', () => {
    expect(
      nomeDoCanal({ channelType: 'Channel::Api', wahaProvider: true })
    ).toBe('INBOX_MGMT.CHANNELS.WHATSAPP_CELULAR');
  });

  it('caixa API comum continua "Canal da API"', () => {
    expect(nomeDoCanal({ channelType: 'Channel::Api' })).toBe(
      'INBOX_MGMT.CHANNELS.API'
    );
  });

  it('waha_provider em outro tipo de caixa não muda o nome', () => {
    expect(
      nomeDoCanal({ channelType: 'Channel::Whatsapp', wahaProvider: true })
    ).toBe('INBOX_MGMT.CHANNELS.WHATSAPP');
  });
});
