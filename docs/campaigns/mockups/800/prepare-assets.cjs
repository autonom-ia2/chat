/* Run with Node. Reuses repository-owned assets; does not access an API or database. */
const fs = require('fs');
const path = require('path');
const repo = path.resolve(__dirname, '../../../..');
const out = path.join(__dirname, 'assets');
fs.mkdirSync(out, { recursive: true });
fs.copyFileSync(path.join(repo, 'public/brand-assets/hub2you-icon.png'), path.join(out, 'hub2you-icon.png'));
const iconData = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const names = ['search', 'inbox', 'messages-square', 'phone', 'bot', 'target', 'shield-check', 'contact', 'briefcase-business', 'wallet', 'chart-no-axes-combined', 'megaphone', 'book-open', 'settings', 'circle-help', 'chevron-down', 'chevron-right', 'arrow-left', 'arrow-right', 'plus', 'mail', 'send', 'calendar-days', 'check', 'circle-check', 'circle-alert', 'clock-3', 'ellipsis', 'pencil', 'eye', 'users', 'sparkles', 'layout-template', 'image', 'type', 'mouse-pointer-2', 'video', 'columns-2', 'separator-horizontal', 'monitor', 'smartphone', 'save', 'copy', 'x', 'external-link', 'download', 'shield', 'link', 'list-filter', 'file-spreadsheet', 'refresh-cw', 'lock-keyhole', 'text-cursor-input', 'chevrons-up-down', 'panel-right-close'];
const icons = Object.fromEntries(names.map(name => [name, iconData.icons[iconData.aliases[name]?.parent || name].body]));
fs.writeFileSync(path.join(__dirname, 'icons.json'), JSON.stringify(icons));
const entries = [
 ['product-launch/01-new-flavor-simple', 'Lançamento de produto', 'Apresente uma novidade com uma imagem de destaque e uma ação principal.', 'Lançamentos'],
 ['newsletter/01-weekly-data-analysis', 'Newsletter de conteúdo', 'Compartilhe novidades, dados e uma seleção de conteúdos.', 'Newsletters'],
 ['reengagement/03-win-back-poll-feedback', 'Retomar o relacionamento', 'Convide clientes que perderam contato a contar o que precisam.', 'Relacionamento'],
 ['account-activation/01-welcome-donation-activation', 'Boas-vindas', 'Receba um novo contato e oriente seus próximos passos.', 'Boas-vindas'],
 ['product-launch/02-teaser-mystery', 'Vem novidade por aí', 'Crie expectativa antes de lançar um produto ou serviço.', 'Lançamentos'],
 ['newsletter/02-newsletter-productivity-tips', 'Dicas e boas práticas', 'Organize dicas úteis em uma mensagem fácil de ler.', 'Newsletters'],
 ['reengagement/02-anniversary-milestone', 'Uma data para celebrar', 'Valorize um aniversário ou marco do relacionamento.', 'Relacionamento'],
 ['reengagement/01-breakup-final', 'Último convite para voltar', 'Faça uma última abordagem clara e respeitosa.', 'Relacionamento'],
 ['abandoned-cart/01-cart-recovery-benefits', 'Recuperar uma compra', 'Relembre os benefícios e facilite a retomada da compra.', 'Vendas'],
 ['upsell/01-order-bump-discount', 'Uma oferta complementar', 'Apresente uma oferta relevante depois de uma compra.', 'Vendas'],
 ['feedback/01-webinar-thank-you-review', 'Obrigado pela participação', 'Agradeça a presença no evento e peça uma avaliação.', 'Eventos'],
 ['shipping-update/01-card-shipped', 'Atualização de entrega', 'Informe o andamento de uma entrega com clareza.', 'Transacionais'],
 ['account-activation/02-email-verification-security', 'Confirmar endereço de e-mail', 'Ajude o usuário a concluir a confirmação do cadastro.', 'Transacionais'],
 ['receipt-invoice/01-review-request-post-delivery', 'Avaliação após a entrega', 'Peça um retorno depois que o cliente receber o pedido.', 'Relacionamento']
];
const templates = entries.map(([file, name, description, category], index) => {
  const dest = path.join(out, 'templates', file + '.html');
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  if (fs.existsSync(dest)) fs.unlinkSync(dest);
  const source = path.join(repo, 'db/seeds/email_templates', file + '.html');
  fs.symlinkSync(path.relative(path.dirname(dest), source), dest);
  return { id: index + 1, file: 'assets/templates/' + file + '.html', name, description, category };
});
fs.copyFileSync(path.join(repo, 'db/seeds/email_templates/LICENSE'), path.join(out, 'templates/LICENSE'));
fs.writeFileSync(path.join(__dirname, 'catalog.json'), JSON.stringify(templates, null, 2) + '\n');
fs.writeFileSync(path.join(__dirname, 'data.js'), 'const MOCKUP_DATA = ' + JSON.stringify({ icons, catalog: templates }) + ';\n');
console.log('Assets prepared: ' + templates.length + ' original templates; ' + names.length + ' library icons.');
