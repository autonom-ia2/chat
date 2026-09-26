// Escolha da campanha na Prospecção (#732, item 11): os dois tipos, com a da
// WhatsApp Oficial (envio único) primeiro, decisão do Rodrigo de 26/09, e o
// valor da escolha levando o tipo.
import CampaignsAPI from 'dashboard/api/campaigns';
import WhatsappApiCampaignsAPI from 'dashboard/api/whatsappApiCampaigns';
import {
  campaignChoices,
  loadCampaigns,
  parseCampaignChoice,
  savedCampaignChoice,
} from '../../utils/campaignChoices';

vi.mock('dashboard/api/campaigns', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/whatsappApiCampaigns', () => ({
  default: { get: vi.fn() },
}));

const t = (key, { title }) => `${key.split('.').pop()} ${title}`;

describe('campaignChoices', () => {
  afterEach(() => vi.clearAllMocks());

  it('põe o envio único ativo (WhatsApp Oficial) antes da API do WhatsApp agendada, e só essas', () => {
    const choices = campaignChoices({
      t,
      campaigns: [
        {
          id: 3,
          title: 'Único',
          campaign_type: 'one_off',
          campaign_status: 'active',
        },
        {
          id: 4,
          title: 'Contínua',
          campaign_type: 'ongoing',
          campaign_status: 'active',
        },
      ],
      whatsappApiCampaigns: [
        { id: 3, title: 'API', status: 'scheduled' },
        { id: 5, title: 'Pausada', status: 'paused' },
      ],
    });

    expect(choices).toEqual([
      { value: 'one_off:3', label: 'CHOICE_ONE_OFF Único' },
      { value: 'whatsapp_api:3', label: 'CHOICE_WHATSAPP_API API' },
    ]);
  });

  it('lê a escolha de volta com id numérico e tipo, e sem campanha não manda tipo', () => {
    expect(parseCampaignChoice('whatsapp_api:3')).toEqual({
      campaignId: 3,
      campaignType: 'whatsapp_api',
    });
    expect(parseCampaignChoice('')).toEqual({
      campaignId: '',
      campaignType: undefined,
    });
  });

  it('segmento gravado antes do #732, sem tipo, volta como envio único', () => {
    expect(savedCampaignChoice({ campaign_id: 7 })).toBe('one_off:7');
    expect(
      savedCampaignChoice({ campaign_id: 7, campaign_type: 'whatsapp_api' })
    ).toBe('whatsapp_api:7');
    expect(savedCampaignChoice(null)).toBe('');
  });

  it('a API do WhatsApp desligada (404) não conta como falha; outra falha conta', async () => {
    CampaignsAPI.get.mockResolvedValue({ data: [{ id: 1 }] });
    WhatsappApiCampaignsAPI.get.mockRejectedValue({
      response: { status: 404 },
    });

    expect(await loadCampaigns()).toEqual({
      campaigns: [{ id: 1 }],
      whatsappApiCampaigns: [],
      failed: false,
    });

    WhatsappApiCampaignsAPI.get.mockRejectedValue({
      response: { status: 500 },
    });
    expect((await loadCampaigns()).failed).toBe(true);
  });
});
