// Calendar dates retain their written day, including historical ISO timestamps.
export function attributeDate(value) {
  if (typeof value !== 'string') return '';
  const day = value.split('T')[0];
  const parts = day.split('-');
  if (
    parts.length !== 3 ||
    parts.map(part => part.length).join(',') !== '4,2,2'
  )
    return '';
  if (
    !parts.every(part => [...part].every(char => '0123456789'.includes(char)))
  )
    return '';
  const [year, month, date] = parts.map(Number);
  const parsed = new Date(0);
  parsed.setUTCFullYear(year, month - 1, date);
  return parsed.getUTCFullYear() === year &&
    parsed.getUTCMonth() === month - 1 &&
    parsed.getUTCDate() === date
    ? day
    : '';
}

export function formatAttributeDate(value) {
  const day = attributeDate(value);
  if (!day) return '';
  const [year, month, date] = day.split('-').map(Number);
  const local = new Date(0);
  local.setFullYear(year, month - 1, date);
  local.setHours(12, 0, 0, 0);
  return local.toLocaleDateString();
}
