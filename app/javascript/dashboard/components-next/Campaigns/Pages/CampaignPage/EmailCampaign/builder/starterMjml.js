import { editableFooterMjml } from './lockedFooter';

// E-mail inicial do editor. Fonte email-safe explícita (sem ela o MJML importa a web font Ubuntu) e o
// rodapé travado da fonte única lockedFooter.json (#1081).
export const STARTER_MJML = `<mjml>
  <mj-body background-color="#f4f4f4">
    <mj-section background-color="#ffffff" padding="24px">
      <mj-column>
        <mj-text font-family="Arial, Helvetica, sans-serif" font-size="16px" line-height="1.5">Olá {{ nome }},</mj-text>
      </mj-column>
    </mj-section>
    ${editableFooterMjml()}
  </mj-body>
</mjml>`;

export default STARTER_MJML;
