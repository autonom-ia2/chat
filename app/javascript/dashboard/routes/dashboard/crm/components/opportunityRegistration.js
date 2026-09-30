export const newRegistrationDraft = () => ({
  name: '',
  email: '',
  phoneNumber: '',
  jobTitle: '',
  city: '',
  country: '',
  address: '',
  companyMode: 'none',
  company: null,
  companyName: '',
  companyDomain: '',
  companyCity: '',
  contactAttributes: {},
  companyAttributes: {},
});

export function companyDomain(value) {
  const input = value.trim();
  if (!input) return '';
  try {
    const url = new URL(input.includes('://') ? input : `https://${input}`);
    if (
      !['http:', 'https:'].includes(url.protocol) ||
      url.username ||
      url.password
    )
      return '';
    return url.hostname.toLowerCase().endsWith('.')
      ? url.hostname.slice(0, -1)
      : url.hostname.toLowerCase();
  } catch {
    return '';
  }
}

const nonempty = values =>
  Object.fromEntries(
    Object.entries(values).filter(
      ([, value]) => value !== '' && value !== null && value !== undefined
    )
  );

export function registrationPayload(draft) {
  const contact = {
    name: draft.name.trim(),
    ...nonempty({ email: draft.email.trim(), phone_number: draft.phoneNumber }),
    additional_attributes: nonempty({
      city: draft.city.trim(),
      country: draft.country,
    }),
    custom_attributes: {
      ...nonempty({
        job_title: draft.jobTitle.trim(),
        address: draft.address.trim(),
      }),
      ...nonempty(draft.contactAttributes),
    },
  };
  let company = { mode: 'none' };
  if (draft.companyMode === 'existing')
    company = { mode: 'existing', id: draft.company.id };
  if (draft.companyMode === 'new')
    company = {
      mode: 'new',
      attributes: {
        name: draft.companyName.trim(),
        ...nonempty({ domain: draft.companyDomain.trim() }),
        additional_attributes: nonempty({ city: draft.companyCity.trim() }),
        custom_attributes: nonempty(draft.companyAttributes),
      },
    };
  return { mode: 'new', contact, company };
}
