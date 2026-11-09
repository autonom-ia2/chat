import { parsePhoneNumberFromString } from 'libphonenumber-js';

// Telefone como a pessoa fala (#2213): "(11) 98765-1201" no Brasil, "+1 415 555 2671" fora dele. Um formato só
// no card do CRM, na agenda e nos Anúncios da Meta; quem lê o número é a libphonenumber-js. Sem número, vazio; o
// que ela não reconhece (inclusive sem o "+" do país) aparece como veio.
export const telefoneParaLer = telefone => {
  if (!telefone) return '';
  const numero = parsePhoneNumberFromString(String(telefone));
  if (!numero) return String(telefone);
  return numero.country === 'BR'
    ? numero.formatNational()
    : numero.formatInternational();
};
