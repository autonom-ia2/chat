// Biblioteca de blocos MJML da Autonomia para o GrapesJS (grapesjs-mjml).
// Labels em pt-BR direto: o painel de blocos do GrapesJS fica fora do escopo
// do vue-i18n (decisão E12 do manifesto — MVP com labels estáticos).

import { canonicalizeMjml } from './mjmlCanonical';
import { editableFooterMjml } from './lockedFooter';

const BRAND_COLOR = '#2563eb';
const TEXT_COLOR = '#1f2937';
const MUTED_COLOR = '#6b7280';
// Contraste AA (>= 4,5:1, #1081): #6b7280 só passa sobre branco. Sobre BG_SOFT usa o cinza mais
// escuro; sobre BRAND_COLOR, o azul quase branco (#dbeafe dava 4,24).
const MUTED_ON_SOFT = '#4b5563';
const TINT_ON_BRAND = '#eff6ff';
const BG_SOFT = '#f4f4f4';
// Fonte email-safe explícita em todo texto/botão: sem ela o MJML usa Ubuntu e importa a web font (#1081).
const FONT_FAMILY = 'Arial, Helvetica, sans-serif';

// Placeholder de imagem HOSPEDADO (PNG via placehold.co). data:image/svg+xml NÃO
// renderiza no Gmail (bloqueado), então o placeholder precisa ser uma URL https
// que devolve um raster — assim o bloco recém-arrastado já aparece no e-mail
// enviado, antes mesmo de o usuário trocar pela imagem real.
export const placeholderImage = (width, height, label) =>
  `https://placehold.co/${width}x${height}/e2e8f0/64748b/png?text=${encodeURIComponent(label)}`;

// Poster de vídeo placeholder (fundo escuro + rótulo). Para o vídeo real, o
// usuário cola o link do YouTube/Vimeo e usa "Buscar capa do vídeo" (resolveVideo),
// que troca por uma miniatura hospedada de verdade.
export const videoPosterPlaceholder = (width, height) =>
  `https://placehold.co/${width}x${height}/0f172a/ffffff/png?text=${encodeURIComponent(
    '▶  Assistir ao vídeo'
  )}`;

const icon = body =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;

// Categorias coerentes para o painel de blocos Vue (block.getCategoryLabel()).
const CAT_DESTAQUE = 'Destaque';
const CAT_CONTEUDO = 'Conteúdo';
const CAT_PROVA = 'Prova social';
const CAT_ACAO = 'Chamada para ação';
const CAT_ESTRUTURA = 'Estrutura';

// URL de assistir do vídeo (placeholder editável) e poster com play já composto
// (variante simples §2.2 das amendments — email-safe, sem <video>/iframe).
// Link de exemplo neutro: a pessoa troca pelo do próprio site no painel de propriedades.
const EXAMPLE_URL = 'https://seusite.com.br';
const VIDEO_WATCH_URL = EXAMPLE_URL;

// Rodapé legal — mj-section travada pelo F1 via css-class="footer-locked" (E11). Vem da fonte única
// lockedFooter.json (#1081), a mesma do servidor; aqui com os placeholders editáveis: linha da empresa
// e ícones de redes sociais (PNG hospedados, renderizam no Gmail) apontando para a raiz de cada rede —
// o usuário troca pelo perfil da empresa no painel (seção Link ao selecionar o ícone).
export const FOOTER_MJML = editableFooterMjml({ social: true });

