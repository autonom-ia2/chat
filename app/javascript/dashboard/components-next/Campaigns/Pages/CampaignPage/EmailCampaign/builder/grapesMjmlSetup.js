// How the e-mail editor loads grapesjs-mjml, so the canvas shows what is sent (#1081).
//
// grapesjs-mjml 1.0.8 has two canvas-only paddings:
// 1. coreMjmlModel.init copies every `style-default` prop the element lacks into its attributes.
//    style-default carries per-side paddings (mj-section 20px 0, mj-text/mj-button/mj-image/
//    mj-divider 10px 25px). When the MJML sets the `padding` shorthand, the injected longhands win
//    in the canvas (each view compiles getMjmlAttributes) while the export drops them
//    (getAttrToHTML skips defaults) — the canvas came out up to 50% taller than the sent e-mail.
//    shorthandDefaults drops, per element, the default longhands its own shorthand already decides.
// 2. The `columnsPadding` option pads every column view; MJML never sees it. It is turned off.

const SHORTHANDS = {
  padding: ['padding-top', 'padding-right', 'padding-bottom', 'padding-left'],
};

// style-default minus the longhands of every shorthand the element sets itself.
export const withoutShadowedDefaults = (styleDefault, attributes) => {
  const shadowed = Object.keys(SHORTHANDS)
    .filter(shorthand => shorthand in attributes)
    .flatMap(shorthand => SHORTHANDS[shorthand])
    .filter(longhand => !(longhand in attributes));
  return Object.fromEntries(
    Object.entries(styleDefault).filter(([prop]) => !shadowed.includes(prop))
  );
};

const LONGHANDS = Object.values(SHORTHANDS).flat();

const hasLonghandDefaults = model => {
  const styleDefault = model.prototype.defaults?.['style-default'] || {};
  return LONGHANDS.some(longhand => longhand in styleDefault);
};

// GrapesJS plugin: runs after grapesjs-mjml and extends its types in place.
export const shorthandDefaults = editor => {
  editor.Components.getTypes()
    .filter(({ model }) => hasLonghandDefaults(model))
    .forEach(({ id, model }) => {
      const baseInit = model.prototype.init;
      editor.Components.addType(id, {
        model: {
          init(...args) {
            this.set(
              'style-default',
              withoutShadowedDefaults(
                this.get('style-default') || {},
                this.get('attributes') || {}
              )
            );
            baseInit.apply(this, args);
          },
        },
      });
    });
};

export const mjmlEditorPlugins = mjmlPlugin => [mjmlPlugin, shorthandDefaults];

export const mjmlEditorPluginsOpts = mjmlPlugin => ({
  [mjmlPlugin]: { useCustomTheme: false, blocks: [], columnsPadding: '' },
});
