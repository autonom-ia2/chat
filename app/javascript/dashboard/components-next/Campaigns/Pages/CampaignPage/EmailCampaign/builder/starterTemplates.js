// Templates MJML iniciais da Autonomia. Todos terminam com a mj-section
// css-class="footer-locked" (F1 trava após o load — E11/E12 do manifesto).
import { placeholderImage, FOOTER_MJML } from './blocks.js';

export const starterTemplates = [
  {
    id: 'promo',
    name: 'Promocional',
    mjml: `<mjml>
  <mj-body background-color="#f4f4f4">
    <mj-section background-color="#ffffff" padding="0">
      <mj-column>
        <mj-image src="${placeholderImage(600, 240, 'Imagem hero 600x240')}" alt="Imagem de destaque" padding="0"/>
        <mj-text font-size="28px" font-weight="bold" color="#1f2937" align="center" padding="24px 24px 8px">Olá {{ nome }}, temos uma oferta para você</mj-text>
        <mj-text font-size="16px" color="#6b7280" align="center" line-height="1.5" padding="0 32px 24px">Condições exclusivas por tempo limitado para quem já é da nossa lista.</mj-text>
      </mj-column>
    </mj-section>
    <mj-section background-color="#2563eb" padding="32px 24px">
      <mj-column>
        <mj-text font-size="14px" color="#dbeafe" align="center" text-transform="uppercase" letter-spacing="2px" padding="0 0 8px">Oferta especial</mj-text>
        <mj-text font-size="32px" font-weight="bold" color="#ffffff" align="center" padding="0 0 8px">A partir de R$ 99/mês</mj-text>
        <mj-text font-size="15px" color="#dbeafe" align="center" line-height="1.5" padding="0 0 16px">Aproveite antes que acabe.</mj-text>
        <mj-button background-color="#ffffff" color="#2563eb" font-size="16px" font-weight="bold" border-radius="6px" href="https://autonomia.site">Garantir oferta</mj-button>
      </mj-column>
    </mj-section>
    <mj-section background-color="#ffffff" padding="24px 12px">
      <mj-column>
        <mj-image src="${placeholderImage(96, 96, 'Ícone')}" alt="Benefício 1" width="64px" padding="0 0 8px"/>
        <mj-text font-size="16px" font-weight="bold" color="#1f2937" align="center" padding="0 8px 4px">Rápido</mj-text>
        <mj-text font-size="13px" color="#6b7280" align="center" line-height="1.5" padding="0 8px">Contratação em poucos minutos.</mj-text>
      </mj-column>
      <mj-column>
        <mj-image src="${placeholderImage(96, 96, 'Ícone')}" alt="Benefício 2" width="64px" padding="0 0 8px"/>
        <mj-text font-size="16px" font-weight="bold" color="#1f2937" align="center" padding="0 8px 4px">Sem burocracia</mj-text>
        <mj-text font-size="13px" color="#6b7280" align="center" line-height="1.5" padding="0 8px">Tudo 100% digital.</mj-text>
      </mj-column>
      <mj-column>
        <mj-image src="${placeholderImage(96, 96, 'Ícone')}" alt="Benefício 3" width="64px" padding="0 0 8px"/>
        <mj-text font-size="16px" font-weight="bold" color="#1f2937" align="center" padding="0 8px 4px">Suporte humano</mj-text>
        <mj-text font-size="13px" color="#6b7280" align="center" line-height="1.5" padding="0 8px">Atendimento de verdade quando precisar.</mj-text>
      </mj-column>
    </mj-section>
    <mj-section background-color="#ffffff" padding="8px 24px 32px">
      <mj-column>
        <mj-button background-color="#2563eb" color="#ffffff" font-size="18px" font-weight="bold" border-radius="8px" inner-padding="16px 40px" href="https://autonomia.site">Quero aproveitar</mj-button>
      </mj-column>
    </mj-section>
    ${FOOTER_MJML}
  </mj-body>
</mjml>`,
  },
  {
    id: 'newsletter',
    name: 'Newsletter',
    mjml: `<mjml>
  <mj-body background-color="#f4f4f4">
    <mj-section background-color="#ffffff" padding="24px">
      <mj-column>
        <mj-image src="${placeholderImage(180, 48, 'Logo')}" alt="Logo da empresa" width="180px" padding="0 0 16px"/>
        <mj-text font-size="22px" font-weight="bold" color="#1f2937" padding="0 0 8px">Olá {{ nome }},</mj-text>
        <mj-text font-size="15px" color="#6b7280" line-height="1.6" padding="0">Estas são as novidades do mês. Boa leitura!</mj-text>
      </mj-column>
    </mj-section>
    <mj-section background-color="#ffffff" padding="0 24px">
      <mj-column>
        <mj-divider border-width="1px" border-color="#e5e7eb" padding="0"/>
      </mj-column>
    </mj-section>
    <mj-section background-color="#ffffff" padding="24px">
      <mj-column width="40%">
        <mj-image src="${placeholderImage(220, 180, 'Imagem')}" alt="Destaque 1" border-radius="6px" padding="0"/>
      </mj-column>
      <mj-column width="60%" vertical-align="middle">
        <mj-text font-size="18px" font-weight="bold" color="#1f2937" padding="0 0 8px">Primeira novidade</mj-text>
        <mj-text font-size="14px" color="#6b7280" line-height="1.6" padding="0 0 12px">Resumo curto da primeira novidade do mês em duas ou três linhas.</mj-text>
        <mj-button background-color="#2563eb" color="#ffffff" font-size="14px" border-radius="6px" href="https://autonomia.site" align="left" padding="0">Ler mais</mj-button>
      </mj-column>
    </mj-section>
    <mj-section background-color="#ffffff" padding="0 24px 24px">
      <mj-column width="40%">
        <mj-image src="${placeholderImage(220, 180, 'Imagem')}" alt="Destaque 2" border-radius="6px" padding="0"/>
      </mj-column>
      <mj-column width="60%" vertical-align="middle">
        <mj-text font-size="18px" font-weight="bold" color="#1f2937" padding="0 0 8px">Segunda novidade</mj-text>
        <mj-text font-size="14px" color="#6b7280" line-height="1.6" padding="0 0 12px">Resumo curto da segunda novidade do mês em duas ou três linhas.</mj-text>
        <mj-button background-color="#2563eb" color="#ffffff" font-size="14px" border-radius="6px" href="https://autonomia.site" align="left" padding="0">Ler mais</mj-button>
      </mj-column>
    </mj-section>
    ${FOOTER_MJML}
  </mj-body>
</mjml>`,
  },
  {
    id: 'transactional',
    name: 'Transacional',
    mjml: `<mjml>
  <mj-body background-color="#f4f4f4">
    <mj-section background-color="#ffffff" padding="32px 24px">
      <mj-column>
        <mj-text font-size="20px" font-weight="bold" color="#1f2937" padding="0 0 12px">Olá {{ nome }},</mj-text>
        <mj-text font-size="15px" color="#1f2937" line-height="1.6" padding="0 0 16px">Temos uma atualização sobre a sua conta. Veja os detalhes abaixo e, se precisar de algo, é só responder este e-mail.</mj-text>
        <mj-button background-color="#2563eb" color="#ffffff" font-size="15px" border-radius="6px" href="https://autonomia.site" align="left" padding="0 0 16px">Ver detalhes</mj-button>
        <mj-text font-size="13px" color="#6b7280" line-height="1.6" padding="0">Se você não reconhece esta mensagem, ignore este e-mail.</mj-text>
      </mj-column>
    </mj-section>
    ${FOOTER_MJML}
  </mj-body>
</mjml>`,
  },
];
