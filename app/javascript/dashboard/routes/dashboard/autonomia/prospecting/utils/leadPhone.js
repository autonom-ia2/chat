// Telefone e WhatsApp do lead: normalização para E.164 e links de contato.
// Dono: frente de telefone. A regra de DDI vem de um "phoneRegion"; a frente de
// país só entrega a região da busca, sem editar esta função.

// Brasil: DDI 55 e número nacional de 10 (fixo) ou 11 (celular) dígitos.
export const BRAZIL_PHONE_REGION = Object.freeze({
  dialCode: '55',
  nationalLengths: Object.freeze([10, 11]),
});

export const normalizedLeadPhone = (lead, region = BRAZIL_PHONE_REGION) => {
  const raw = String(lead?.whatsapp_phone || lead?.phone || '').trim();
  const digits = raw.replace(/\D/g, '');
  if (!digits) return '';
  if (raw.startsWith('+')) return `+${digits}`;
  if (digits.startsWith(region.dialCode)) return `+${digits}`;
  if (region.nationalLengths.includes(digits.length)) {
    return `+${region.dialCode}${digits}`;
  }
  return `+${digits}`;
};

export const leadPhoneUrl = lead => {
  const phone = normalizedLeadPhone(lead);
  return phone ? `tel:${phone}` : '';
};

export const leadWhatsAppUrl = lead => {
  const verifiedUrl = lead?.whatsapp_url;
  if (verifiedUrl) return verifiedUrl;

  const phone = normalizedLeadPhone(lead);
  return phone ? `https://wa.me/${phone.replace(/\D/g, '')}` : '';
};

export const isWhatsAppVerified = lead => lead?.whatsapp_verified === true;

export const isWhatsAppUnavailable = lead =>
  lead?.whatsapp_verification_status === 'not_whatsapp';
