// A card's company belongs to the opportunity payload. The contact snapshot
// can be shared by several opportunities and must never replace that company.
export const buildCrmCardIdentity = (card, standaloneLabel) => {
  const company = String(card?.company?.name || '').trim();
  const person = String(
    card?.contact?.name || card?.contact?.phone_number || ''
  ).trim();
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
