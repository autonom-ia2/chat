const icons = {
  inbox: 'M4 4h16v16H4z M4 13h5l2 3h2l2-3h5', chat: 'M21 11a9 9 0 0 1-9 9H4l-2 2V11a9 9 0 0 1 19 0Z', phone: 'M5 3h4l2 5-3 2a15 15 0 0 0 6 6l2-3 5 2v4c-10 3-19-6-16-16Z', bot: 'M5 8h14v12H5z M12 8V3 M9 13v2 M15 13v2', users: 'M16 21v-3a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v3 M9 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M18 5a4 4 0 0 1 0 7 M20 16v5', columns: 'M3 4h18v16H3z M9 4v16 M15 4v16', chart: 'M3 3v18h18 M7 15l5-5 4 2 5-7', megaphone: 'M3 9h5l12-5v16L8 15H3z M7 15l2 6', qr: 'M3 3h6v6H3z M15 3h6v6h-6z M3 15h6v6H3z M15 15h3v3h3v3h-6z', plus: 'M12 5v14 M5 12h14', search: 'M21 21l-5-5 M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14', copy: 'M8 8h13v13H8z M16 8V3H3v13h5', download: 'M12 3v12 M7 10l5 5 5-5 M3 17v4h18v-4', expand: 'M8 3H3v5 M16 3h5v5 M3 16v5h5 M21 16v5h-5', close: 'M6 6l12 12 M18 6 6 18', route: 'M5 3a2 2 0 1 0 0 4 2 2 0 0 0 0-4 M19 17a2 2 0 1 0 0 4 2 2 0 0 0 0-4 M5 7v6a4 4 0 0 0 4 4h6a4 4 0 0 0 0-8h-2', arrow: 'M5 12h14 M14 7l5 5-5 5', link: 'M10 13a5 5 0 0 0 7 0l4-4a5 5 0 0 0-7-7l-3 3 M14 11a5 5 0 0 0-7 0l-4 4a5 5 0 0 0 7 7l3-3'
};
const icon = name => `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${icons[name] || icons.link}"/></svg>`;
document.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icon(el.dataset.icon); });
const $ = id => document.getElementById(id);
// Utilities de tema aplicadas também aos elementos criados na demonstração.
const themeClasses = {
  'bg-[#f7f8fa]': 'dark:bg-[#111827]', 'bg-white': 'dark:bg-[#192334]',
  'bg-slate-50': 'dark:bg-[#152030]', 'bg-slate-100': 'dark:bg-slate-700',
  'bg-slate-200': 'dark:bg-slate-700', 'bg-[#f0f6ff]': 'dark:bg-[#213b5b]',
  'bg-[#f3f6fa]': 'dark:bg-[#111d2d]', 'bg-[#edf3fa]': 'dark:bg-[#1a2d43]',
  'bg-blue-50': 'dark:bg-[#203c5f]', 'bg-blue-100': 'dark:bg-[#29476b]',
  'text-slate-800': 'dark:text-slate-100', 'text-slate-700': 'dark:text-slate-200',
  'text-slate-600': 'dark:text-slate-300', 'text-slate-500': 'dark:text-slate-400',
  'text-slate-400': 'dark:text-slate-400', 'text-[#172b49]': 'dark:text-slate-100',
  'text-[#263f61]': 'dark:text-slate-100', 'text-[#536883]': 'dark:text-slate-300',
  'text-[#35689f]': 'dark:text-blue-300', 'text-blue-700': 'dark:text-blue-300',
  'text-teal-700': 'dark:text-teal-300', 'border-slate-200': 'dark:border-slate-700',
  'border-slate-300': 'dark:border-slate-600', 'border-slate-100': 'dark:border-slate-700',
  'hover:bg-blue-50': 'dark:hover:bg-[#29476b]', 'hover:bg-blue-100': 'dark:hover:bg-[#29476b]',
  'hover:bg-slate-50': 'dark:hover:bg-slate-700', 'hover:bg-slate-100': 'dark:hover:bg-slate-700'
};
function applyThemeUtilities() {
  document.querySelectorAll('[class]').forEach(el => {
    [...el.classList].forEach(token => { if (themeClasses[token]) el.classList.add(themeClasses[token]); });
  });
  document.querySelectorAll('input,textarea,select').forEach(el => el.classList.add('dark:bg-[#111d2d]', 'dark:text-slate-100'));
  document.querySelectorAll('dialog').forEach(el => el.classList.add('bg-white', 'dark:bg-[#192334]'));
  document.querySelectorAll('img[src="qr-demo.svg"]').forEach(el => { el.classList.add('bg-white', 'rounded-lg'); if (el.parentElement.classList.contains('bg-white') && el.parentElement.children.length === 1) el.parentElement.classList.add('dark:bg-white'); });
  $('preview-message').parentElement.querySelector('p:last-child').classList.remove('dark:text-slate-300');
  $('preview-message').parentElement.querySelector('p:last-child').classList.add('dark:text-slate-600');
  // A mensagem simula a bolha clara do WhatsApp dentro da prévia.
  $('preview-message').classList.add('dark:bg-white', 'dark:text-slate-700');
}
$('theme').onclick = () => {
  const dark = document.documentElement.classList.toggle('dark');
  $('theme').textContent = dark ? 'Tema claro' : 'Tema escuro';
  $('theme').setAttribute('aria-pressed', String(dark));
};
const campaigns = [
  { name: 'Loja Centro · balcão', inbox: 'WhatsApp Loja Centro', code: 'demo-centro', clicks: 542, conversations: 87, message: 'Olá! Estou na loja Centro e gostaria de falar com a equipe.', type: 'qr', description: 'Ponto de venda' },
  { name: 'Instagram · bio', inbox: 'WhatsApp Comercial', code: 'demo-bio', clicks: 416, conversations: 54, message: 'Olá! Vim pelo Instagram e gostaria de saber mais.', type: 'link', description: 'Redes sociais' },
  { name: 'Marina · atendimento', inbox: 'WhatsApp Comercial', code: 'demo-marina', clicks: 238, conversations: 33, message: 'Olá! Gostaria de falar com a Marina.', type: 'link', description: 'Vendedor' },
  { name: 'Evento · primavera', inbox: 'WhatsApp Comercial', code: 'demo-evento', clicks: 88, conversations: 12, message: 'Olá! Conheci vocês no evento e quero saber mais.', type: 'qr', description: 'Evento presencial' }
];
let selected = 0;
let emptyMode = false;
let toastTimer;
const url = campaign => `https://example.invalid/l/${campaign.code}`;
const notify = message => { $('toast').textContent = message; $('toast').classList.remove('hidden'); clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').classList.add('hidden'), 3200); };
function details() {
  const campaign = campaigns[selected];
  $('detail-name').textContent = campaign.name;
  $('detail-inbox').textContent = campaign.inbox;
  $('detail-url').textContent = url(campaign);
  $('detail-message').textContent = campaign.message || 'Sem mensagem pré-preenchida.';
  $('poster-name').textContent = campaign.name;
}
function render() {
  $('rows').replaceChildren();
  let visible = 0;
  campaigns.forEach((campaign, index) => {
    if (emptyMode || !campaign.name.toLocaleLowerCase('pt-BR').includes($('search').value.toLocaleLowerCase('pt-BR'))) return;
    visible += 1;
    const row = document.createElement('button');
    row.className = `w-full text-left grid grid-cols-[minmax(0,1fr)_4rem_5rem_2rem] gap-4 px-5 py-5 border-b last:border-b-0 border-slate-100 items-center hover:bg-blue-50 focus-visible:outline-blue-500 ${index === selected ? 'bg-[#f0f6ff]' : 'bg-white'}`;
    row.setAttribute('aria-label', `Abrir ${campaign.name}`);
    row.setAttribute('aria-pressed', String(index === selected));
    row.innerHTML = `<span class="flex items-center gap-3 min-w-0"><span class="hidden md:flex w-10 h-10 shrink-0 items-center justify-center rounded-lg ${index === selected ? 'bg-blue-100 text-blue-700' : 'bg-slate-100 text-slate-500'}">${icon(campaign.type)}</span><span class="min-w-0"><span class="block font-semibold text-sm truncate" data-name></span><span class="block text-xs mt-1 text-slate-500" data-description></span></span></span><span class="text-right text-sm tabular-nums font-medium">${campaign.clicks}</span><span class="text-right text-sm tabular-nums font-semibold text-teal-700">${campaign.conversations}</span><span class="text-slate-400">${icon('arrow')}</span>`;
    row.querySelector('[data-name]').textContent = campaign.name;
    row.querySelector('[data-description]').textContent = `${campaign.description} · ${campaign.inbox}`;
    row.onclick = () => { selected = index; render(); details(); };
    $('rows').append(row);
  });
  $('empty').classList.toggle('hidden', !emptyMode);
  if (!emptyMode && !visible) { const p = document.createElement('p'); p.className = 'p-8 text-center text-sm text-slate-500'; p.textContent = 'Nenhuma campanha encontrada. Tente outro nome.'; $('rows').append(p); }
  $('total').textContent = emptyMode ? '0' : String(campaigns.length);
  $('clicks-total').textContent = emptyMode ? '0' : '1.284';
  $('conversations-total').textContent = emptyMode ? '0' : '186';
  $('detail-panel').classList.toggle('hidden', emptyMode);
  $('count').textContent = String(visible);
  $('results').textContent = `${visible} campanhas · resultados acumulados`;
  $('empty-toggle').textContent = emptyMode ? 'Voltar à lista' : 'Ver estado vazio';
  applyThemeUtilities();
}
const openCreate = () => { $('creator').showModal(); $('name').focus(); };
$('new').onclick = openCreate;
$('empty-create').onclick = openCreate;
$('empty-toggle').onclick = () => { emptyMode = !emptyMode; render(); };
$('search').oninput = render;
document.querySelectorAll('[data-close]').forEach(el => { el.onclick = () => $(el.dataset.close).close(); });
['name', 'inbox', 'message'].forEach(id => { $(id).oninput = () => { $('preview-name').textContent = $('name').value || 'Sua campanha'; $('preview-message').textContent = $('message').value || 'Olá! Gostaria de saber mais.'; $('preview-inbox').textContent = $('inbox').value; }; });
$('form').onsubmit = event => {
  event.preventDefault();
  if (!$('name').value.trim()) { $('name').setCustomValidity('Informe um nome para a campanha.'); $('name').reportValidity(); return; }
  campaigns.unshift({ name: $('name').value.trim(), inbox: $('inbox').value, code: `demo-${campaigns.length + 1}`, clicks: 0, conversations: 0, message: $('message').value.trim(), type: 'qr', description: 'Nova origem' });
  selected = 0; emptyMode = false; $('search').value = ''; render(); details(); $('creator').close(); notify('Campanha criada na demonstração.');
};
$('name').addEventListener('input', () => $('name').setCustomValidity(''));
$('copy').onclick = async () => { try { await navigator.clipboard.writeText(url(campaigns[selected])); notify('Link demonstrativo copiado.'); } catch { notify('Copie o endereço exibido no campo do link.'); } };
$('download').onclick = () => { const a = document.createElement('a'); a.href = 'qr-demo.svg'; a.download = 'qr-demonstracao.svg'; a.click(); notify('QR demonstrativo baixado.'); };
$('material').onclick = () => $('poster').showModal();
render(); details();
