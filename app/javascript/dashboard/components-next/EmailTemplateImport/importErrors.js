// What each code of "Trazer meu modelo" (#1099) shows: one sentence and one way out. Codes come from
// EmailCampaigns::Import::Error (and the controller), always as "email_template_import.<code>".
export const ERROR_PREFIX = 'email_template_import.';

// Problems with what the person typed: shown under the field, on the same screen, with what
// they typed still there (the address that did not open comes back from the job).
const INLINE = [
  'url_invalid',
  'url_not_https',
  'url_unsafe',
  'url_unreachable',
  'empty',
];
const SOURCES = ['file', 'paste', 'url'];
const NOT_EMAIL = [
  'unsupported_file',
  'zip_no_html',
  'zip_invalid',
  'zip_unsafe_path',
  'url_not_html',
  'malformed_mjml',
];
const TOO_BIG = [
  'too_large',
  'zip_too_large',
  'zip_too_many_files',
  'too_many_nodes',
  'too_deep',
];
const FAILED = ['too_slow', 'stalled', 'internal'];

export const MAX_PASTE_BYTES = 500 * 1024;
export const MAX_HTML_BYTES = 500 * 1024;
export const MAX_ZIP_BYTES = 2 * 1024 * 1024;
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

export const errorCode = error => {
  const raw = error?.response?.data?.error || '';
  return raw.startsWith(ERROR_PREFIX) ? raw.slice(ERROR_PREFIX.length) : '';
};

// -> { kind: 'inline' | 'not_email' | 'too_big' | 'failed' | 'other', code }
export const classifyError = code => {
  if (INLINE.includes(code)) return { kind: 'inline', code };
  if (NOT_EMAIL.includes(code)) return { kind: 'not_email', code };
  if (TOO_BIG.includes(code)) return { kind: 'too_big', code };
  if (FAILED.includes(code) || !code) return { kind: 'failed', code };
  return { kind: 'other', code };
};

// How the model came in, so an error speaks of a file, a pasted code or an address.
export const sourceOf = kind => (SOURCES.includes(kind) ? kind : 'file');

const extensionOf = name => {
  const dot = name.lastIndexOf('.');
  return dot === -1 ? '' : name.slice(dot + 1).toLowerCase();
};

// Checked before sending; the server checks the bytes again. -> error code or ''.
export const fileProblem = file => {
  const extension = extensionOf(file?.name || '');
  if (extension === 'zip')
    return file.size > MAX_ZIP_BYTES ? 'zip_too_large' : '';
  if (extension === 'html' || extension === 'htm') {
    return file.size > MAX_HTML_BYTES ? 'too_large' : '';
  }
  return 'unsupported_file';
};

export const pasteProblem = content => {
  if (!content.trim()) return 'empty';
  return new Blob([content]).size > MAX_PASTE_BYTES ? 'too_large' : '';
};

export const sizeLabel = bytes => {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1).replace('.0', '')} MB`;
};
