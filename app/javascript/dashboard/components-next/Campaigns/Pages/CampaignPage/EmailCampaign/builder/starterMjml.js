export const STARTER_MJML = `<mjml>
  <mj-body background-color="#f4f4f4">
    <mj-section background-color="#ffffff" padding="24px">
      <mj-column>
        <mj-text font-size="16px" line-height="1.5">Olá {{ nome }},</mj-text>
      </mj-column>
    </mj-section>
    <mj-section css-class="footer-locked" background-color="#f4f4f4" padding="16px">
      <mj-column>
        <mj-text font-size="11px" color="#888888" align="center">
          Nome da sua empresa · Endereço da empresa<br/>
          Você recebeu este e-mail porque está em nossa lista de contatos.<br/>
          <a href="{{ unsubscribe_url }}" style="color:#888888;">Cancelar inscrição</a>
        </mj-text>
      </mj-column>
    </mj-section>
  </mj-body>
</mjml>`;

export default STARTER_MJML;
