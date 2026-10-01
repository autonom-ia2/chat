// Compiles MJML (read from stdin) to HTML (written to stdout) using the SAME
// mjml-browser@4.18 that grapesjs-mjml uses in the editor, so seeded previews match
// what the client renders. Exits non-zero (and prints nothing useful) if mjml-browser
// cannot be resolved. Compile the sanitized catalog before publishing its assets.
//
// Usage: node lib/tasks/support/mjml_compile.js < input.mjml > output.html

// mjml-browser targets the browser and expects window/document globals.
global.window = global.window || {};
global.document = global.document || {};

function loadMjml() {
  try {
    const path = require.resolve('mjml-browser', { paths: [require.resolve('grapesjs-mjml')] });
    return require(path);
  } catch (e) {
    return require('mjml-browser');
  }
}

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const mjml2html = loadMjml();
    const { html } = mjml2html(input, { validationLevel: 'soft', minify: false });
    process.stdout.write(html || '');
  } catch (e) {
    process.stderr.write(String(e && e.message ? e.message : e));
    process.exit(1);
  }
});
