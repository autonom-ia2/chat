import grapesjs from 'grapesjs';
import mjmlPlugin from 'grapesjs-mjml';
import { canonicalizeMjml } from '../mjmlCanonical';
import { prepareMjmlForEditor } from '../editorMjml';
import { UPLOAD_PLACEHOLDER_SRC } from '../sectionMarkup';

// Shape of a draft broken by an image file dropped on the canvas (#2908): a loose <img> whose data:
// address the server cleaner turned into '#', with the photo size as style, and loose text in a column.
const BROKEN =
  '<mjml><mj-body>' +
  '<mj-section background-color="#ffffff"><mj-column>' +
  '<img alt="foto.jpg" src="#" style="width:549px;height:821px;"></img>' +
  '</mj-column></mj-section>' +
  '<mj-section background-color="#ffffff"><mj-column>' +
  '<p>Texto solto</p><mj-text font-size="15px">Oi</mj-text>' +
  '</mj-column></mj-section>' +
  '</mj-body></mjml>';

const ARIAL = 'font-family="Arial, Helvetica, sans-serif"';

const typesIn = (component, acc = []) => {
  acc.push(component.get('type'));
  component.components().forEach(child => typesIn(child, acc));
  return acc;
};

describe('loose content in mj-column on load (#2908)', () => {
  it('turns the loose <img> into an mj-image with the upload frame, no size style', () => {
    const out = canonicalizeMjml(BROKEN);

    expect(out).toContain(
      `<mj-image src="${UPLOAD_PLACEHOLDER_SRC}" alt="foto.jpg"></mj-image>`
    );
    expect(out).not.toContain('<img');
    expect(out).not.toContain('549px');
  });

  it('turns loose text into one mj-text with Arial, before the existing text', () => {
    const out = canonicalizeMjml(BROKEN);

    expect(out).toContain(
      `<mj-column><mj-text ${ARIAL} font-size="15px" color="#1f2937" line-height="1.6"><p>Texto solto</p></mj-text>` +
        '<mj-text font-size="15px">Oi</mj-text></mj-column>'
    );
  });

  it('keeps a public image address', () => {
    const out = canonicalizeMjml(
      '<mj-section><mj-column><img src="https://cdn.exemplo.com.br/a.png" alt="Logo"></img></mj-column></mj-section>'
    );

    expect(out).toBe(
      '<mj-section><mj-column><mj-image src="https://cdn.exemplo.com.br/a.png" alt="Logo"></mj-image></mj-column></mj-section>'
    );
  });

  it('keeps the order of text, image and text runs', () => {
    const out = canonicalizeMjml(
      '<mj-column>Antes<img src="#" alt=""></img><b>Depois</b> fim</mj-column>'
    );

    expect(out).toBe(
      `<mj-column><mj-text ${ARIAL} font-size="15px" color="#1f2937" line-height="1.6">Antes</mj-text>` +
        `<mj-image src="${UPLOAD_PLACEHOLDER_SRC}" alt="Imagem"></mj-image>` +
        `<mj-text ${ARIAL} font-size="15px" color="#1f2937" line-height="1.6"><b>Depois</b> fim</mj-text></mj-column>`
    );
  });

  it('leaves a healthy column untouched: whitespace and comments are not loose text', () => {
    const healthy =
      '<mj-section><mj-column>\n  <!-- topo -->\n  <mj-text>Oi</mj-text>\n</mj-column></mj-section>';

    expect(canonicalizeMjml(healthy)).toBe(healthy);
  });

  it('does not apply head defaults to the repaired loose HTML', () => {
    const out = canonicalizeMjml(
      '<mjml><mj-head><mj-attributes><mj-all font-family="Georgia"></mj-all></mj-attributes></mj-head>' +
        '<mj-body><mj-section><mj-column><p>Solto</p></mj-column></mj-section></mj-body></mjml>'
    );

    expect(out).toContain('<p>Solto</p>');
    expect(out).not.toContain('<p font-family');
  });

  it('loads the repaired draft in GrapesJS with only MJML blocks, and saves it repaired', () => {
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
    editor.setComponents(prepareMjmlForEditor(BROKEN).mjml);
    const body = editor
      .getWrapper()
      .components()
      .at(0)
      .components()
      .find(c => c.get('type') === 'mj-body');
    const types = typesIn(body);
    const saved = editor.runCommand('mjml-code');
    editor.destroy();
    container.remove();

    expect(types).not.toContain('image');
    expect(types).not.toContain('default');
    expect(types.filter(type => type === 'mj-image')).toHaveLength(1);
    expect(types.filter(type => type === 'mj-text')).toHaveLength(2);
    expect(saved).not.toContain('<img');
    expect(saved).toContain(UPLOAD_PLACEHOLDER_SRC.split('?')[0]);
  }, 30000);
});
