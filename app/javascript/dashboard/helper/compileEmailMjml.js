// Compiles e-mail MJML to HTML in the browser with mjml-browser, the same compiler the e-mail
// editor runs (grapesjs-mjml). Loaded on first use, so screens that never preview MJML do not pay
// for it. Never throws: a design that does not compile gives '' and the screen shows no preview.
let compilerPromise = null;

const compiler = () => {
  compilerPromise ||= import('mjml-browser').then(module => module.default);
  return compilerPromise;
};

export const compileEmailMjml = async mjml => {
  if (typeof mjml !== 'string' || !mjml.trim()) return '';
  try {
    const mjml2html = await compiler();
    return mjml2html(mjml, { validationLevel: 'soft' }).html || '';
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn('[compileEmailMjml] could not compile the design', error);
    return '';
  }
};

// Marks, inside a compiled preview, what the person still has to solve (css-class of the import
// placeholders). Only CSS goes in: the preview runs in an iframe with sandbox="".
export const IMPORT_MARK_STYLE =
  '<style>.import-unresolved,.import-missing,.import-missing-background{outline:3px dashed #F59E0B;outline-offset:-3px}</style>';

export const withImportMarks = html => {
  if (!html) return '';
  const head = html.indexOf('</head>');
  return head === -1
    ? `${IMPORT_MARK_STYLE}${html}`
    : `${html.slice(0, head)}${IMPORT_MARK_STYLE}${html.slice(head)}`;
};
