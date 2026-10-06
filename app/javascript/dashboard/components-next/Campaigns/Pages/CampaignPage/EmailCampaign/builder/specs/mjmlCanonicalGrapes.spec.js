import grapesjs from 'grapesjs';
import mjmlPlugin from 'grapesjs-mjml';
import { canonicalizeMjml } from '../mjmlCanonical';
import aiEmail from './fixtures/aiEmail.mjml?raw';

// Loads the MJML exactly like useEmailEditor (setComponents on a grapesjs-mjml editor) and reads
// back what the editor saves (mjml-code) and sends (mjml-code-to-html).
// Component#find hangs on this tree under jsdom, so the body is walked by hand.
const typesIn = (component, acc = []) => {
  acc.push(component.get('type'));
  component.components().forEach(child => typesIn(child, acc));
  return acc;
};

const loadInEditor = mjml => {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const editor = grapesjs.init({
    container,
    fromElement: false,
    storageManager: false,
    panels: { defaults: [] },
    plugins: [mjmlPlugin],
    pluginsOpts: { [mjmlPlugin]: { useCustomTheme: false, blocks: [] } },
  });
  editor.setComponents(mjml);
  const root = editor.getWrapper().components().at(0);
  const body = root.components().find(c => c.get('type') === 'mj-body');
  const bodyTypes = typesIn(body);
  const saved = editor.runCommand('mjml-code');
  const result = {
    bodyImages: bodyTypes.filter(type => type === 'mj-image').length,
    bodyDividers: bodyTypes.filter(type => type === 'mj-divider').length,
    head: saved.slice(saved.indexOf('<mj-head>'), saved.indexOf('</mj-head>')),
    mjml: saved,
    html: String(editor.runCommand('mjml-code-to-html').html),
  };
  editor.destroy();
  container.remove();
  return result;
};

const count = (text, needle) => text.split(needle).length - 1;
const FLAT_HEAD =
  '<mj-head><mj-attributes><mj-all font-family="Arial, Helvetica, sans-serif"></mj-all>' +
  '<mj-text color="#252432" font-size="16px" line-height="1.6" padding="0"></mj-text>' +
  '<mj-section padding="40px 24px"></mj-section>' +
  '<mj-button background-color="#4B479B" color="#FFFFFF" font-size="16px" font-weight="700" ' +
  'border-radius="8px" inner-padding="14px 36px" padding="24px 0 0"></mj-button>' +
  '<mj-image padding="0"></mj-image>' +
  '<mj-divider border-color="#4B479B" border-width="1px" padding="0"></mj-divider>' +
  '</mj-attributes>';

describe('canonical MJML inside GrapesJS + grapesjs-mjml', () => {
  it('reproduces the bug without canonicalization: nested head, defaults lost', () => {
    const raw = loadInEditor(aiEmail);

    expect(raw.head).not.toBe(FLAT_HEAD);
    expect(raw.head).toContain('line-height="1.6" padding="0"><mj-section');
    expect(raw.html).not.toContain('line-height:1.6');
  }, 30000);

  it('keeps the head flat, the body blocks as in the source and the defaults applied', () => {
    const result = loadInEditor(canonicalizeMjml(aiEmail));
    const bodySource = aiEmail.slice(aiEmail.indexOf('<mj-body'));

    expect(result.head).toBe(FLAT_HEAD);
    expect(result.bodyImages).toBe(count(bodySource, '<mj-image'));
    expect(result.bodyDividers).toBe(count(bodySource, '<mj-divider'));
    // 1 logo + 4 social icons: no ghost image from the defaults.
    expect(count(result.html, '<img')).toBe(5);
    expect(result.html).toContain('line-height:1.6');
    expect(canonicalizeMjml(result.mjml)).toBe(result.mjml);
  }, 30000);

  it('repairs a corrupted head saved by the old editor', () => {
    const corrupted = loadInEditor(aiEmail).mjml;
    const repaired = loadInEditor(canonicalizeMjml(corrupted));

    expect(repaired.head).toBe(FLAT_HEAD);
    expect(repaired.html).toContain('line-height:1.6');
  }, 30000);
});
