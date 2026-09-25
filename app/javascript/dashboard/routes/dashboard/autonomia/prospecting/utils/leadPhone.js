// Telefone e WhatsApp do lead: E.164 e links de contato pelo contrato único
// (utils/phoneContract.js). A região é o search_country das configurações
// (phoneRegionFromSettings); sem ela vale o Brasil.
import { DEFAULT_PHONE_REGION, parsePhone } from './phoneContract';

const leadPhoneRaw = lead => lead?.whatsapp_phone || lead?.phone;

export const normalizedLeadPhone = (lead, region = DEFAULT_PHONE_REGION) =>
  parsePhone(leadPhoneRaw(lead), region)?.e164 || '';

export const leadPhoneUrl = (lead, region = DEFAULT_PHONE_REGION) => {
  const phone = normalizedLeadPhone(lead, region);
  return phone ? `tel:${phone}` : '';
};

export const leadWhatsAppUrl = (lead, region = DEFAULT_PHONE_REGION) => {
  const verifiedUrl = lead?.whatsapp_url;
  if (verifiedUrl) return verifiedUrl;

  const digits = parsePhone(leadPhoneRaw(lead), region)?.digits;
  return digits ? `https://wa.me/${digits}` : '';
};

export const isWhatsAppVerified = lead => lead?.whatsapp_verified === true;

export const isWhatsAppUnavailable = lead =>
  lead?.whatsapp_verification_status === 'not_whatsapp';
