// Datas do formulário de reunião (dia no formato do campo de data, sempre no
// fuso de quem usa). A janela do calendário e o formulário do Google/Microsoft
// usam as mesmas regras.
export const pad = value => String(value).padStart(2, '0');

export const toDate = value => {
  if (value instanceof Date) return new Date(value.getTime());

  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [year, month, day] = value.split('-').map(Number);
    return new Date(year, month - 1, day);
  }

  const date = value ? new Date(value) : new Date();
  return Number.isNaN(date.getTime()) ? new Date() : date;
};

export const toDateInput = value => {
  const date = toDate(value);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(
    date.getDate()
  )}`;
};

export const parseDateInput = value => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '')) return null;

  const [year, month, day] = value.split('-').map(Number);
  return new Date(year, month - 1, day);
};

// ISO 8601 com o deslocamento do fuso de quem marca (ex.: -03:00).
export const toIso8601WithOffset = date => {
  const offset = -date.getTimezoneOffset();
  const sign = offset >= 0 ? '+' : '-';
  const absOffset = Math.abs(offset);

  return [
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`,
    `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(
      date.getSeconds()
    )}`,
    `${sign}${pad(Math.floor(absOffset / 60))}:${pad(absOffset % 60)}`,
  ].join('');
};
