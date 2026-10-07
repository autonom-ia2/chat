// Compiles MJML (read from stdin) with the SAME mjml-browser@4.18 that grapesjs-mjml uses in the
// editor, so seeded previews match what the client renders. Validation is STRICT: invalid MJML is
// not compiled. Writes one JSON object to stdout: { "html": "...", "errors": ["..."] } — html is
// empty when validation failed. Exits non-zero only when mjml-browser itself cannot be loaded or
// crashes. Used by EmailCampaigns::MjmlCompiler (compile rake task and the library quality gate).
//
// Usage: node lib/tasks/support/mjml_compile.js < input.mjml

// mjml-browser targets the browser and expects window/document globals.
global.window = global.window || {};
global.document = global.document || {};

function loadMjml() {
  try {
    const path = require.resolve('mjml-browser', {
      paths: [require.resolve('grapesjs-mjml')],
    });
    return require(path);
  } catch (e) {
    return require('mjml-browser');
  }
}

const messages = list =>
  (list || []).map(error => error.formattedMessage || error.message);

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  input += chunk;
});
process.stdin.on('end', () => {
  let mjml2html;
  try {
    mjml2html = loadMjml();
  } catch (e) {
    process.stderr.write(String(e && e.message ? e.message : e));
    process.exit(1);
  }
  try {
    const result = mjml2html(input, {
      validationLevel: 'strict',
      minify: false,
    });
    process.stdout.write(
      JSON.stringify({
        html: result.html || '',
        errors: messages(result.errors),
      })
    );
  } catch (e) {
    if (!Array.isArray(e && e.errors)) {
      process.stderr.write(String(e && e.message ? e.message : e));
      process.exit(1);
    }
    process.stdout.write(
      JSON.stringify({ html: '', errors: messages(e.errors) })
    );
  }
});
