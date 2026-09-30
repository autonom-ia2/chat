const SIZE_BASE = 1024;
const SIZE_UNITS = ['KB', 'MB', 'GB', 'TB'];

export const mediaTypeKey = row => {
  if (row.content_type === 'application/pdf') return 'PDF';
  return ['image', 'audio', 'video'].includes(row.file_type)
    ? row.file_type
    : 'file';
};

export const formatMediaSize = (bytes, locale) => {
  const unit = Math.min(
    Math.max(Math.floor(Math.log(bytes || 1) / Math.log(SIZE_BASE)) - 1, 0),
    SIZE_UNITS.length - 1
  );
  const size = bytes / SIZE_BASE ** (unit + 1);
  return `${new Intl.NumberFormat(locale?.replaceAll('_', '-'), {
    maximumFractionDigits: size < 1 ? 3 : 1,
    minimumFractionDigits: size > 0 && size < 1 ? 1 : 0,
  }).format(size)} ${SIZE_UNITS[unit]}`;
};

// Display timestamps in the browser's local zone. Date filters are interpreted
// by the server in account.reporting_timezone (UTC when unset), separately.
export const formatMediaDate = (timestamp, locale) =>
  new Intl.DateTimeFormat(locale?.replaceAll('_', '-'), {
    calendar: 'gregory',
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(timestamp));

// Only mark boundaries in the server's ordered page; never regroup or dedupe it.
export const mediaContactGroups = (rows, grouped) => {
  const groups = [];
  rows.forEach(row => {
    const previous = groups[groups.length - 1];
    if (!previous || (grouped && previous.contact.id !== row.contact.id)) {
      groups.push({ key: row.id, contact: row.contact, rows: [row] });
    } else previous.rows.push(row);
  });
  return groups;
};
