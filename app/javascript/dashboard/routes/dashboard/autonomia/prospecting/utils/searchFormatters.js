// Formatação da tela de busca: datas, área da busca, endereço e link do mapa.
// As que exibem texto recebem o `t` do vue-i18n de quem chama.
export const formatShortDate = value => {
  if (!value) return '-';
  return new Date(value).toLocaleDateString();
};

export const formatRelativeTime = (value, t) => {
  if (!value) return '-';

  const diff = Date.now() - new Date(value).getTime();
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);
  if (minutes < 1) return t('PROSPECTING.SEARCH.TIME_NOW');
  if (minutes < 60) {
    return t('PROSPECTING.SEARCH.TIME_MINUTES_AGO', { count: minutes });
  }
  if (hours < 24) {
    return t('PROSPECTING.SEARCH.TIME_HOURS_AGO', { count: hours });
  }
  if (days < 7) return t('PROSPECTING.SEARCH.TIME_DAYS_AGO', { count: days });
  return formatShortDate(value);
};

export const formatRadius = (radius, t) => {
  const kilometers = Number(radius || 0) / 1000;
  return t('PROSPECTING.SEARCH.RADIUS_KM_VALUE', {
    value: Number.isInteger(kilometers) ? kilometers : kilometers.toFixed(1),
  });
};

export const formatSearchArea = (search, t) => {
  if (search?.area_type === 'viewport') {
    return t('PROSPECTING.SEARCH.AREA_VIEWPORT_SHORT');
  }

  return formatRadius(search?.radius || 0, t);
};

export const formatLeadAddress = (lead, t) => {
  const cityState = [lead.city, lead.state].filter(Boolean).join(' ');
  return [lead.address, cityState]
    .filter(Boolean)
    .join(t('PROSPECTING.SEARCH.ADDRESS_SEPARATOR'));
};

export const googleMapsLeadUrl = (lead, t) => {
  const query =
    lead.latitude && lead.longitude
      ? `${lead.latitude},${lead.longitude}`
      : [lead.name, formatLeadAddress(lead, t)].filter(Boolean).join(' ');
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
};
