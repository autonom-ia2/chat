// Gera PRD.html (página única, sem dependência de JavaScript para navegar nas jornadas).
// A navegação usa botões de opção (radio) + CSS. O script no fim só abre a etapa do endereço (#jornada-N-M).
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const { default: J } = await import('./src/journeys.mjs');
const template = readFileSync(join(root, 'src/PRD.src.html'), 'utf8');

const css = [];
const html = [];

html.push('<div class="jwrap">');
J.forEach((j, ji) => {
  html.push(`<input class="rj" type="radio" name="j" id="j${j.id}" ${ji === 0 ? 'checked' : ''} aria-label="Jornada ${j.id}">`);
  css.push(`#j${j.id}:checked ~ .jmain #p${j.id}{display:block}`);
  css.push(`#j${j.id}:checked ~ .jlist label[for=j${j.id}]{border-color:var(--brand);background:var(--brand-soft);color:var(--brand-ink)}`);
  css.push(`#j${j.id}:focus-visible ~ .jlist label[for=j${j.id}]{outline:3px solid var(--brand);outline-offset:2px}`);
});
html.push('<input class="rj" type="checkbox" id="all" aria-label="Ver todas as etapas">');

html.push('<div class="jlist">');
J.forEach((j) => {
  html.push(`<label class="jbtn" for="j${j.id}">J${j.id}. ${j.t}<small>${j.s} · ${j.who}</small></label>`);
});
html.push('<label class="jbtn jall" for="all"><span class="off">Ver todas as etapas de uma vez</span><span class="on">Voltar a uma etapa por vez</span></label>');
html.push('</div>');

html.push('<div class="jmain">');
J.forEach((j, ji) => {
  const last = j.steps.length;
  html.push(`<div class="jp" id="p${j.id}">`);
  html.push(`<div class="jhead"><h3 id="jornada-${j.id}">J${j.id}. ${j.t}</h3><p>${j.goal}</p></div>`);
  j.steps.forEach((st, si) => {
    html.push(`<input class="rs" type="radio" name="s${j.id}" id="s${j.id}-${si + 1}" ${si === 0 ? 'checked' : ''} aria-label="Etapa ${si + 1}">`);
    css.push(`#s${j.id}-${si + 1}:checked ~ .stplist .stp:nth-child(${si + 1}){display:block}`);
    css.push(`#s${j.id}-${si + 1}:checked ~ .steps label[for=s${j.id}-${si + 1}]{border-color:var(--brand);background:var(--brand);color:#fff}`);
    css.push(`#s${j.id}-${si + 1}:checked ~ .steps label[for=s${j.id}-${si + 1}] b{background:rgba(255,255,255,.25)}`);
    css.push(`#s${j.id}-${si + 1}:focus-visible ~ .steps label[for=s${j.id}-${si + 1}]{outline:3px solid var(--brand);outline-offset:2px}`);
  });
  html.push('<ol class="steps">');
  j.steps.forEach((st, si) => {
    html.push(`<li><label for="s${j.id}-${si + 1}"><b>${si + 1}</b>${st.n}</label></li>`);
  });
  html.push('</ol>');
  html.push('<div class="stplist">');
  j.steps.forEach((st, si) => {
    const prev = si > 0 ? `<label class="nv" for="s${j.id}-${si}">Etapa anterior</label>` : '';
    let next = '';
    if (si < last - 1) next = `<label class="nv pri" for="s${j.id}-${si + 2}">Próxima etapa</label>`;
    else if (ji < J.length - 1) next = `<label class="nv pri" for="j${J[ji + 1].id}">Próxima jornada</label>`;
    html.push(`<div class="stp"><div class="sh">Etapa ${si + 1} de ${last} · ${st.n}</div>`
      + `<div class="stagebox"><div class="stage">${st.screen()}</div>`
      + `<div class="side"><div class="diff"><h4>O que muda em relação a hoje</h4><p>${st.diff}</p></div></div></div>`
      + `<div class="navrow">${prev}${next}</div></div>`);
  });
  html.push('</div>');
  html.push(`<div class="accept"><h4>Termos de aceite · J${j.id}</h4><ol>${[...j.accept].sort((x, y) => Number(x[0].split('-A')[1]) - Number(y[0].split('-A')[1])).map((a) => `<li><i>${a[0]}</i>${a[1]}</li>`).join('')}</ol></div>`);
  html.push('</div>');
});
html.push('</div></div>');

const extraCss = `
/* navegação das jornadas sem JavaScript */
.rj,.rs{position:absolute;opacity:0;width:1px;height:1px;pointer-events:none}
.jmain>.jp,.stplist>.stp{display:none}
.jall .on{display:none}
#all:checked ~ .jlist .jall .on{display:inline}
#all:checked ~ .jlist .jall .off{display:none}
#all:checked ~ .jmain .stplist .stp{display:block}
.sh{font:800 13px/1 var(--font);letter-spacing:.06em;text-transform:uppercase;color:var(--muted);margin:0 0 10px}
.stp{margin-bottom:18px}
.steps label{min-height:44px;padding:8px 14px;border-radius:999px;border:1px solid var(--line);background:var(--surface);color:var(--ink);cursor:pointer;font:600 14px/1.2 var(--font);display:flex;gap:8px;align-items:center}
.steps label b{display:inline-grid;place-items:center;width:24px;height:24px;border-radius:50%;background:var(--code);font-size:12px}
.jbtn{cursor:pointer}
.nv{display:inline-grid;place-items:center;min-height:44px;padding:10px 18px;border-radius:10px;border:1px solid var(--line);background:var(--surface);color:var(--ink);font:700 14px var(--font);cursor:pointer}
.nv.pri{background:var(--brand);border-color:var(--brand);color:#fff}
.accept{margin-top:6px}
.accept ol{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:10px 22px}
.stagebox{grid-template-columns:minmax(0,1.5fr) minmax(0,1fr)}
@media (max-width:900px){.stagebox{grid-template-columns:1fr}}
`;

let out = template.replace('<!--JORNADAS-->', html.join('\n'));
out = out.replace('</style>', `${extraCss}\n${css.join('\n')}\n</style>`);
out += `
<script>
// Opcional: abre a etapa indicada no endereço (#jornada-N-M). A página funciona sem este script.
try {
  var h = location.hash;
  if (h.indexOf('#jornada-') === 0) {
    var p = h.slice(9).split('-');
    var j = document.getElementById('j' + p[0]);
    var s = document.getElementById('s' + p[0] + '-' + (p[1] || 1));
    if (j) j.checked = true;
    if (s) s.checked = true;
  }
} catch (e) { /* sem script a página continua navegável */ }
</script>
</body>
</html>
`;
writeFileSync(join(root, 'PRD.html'), out);
console.log('PRD.html gerado:', out.length, 'bytes;', J.reduce((n, j) => n + j.steps.length, 0), 'etapas');
