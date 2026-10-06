import grapesjs from 'grapesjs';
import mjmlPlugin from 'grapesjs-mjml';
import { canonicalizeMjml } from '../mjmlCanonical';
import aiEmail from './fixtures/aiEmail.mjml?raw';

// Loads the MJML exactly like useEmailEditor (setComponents on a grapesjs-mjml editor) and reads
// back the component tree (what the canvas renders), what it saves (mjml-code) and what it sends
// (mjml-code-to-html). Component#find hangs on this tree under jsdom, so it is walked by hand.
const typesIn = (component, acc = []) => {
  acc.push(component.get('type'));
  component.components().forEach(child => typesIn(child, acc));
  return acc;
};

const firstOfType = (component, type) => {
  if (component.get('type') === type) return component;
  return component
    .components()
    .map(child => firstOfType(child, type))
    .find(Boolean);
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
  const part = type => root.components().find(c => c.get('type') === type);
  const body = part('mj-body');
  const bodyTypes = typesIn(body);
  const result = {
    headTypes: typesIn(part('mj-head'))
      .slice(1)
      .filter(type => type !== 'textnode'),
    bodyImages: bodyTypes.filter(type => type === 'mj-image').length,
    bodyDividers: bodyTypes.filter(type => type === 'mj-divider').length,
    button: firstOfType(body, 'mj-button').getAttributes(),
    text: firstOfType(body, 'mj-text').getAttributes(),
    mjml: editor.runCommand('mjml-code'),
    html: String(editor.runCommand('mjml-code-to-html').html),
  };
  editor.destroy();
  container.remove();
  return result;
};

const count = (text, needle) => text.split(needle).length - 1;

describe('canonical MJML inside GrapesJS + grapesjs-mjml', () => {
  it('reproduces the bug without canonicalization: defaults become head blocks and are lost', () => {
    const raw = loadInEditor(aiEmail);

    expect(raw.headTypes).toContain('mj-button');
    // grapesjs-mjml falls back to its own dark gray (#414141)
    expect(raw.button['background-color']).not.toBe('#4B479B');
    expect(raw.html).not.toContain('line-height:1.6');
  }, 30000);

  it('has no blocks in the head and carries the defaults on each body block', () => {
    const result = loadInEditor(canonicalizeMjml(aiEmail));
    const bodySource = aiEmail.slice(aiEmail.indexOf('<mj-body'));

    expect(result.headTypes).toEqual([]);
    expect(result.button['background-color']).toBe('#4B479B');
    expect(result.text['line-height']).toBe('1.6');
    expect(result.bodyImages).toBe(count(bodySource, '<mj-image'));
    expect(result.bodyDividers).toBe(count(bodySource, '<mj-divider'));
    // 1 logo + 4 social icons: no ghost image from the defaults.
    expect(count(result.html, '<img')).toBe(5);
    expect(result.html).toContain('line-height:1.6');
    expect(result.html).toContain('background:#4B479B');
    expect(result.mjml).not.toContain('mj-attributes');
    expect(canonicalizeMjml(result.mjml)).toBe(result.mjml);
  }, 30000);

  it('recovers the defaults of a corrupted head saved by the old editor', () => {
    const corrupted = loadInEditor(aiEmail).mjml;
    const repaired = loadInEditor(canonicalizeMjml(corrupted));

    expect(repaired.headTypes).toEqual([]);
    expect(repaired.button['background-color']).toBe('#4B479B');
    expect(repaired.html).toContain('line-height:1.6');
  }, 30000);
});
