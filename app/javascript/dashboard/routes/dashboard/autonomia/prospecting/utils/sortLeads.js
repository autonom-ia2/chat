// Ordenação local dos leads de uma busca, pela chave escolhida na tela.
const numberValue = (lead, key, fallback = 0) => Number(lead[key] || fallback);

const compareByPriority = (first, second) => {
  const firstPosition = numberValue(
    first,
    'priority_position',
    Number.MAX_SAFE_INTEGER
  );
  const secondPosition = numberValue(
    second,
    'priority_position',
    Number.MAX_SAFE_INTEGER
  );
  if (firstPosition !== secondPosition) {
    return firstPosition - secondPosition;
  }

  return (
    numberValue(second, 'priority_score') - numberValue(first, 'priority_score')
  );
};

const compareBy = (sortKey, first, second) => {
  if (sortKey === 'priority_desc') return compareByPriority(first, second);
  if (sortKey === 'score_desc') {
    return numberValue(second, 'score') - numberValue(first, 'score');
  }
  if (sortKey === 'rating_desc') {
    return numberValue(second, 'rating') - numberValue(first, 'rating');
  }
  if (sortKey === 'reviews_desc') {
    return (
      numberValue(second, 'reviews_count') - numberValue(first, 'reviews_count')
    );
  }
  if (sortKey === 'name_asc') {
    return String(first.name || '').localeCompare(String(second.name || ''));
  }
  if (sortKey === 'created_asc') {
    return (
      new Date(first.created_at).getTime() -
      new Date(second.created_at).getTime()
    );
  }

  return (
    new Date(second.created_at).getTime() - new Date(first.created_at).getTime()
  );
};

export const sortLeads = (leads, sortKey) =>
  [...leads].sort((first, second) => compareBy(sortKey, first, second));
