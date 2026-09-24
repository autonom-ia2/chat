// Telefone e WhatsApp do lead: normalização para E.164 e links de contato.
export const normalizedLeadPhone = lead => {
  const raw = String(lead?.whatsapp_phone || lead?.phone || '').trim();
  const digits = raw.replace(/\D/g, '');
  if (!digits) return '';
  if (raw.startsWith('+')) return `+${digits}`;
  if (digits.startsWith('55')) return `+${digits}`;
  if ([10, 11].includes(digits.length)) return `+55${digits}`;
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
