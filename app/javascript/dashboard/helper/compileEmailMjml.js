// Compiles e-mail MJML to HTML with the e-mail editor's own compiler: GrapesJS + grapesjs-mjml with
// the editor's plugins (grapesMjmlSetup) and its load/export path (editorMjml), in headless mode.
// The preview then shows what the editor will send, and the dashboard ships ONE MJML compiler — the
// copy inside grapesjs-mjml — instead of a second mjml-browser (#1118). GrapesJS loads on first use
// and the headless editor is kept for the next preview; disposeEmailMjmlCompiler frees it when the
// screen leaves. Never throws: a design that does not compile gives '' and the screen shows no preview.
import {
  prepareMjmlForEditor,
  restoreHeldHead,
} from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/editorMjml';
import {
  mjmlEditorPlugins,
  mjmlEditorPluginsOpts,
} from 'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/grapesMjmlSetup';

let compilerPromise = null;

const createCompiler = async () => {
  const [{ default: grapesjs }, { default: mjmlPlugin }] = await Promise.all([
    import('grapesjs'),
    import('grapesjs-mjml'),
  ]);
  return grapesjs.init({
    headless: true,
    storageManager: false,
    plugins: mjmlEditorPlugins(mjmlPlugin),
    pluginsOpts: mjmlEditorPluginsOpts(mjmlPlugin),
  });
};

const compiler = () => {
  compilerPromise ||= createCompiler().catch(error => {
    compilerPromise = null;
    throw error;
  });
  return compilerPromise;
};

// The editor's path, synchronous end to end, so two previews never interleave on the shared editor:
// load (prepareMjmlForEditor + setComponents), export (mjml-code + restoreHeldHead), compile.
const compileInEditor = (editor, mjml) => {
  const prepared = prepareMjmlForEditor(mjml);
  editor.setComponents(prepared.mjml);
  const exported = restoreHeldHead(
    editor.runCommand('mjml-code') || '',
    prepared.held
  );
  const out = editor.runCommand('mjml-code-to-html', { mjml: exported }) || {};
  editor.setComponents('');
  return out.html || '';
};

export const compileEmailMjml = async mjml => {
  if (typeof mjml !== 'string' || !mjml.trim()) return '';
  try {
    return compileInEditor(await compiler(), mjml);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn('[compileEmailMjml] could not compile the design', error);
    return '';
  }
};

export const disposeEmailMjmlCompiler = async () => {
  const pending = compilerPromise;
  compilerPromise = null;
  if (!pending) return;
  try {
    (await pending).destroy();
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn('[compileEmailMjml] could not dispose the compiler', error);
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
