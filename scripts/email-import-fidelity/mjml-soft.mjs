// Compiles MJML read from stdin with mjml-browser under SOFT validation, for the original page of
// a model that was MJML already (EmailImportFidelity::Pages): strict validation refuses what the
// import itself takes apart (mj-raw...), and the suite draws the model as its author wrote it.
// Writes the HTML to stdout. Only for the fidelity report — never for what is saved or sent.
import { createRequire } from 'node:module';

globalThis.window = globalThis.window || {};
globalThis.document = globalThis.document || {};

const require = createRequire(import.meta.url);
const mjml2html = require('mjml-browser');

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  input += chunk;
});
process.stdin.on('end', () => {
  process.stdout.write(
    mjml2html(input, { validationLevel: 'soft', minify: false }).html || ''
  );
});
