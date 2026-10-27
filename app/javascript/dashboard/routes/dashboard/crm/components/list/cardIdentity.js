import { nomeDoContatoNaTela } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

// A card's company belongs to the opportunity payload. The contact snapshot
// can be shared by several opportunities and must never replace that company.
export const buildCrmCardIdentity = (card, standaloneLabel) => {
  const company = String(card?.company?.name || '').trim();
  // Nome que é só telefone sai legível ("+55 11 95555-4444"); sem nome, o telefone legível (#2255).
  const person = nomeDoContatoNaTela(card?.contact).trim();
  const title = String(card?.title || '').trim();
  const main = company || person || title || standaloneLabel;
  const secondaryPerson = company && person && company !== person ? person : '';
  const business =
    title &&
    ![main, secondaryPerson].includes(title) &&
    title !== String(card?.contact?.phone_number || '').trim()
      ? title
      : '';

  return { company, person: secondaryPerson, business, main };
};

export const crmCardIdentityLabel = (card, standaloneLabel) => {
  const identity = buildCrmCardIdentity(card, standaloneLabel);
  return identity.business
    ? `${identity.main} ${identity.business}`
    : identity.main;
};
