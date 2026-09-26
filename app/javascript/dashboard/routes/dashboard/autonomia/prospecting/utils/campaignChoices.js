// Campanhas que recebem o segmento da Prospecção pela etiqueta (#732, item 11;
// ACAO-X09): primeiro as da API do WhatsApp que ainda não começaram (o público
// delas é lido quando começam), depois as de envio único ativas. O valor da
// escolha leva o tipo, porque os ids das duas tabelas se repetem.
import CampaignsAPI from 'dashboard/api/campaigns';
import WhatsappApiCampaignsAPI from 'dashboard/api/whatsappApiCampaigns';

export const WHATSAPP_API = 'whatsapp_api';
export const ONE_OFF = 'one_off';
const SEPARATOR = ':';
const NOT_FOUND = 404;

export const campaignChoiceValue = (type, id) => `${type}${SEPARATOR}${id}`;

// Sem campanha: só o segmento. O tipo fica de fora para o servidor.
export const parseCampaignChoice = value => {
  if (!value) return { campaignId: '', campaignType: undefined };
  const [campaignType, campaignId] = String(value).split(SEPARATOR);
  return { campaignId: Number(campaignId), campaignType };
};

// A campanha já gravada no segmento da lista. Segmento de antes do #732 não tem
// tipo e é de envio único.
export const savedCampaignChoice = segment =>
  segment?.campaign_id
    ? campaignChoiceValue(segment.campaign_type || ONE_OFF, segment.campaign_id)
    : '';

export const campaignChoices = ({
  campaigns = [],
  whatsappApiCampaigns = [],
  t,
}) => [
  ...whatsappApiCampaigns
    .filter(campaign => campaign.status === 'scheduled')
    .map(campaign => ({
      value: campaignChoiceValue(WHATSAPP_API, campaign.id),
      label: t('PROSPECTING.CAMPAIGN_SELECTION.CHOICE_WHATSAPP_API', {
        title: campaign.title,
      }),
    })),
  ...campaigns
    .filter(
      campaign =>
        campaign.campaign_type === ONE_OFF &&
        campaign.campaign_status === 'active'
    )
    .map(campaign => ({
      value: campaignChoiceValue(ONE_OFF, campaign.id),
      label: t('PROSPECTING.CAMPAIGN_SELECTION.CHOICE_ONE_OFF', {
        title: campaign.title,
      }),
    })),
];

// A campanha da API do WhatsApp desligada na instalação responde 404: não é
// falha, só não há campanha desse tipo para oferecer.
const loadWhatsappApiCampaigns = async () => {
  try {
    const { data } = await WhatsappApiCampaignsAPI.get();
    return { list: data?.payload || [], failed: false };
  } catch (error) {
    return { list: [], failed: error?.response?.status !== NOT_FOUND };
  }
};

const loadOneOffCampaigns = async () => {
  try {
    const { data } = await CampaignsAPI.get();
    return { list: data || [], failed: false };
  } catch {
    return { list: [], failed: true };
  }
};

export const loadCampaigns = async () => {
  const [oneOff, whatsappApi] = await Promise.all([
    loadOneOffCampaigns(),
    loadWhatsappApiCampaigns(),
  ]);
  return {
    campaigns: oneOff.list,
    whatsappApiCampaigns: whatsappApi.list,
    failed: oneOff.failed || whatsappApi.failed,
  };
};
