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
// placeholders): a dashed outline and a fixed tag that says what it is ("Ficou como imagem").
// Links do not open: a click would take the preview frame to another site. Only CSS goes in: the
// preview runs in an iframe with sandbox="".
const MARK = '#D97706';

// A text as a CSS string, so a translated tag can never close the rule or the <style>.
export const cssString = text =>
  `"${String(text)
    .split('\\')
    .join('\\\\')
    .split('"')
    .join('\\"')
    .split('<')
    .join('\\3c ')
    .split('\n')
    .join(' ')}"`;

const tagRule = (selector, label) =>
  label
    ? `${selector}{position:relative}${selector}::before{content:${cssString(label)};position:absolute;left:10px;top:10px;z-index:2;` +
      `padding:3px 9px;border-radius:999px;background:${MARK};color:#ffffff;font:600 12px/1.4 Arial,Helvetica,sans-serif}`
    : '';

export const importMarkStyle = (labels = {}) =>
  '<style>a{pointer-events:none;cursor:default}' +
  `.import-unresolved,.import-missing,.import-missing-background{outline:3px dashed ${MARK};outline-offset:-3px}` +
  tagRule('.import-unresolved', labels.unresolved) +
  tagRule('.import-missing', labels.missing) +
  '</style>';

export const withImportMarks = (html, labels = {}) => {
  if (!html) return '';
  const style = importMarkStyle(labels);
  const head = html.indexOf('</head>');
  return head === -1
    ? `${style}${html}`
    : `${html.slice(0, head)}${style}${html.slice(head)}`;
};