const BLOCKS = [
  {
    id: 'autonomia-text',
    label: 'Texto',
    category: CAT_CONTEUDO,
    media: icon(
      '<line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17" x2="14" y2="17"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="16px 24px">
  <mj-column>
    <mj-text font-family="${FONT_FAMILY}" font-size="15px" color="${TEXT_COLOR}" line-height="1.6">Escreva seu texto aqui. Clique para editar.</mj-text>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-heading',
    label: 'Título',
    category: CAT_CONTEUDO,
    media: icon(
      '<path d="M6 4v16"/><path d="M18 4v16"/><line x1="6" y1="12" x2="18" y2="12"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="16px 24px">
  <mj-column>
    <mj-text font-family="${FONT_FAMILY}" font-size="24px" font-weight="bold" color="${TEXT_COLOR}" line-height="1.3">Título da seção</mj-text>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-button',
    label: 'Botão',
    category: CAT_ACAO,
    media: icon(
      '<rect x="3" y="9" width="18" height="6" rx="3"/><line x1="9" y1="12" x2="15" y2="12"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="16px 24px">
  <mj-column>
    <mj-button font-family="${FONT_FAMILY}" background-color="${BRAND_COLOR}" color="#ffffff" font-size="16px" border-radius="6px" href="${EXAMPLE_URL}">Ver detalhes</mj-button>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-image',
    label: 'Imagem',
    category: CAT_CONTEUDO,
    media: icon(
      '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="16px 24px">
  <mj-column>
    <mj-image src="${placeholderImage(600, 300, 'Imagem')}" alt="Imagem" padding="0"/>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-hero',
    label: 'Hero (imagem + título + CTA)',
    category: CAT_DESTAQUE,
    media: icon(
      '<rect x="3" y="3" width="18" height="12" rx="2"/><line x1="7" y1="19" x2="17" y2="19"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="0">
  <mj-column>
    <mj-image src="${placeholderImage(600, 240, 'Imagem hero 600x240')}" alt="Imagem de destaque" padding="0"/>
    <mj-text font-family="${FONT_FAMILY}" font-size="28px" font-weight="bold" color="${TEXT_COLOR}" align="center" padding="24px 24px 8px">Título principal da campanha</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="16px" color="${MUTED_COLOR}" align="center" line-height="1.5" padding="0 32px 16px">Uma frase curta de apoio explicando a proposta de valor.</mj-text>
    <mj-button font-family="${FONT_FAMILY}" background-color="${BRAND_COLOR}" color="#ffffff" font-size="16px" border-radius="6px" href="${EXAMPLE_URL}" padding="8px 0 32px">Quero saber mais</mj-button>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-offer',
    label: 'Oferta destacada',
    category: CAT_DESTAQUE,
    media: icon(
      '<path d="M20 12v8H4v-8"/><path d="M2 7h20v5H2z"/><path d="M12 22V7"/><path d="M12 7c2 0 4-1 4-3s-4-2-4 3c0-5-4-5-4-3s2 3 4 3z"/>'
    ),
    content: `<mj-section background-color="${BRAND_COLOR}" border-radius="8px" padding="32px 24px">
  <mj-column>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" color="${TINT_ON_BRAND}" align="center" text-transform="uppercase" letter-spacing="2px" padding="0 0 8px">Oferta especial</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="32px" font-weight="bold" color="#ffffff" align="center" padding="0 0 8px">A partir de R$ 99/mês</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="15px" color="${TINT_ON_BRAND}" align="center" line-height="1.5" padding="0 0 16px">Condição válida por tempo limitado. Aproveite agora.</mj-text>
    <mj-button font-family="${FONT_FAMILY}" background-color="#ffffff" color="${BRAND_COLOR}" font-size="16px" font-weight="bold" border-radius="6px" href="${EXAMPLE_URL}">Garantir oferta</mj-button>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-benefits',
    label: 'Benefícios (3 cards)',
    category: CAT_CONTEUDO,
    media: icon(
      '<rect x="2" y="6" width="6" height="12" rx="1"/><rect x="9" y="6" width="6" height="12" rx="1"/><rect x="16" y="6" width="6" height="12" rx="1"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="24px 12px">
  <mj-column>
    <mj-image src="${placeholderImage(96, 96, 'Ícone')}" alt="Benefício 1" width="64px" padding="0 0 8px"/>
    <mj-text font-family="${FONT_FAMILY}" font-size="16px" font-weight="bold" color="${TEXT_COLOR}" align="center" padding="0 8px 4px">Benefício 1</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="13px" color="${MUTED_COLOR}" align="center" line-height="1.5" padding="0 8px">Descrição curta do primeiro benefício.</mj-text>
  </mj-column>
  <mj-column>
    <mj-image src="${placeholderImage(96, 96, 'Ícone')}" alt="Benefício 2" width="64px" padding="0 0 8px"/>
    <mj-text font-family="${FONT_FAMILY}" font-size="16px" font-weight="bold" color="${TEXT_COLOR}" align="center" padding="0 8px 4px">Benefício 2</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="13px" color="${MUTED_COLOR}" align="center" line-height="1.5" padding="0 8px">Descrição curta do segundo benefício.</mj-text>
  </mj-column>
  <mj-column>
    <mj-image src="${placeholderImage(96, 96, 'Ícone')}" alt="Benefício 3" width="64px" padding="0 0 8px"/>
    <mj-text font-family="${FONT_FAMILY}" font-size="16px" font-weight="bold" color="${TEXT_COLOR}" align="center" padding="0 8px 4px">Benefício 3</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="13px" color="${MUTED_COLOR}" align="center" line-height="1.5" padding="0 8px">Descrição curta do terceiro benefício.</mj-text>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-testimonial',
    label: 'Depoimento',
    category: CAT_PROVA,
    media: icon(
      '<path d="M3 21c3-1 4-3 4-5H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v6c0 4-3 6-8 7z"/><path d="M14 21c3-1 4-3 4-5h-3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v6c0 4-3 6-8 7z"/>'
    ),
    content: `<mj-section background-color="${BG_SOFT}" border-radius="8px" padding="32px 24px">
  <mj-column>
    <mj-text font-family="${FONT_FAMILY}" font-size="18px" font-style="italic" color="${TEXT_COLOR}" align="center" line-height="1.6" padding="0 16px 12px">“Transformou a forma como cuidamos dos nossos clientes. Recomendo de olhos fechados.”</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" font-weight="bold" color="${MUTED_ON_SOFT}" align="center" padding="0">Maria Silva — Cliente desde 2024</mj-text>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-products',
    label: 'Produtos (grade 2x2)',
    category: CAT_CONTEUDO,
    media: icon(
      '<rect x="3" y="3" width="8" height="8" rx="1"/><rect x="13" y="3" width="8" height="8" rx="1"/><rect x="3" y="13" width="8" height="8" rx="1"/><rect x="13" y="13" width="8" height="8" rx="1"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="24px 12px 0">
  <mj-column>
    <mj-image src="${placeholderImage(280, 180, 'Produto 1')}" alt="Produto 1" border-radius="6px" padding="0 8px 8px"/>
    <mj-text font-family="${FONT_FAMILY}" font-size="15px" font-weight="bold" color="${TEXT_COLOR}" align="center" padding="0 8px 2px">Produto 1</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" color="${BRAND_COLOR}" align="center" padding="0 8px 16px">R$ 199,00</mj-text>
  </mj-column>
  <mj-column>
    <mj-image src="${placeholderImage(280, 180, 'Produto 2')}" alt="Produto 2" border-radius="6px" padding="0 8px 8px"/>
    <mj-text font-family="${FONT_FAMILY}" font-size="15px" font-weight="bold" color="${TEXT_COLOR}" align="center" padding="0 8px 2px">Produto 2</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" color="${BRAND_COLOR}" align="center" padding="0 8px 16px">R$ 249,00</mj-text>
  </mj-column>
</mj-section>
<mj-section background-color="#ffffff" padding="0 12px 24px">
  <mj-column>
    <mj-image src="${placeholderImage(280, 180, 'Produto 3')}" alt="Produto 3" border-radius="6px" padding="0 8px 8px"/>
    <mj-text font-family="${FONT_FAMILY}" font-size="15px" font-weight="bold" color="${TEXT_COLOR}" align="center" padding="0 8px 2px">Produto 3</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" color="${BRAND_COLOR}" align="center" padding="0 8px 16px">R$ 299,00</mj-text>
  </mj-column>
  <mj-column>
    <mj-image src="${placeholderImage(280, 180, 'Produto 4')}" alt="Produto 4" border-radius="6px" padding="0 8px 8px"/>
    <mj-text font-family="${FONT_FAMILY}" font-size="15px" font-weight="bold" color="${TEXT_COLOR}" align="center" padding="0 8px 2px">Produto 4</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" color="${BRAND_COLOR}" align="center" padding="0 8px 16px">R$ 349,00</mj-text>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-image-text',
    label: 'Imagem + texto',
    category: CAT_CONTEUDO,
    media: icon(
      '<rect x="3" y="5" width="8" height="14" rx="1"/><line x1="14" y1="7" x2="21" y2="7"/><line x1="14" y1="12" x2="21" y2="12"/><line x1="14" y1="17" x2="19" y2="17"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="24px">
  <mj-column width="40%">
    <mj-image src="${placeholderImage(220, 180, 'Imagem')}" alt="Imagem ilustrativa" border-radius="6px" padding="0"/>
  </mj-column>
  <mj-column width="60%" vertical-align="middle">
    <mj-text font-family="${FONT_FAMILY}" font-size="18px" font-weight="bold" color="${TEXT_COLOR}" padding="0 0 8px">Título da seção</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" color="${MUTED_COLOR}" line-height="1.6" padding="0 0 12px">Texto de apoio ao lado da imagem. Explique um detalhe do produto ou serviço em poucas linhas.</mj-text>
    <mj-button font-family="${FONT_FAMILY}" background-color="${BRAND_COLOR}" color="#ffffff" font-size="14px" border-radius="6px" href="${EXAMPLE_URL}" align="left" padding="0">Saiba mais</mj-button>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-video',
    label: 'Vídeo (poster + play)',
    category: CAT_CONTEUDO,
    media: icon(
      '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m10 9 5 3-5 3z"/>'
    ),
    // Variante simples §2.2 das amendments: mj-image (poster já com play) + href.
    // Email-safe — sem <video>/iframe; o href garante a clicabilidade. A IA e a
    // galeria emitem ESTE bloco; o usuário troca src/href pelo vídeo real.
    content: `<mj-section background-color="#000000" padding="0" css-class="video-block">
  <mj-column>
    <mj-image src="${videoPosterPlaceholder(600, 338)}" href="${VIDEO_WATCH_URL}" alt="Assistir: descrição do vídeo" padding="0"/>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-cta',
    label: 'CTA grande',
    category: CAT_ACAO,
    media: icon(
      '<rect x="3" y="8" width="18" height="8" rx="4"/><line x1="8" y1="12" x2="16" y2="12"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="32px 24px">
  <mj-column>
    <mj-text font-family="${FONT_FAMILY}" font-size="22px" font-weight="bold" color="${TEXT_COLOR}" align="center" padding="0 0 16px">Pronto para dar o próximo passo?</mj-text>
    <mj-button font-family="${FONT_FAMILY}" background-color="${BRAND_COLOR}" color="#ffffff" font-size="18px" font-weight="bold" border-radius="8px" inner-padding="16px 40px" href="${EXAMPLE_URL}">Fale com a gente</mj-button>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-faq',
    label: 'FAQ (3 itens)',
    category: CAT_CONTEUDO,
    media: icon(
      '<circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3"/><line x1="12" y1="17" x2="12" y2="17"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="24px">
  <mj-column>
    <mj-text font-family="${FONT_FAMILY}" font-size="20px" font-weight="bold" color="${TEXT_COLOR}" padding="0 0 16px">Perguntas frequentes</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="15px" font-weight="bold" color="${TEXT_COLOR}" padding="0 0 4px">Como funciona?</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" color="${MUTED_COLOR}" line-height="1.6" padding="0 0 12px">Resposta curta e direta para a primeira pergunta.</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="15px" font-weight="bold" color="${TEXT_COLOR}" padding="0 0 4px">Quanto custa?</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" color="${MUTED_COLOR}" line-height="1.6" padding="0 0 12px">Resposta curta e direta para a segunda pergunta.</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="15px" font-weight="bold" color="${TEXT_COLOR}" padding="0 0 4px">Posso cancelar quando quiser?</mj-text>
    <mj-text font-family="${FONT_FAMILY}" font-size="14px" color="${MUTED_COLOR}" line-height="1.6" padding="0">Resposta curta e direta para a terceira pergunta.</mj-text>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-divider',
    label: 'Divisor / espaçador',
    category: CAT_ESTRUTURA,
    media: icon(
      '<line x1="3" y1="12" x2="21" y2="12" stroke-dasharray="4 3"/>'
    ),
    content: `<mj-section background-color="#ffffff" padding="0 24px">
  <mj-column>
    <mj-spacer height="16px"/>
    <mj-divider border-width="1px" border-color="#e5e7eb" padding="0"/>
    <mj-spacer height="16px"/>
  </mj-column>
</mj-section>`,
  },
  {
    id: 'autonomia-footer',
    label: 'Rodapé legal',
    category: CAT_ESTRUTURA,
    media: icon(
      '<rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="16" x2="21" y2="16"/><line x1="8" y1="19" x2="16" y2="19"/>'
    ),
    content: FOOTER_MJML,
  },
];

// grapesjs-mjml lê o conteúdo do bloco com o parser HTML: um self-closed `<mj-image/>` vira tag
// de abertura e "engole" os irmãos no drag/drop. canonicalizeMjml (#1074) fecha cada tag de forma
// explícita, o mesmo tratamento que o useEmailEditor aplica ao MJML carregado no editor.
export default function registerAutonomiaBlocks(editor) {
  BLOCKS.forEach(({ id, label, category, media, content }) => {
    editor.Blocks.add(id, {
      label,
      category,
      media,
      content: canonicalizeMjml(content),
      select: true,
    });
  });
}
