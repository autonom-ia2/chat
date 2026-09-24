// País da busca no Google (#677). A lista de países aceitos vem do backend
// (settings.search_countries); aqui só o agrupamento por continente, como no
// Orth (SearchCountryConfig.tsx), em ordem do nome. País novo que ainda não esteja num grupo cai
// em "Outros" em vez de sumir.
export const DEFAULT_SEARCH_COUNTRY = 'BR';

const COUNTRY_GROUPS = [
  {
    key: 'SOUTH_AMERICA',
    countries: ['BR', 'AR', 'CL', 'CO', 'EC', 'PY', 'PE', 'UY'],
  },
  { key: 'NORTH_AMERICA', countries: ['US', 'MX'] },
  {
    key: 'EUROPE',
    countries: ['PT', 'ES', 'FR', 'DE', 'IT', 'GB', 'AT', 'IE'],
  },
  { key: 'ASIA', countries: ['IN'] },
];

const GROUPED = new Set(COUNTRY_GROUPS.flatMap(group => group.countries));

export const searchCountryGroups = (allowed, t) => {
  const option = code => ({
    value: code,
    label: t(`PROSPECTING.SEARCH_COUNTRY.COUNTRIES.${code}`),
  });
  const group = (key, countries) => ({
    label: t(`PROSPECTING.SEARCH_COUNTRY.GROUPS.${key}`),
    options: countries
      .map(option)
      .sort((a, b) => a.label.localeCompare(b.label)),
  });

  return [
    ...COUNTRY_GROUPS.map(({ key, countries }) =>
      group(
        key,
        countries.filter(code => allowed.includes(code))
      )
    ),
    group(
      'OTHER',
      allowed.filter(code => !GROUPED.has(code))
    ),
  ].filter(item => item.options.length);
};
