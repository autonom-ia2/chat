# Agendamento: botão "Ver meu horário" no aviso do WhatsApp oficial (#1517)

Refs #1517, #1473 (envios ricos), #1354 (texto próprio do aviso).

## Decisão (Rodrigo, 14/10/2026, alinhada com o chat Auditoria BM)

- O botão sai só quando `RichMessages.delivery_mode(inbox:, type: 'link_button', conversation:)` responde `:native`
  para a conversa em que a mensagem vai ser criada (`decision.conversation`), o modo é `:session` e não é Híbrido.
  Lugar único: `Crm::BookingV2::Notices::Button`.
- `rich_message = { 'type' => 'link_button', 'label' => 'Ver meu horário', 'url' => invite.url }`.
- `{{horario.link_gestao}}` deixou de ser obrigatório no texto próprio (`CustomText::REQUIRED_KEYS = [WHEN]`); a IA
  (`Ai::Redacao`) recebe isso como `obrigatorias` pelo concern do agendamento, sem mudança no redator. A tela também
  deixou de exigir o link.
- Texto próprio com o link → sem botão, texto com o link. Texto sem o link → com botão; no caminho só de texto, o
  sistema acrescenta a linha fixa `manage_line` antes da linha de parar. O texto padrão com botão sai sem o link cru.
  A linha de parar (RA-18) vai em todo aviso em texto (sessão, WAHA, Híbrido) e no complemento do modelo do canal API.
  No modelo da Meta não há linha: o "parar" está no link do `{{3}}` (`Notices::Route`), cuja página oferece parar os
  avisos; isso não mudou.
- "Testar no meu WhatsApp" (`TestInvite`): a mesma decisão (`Notices::Button`). Texto padrão do convite com botão:
  `invite.button_text` (sem o link cru); texto da página com `{link}` → sem botão. O convite de teste não tem linha de
  parar: convite não é aviso, e já era assim. Por decisão do Rodrigo ("o sistema garante o link"), o texto da página
  sem `{link}` passou a ganhar a linha fixa do link na WAHA, no Híbrido e no canal API (antes saía sem link).
- Limite do botão (`Notices::Button.fits?`): o corpo final que vai com o botão (linha de parar e, no teste, o prefixo
  incluídos) precisa caber nos 1024 caracteres do `cta_url`. Não cabendo, sai só texto, com a linha do link; senão o
  `RichMessages::SendGuard` deixaria a mensagem `failed` sem link nenhum.
- Envio assíncrono: o aviso fica `sent` quando a mensagem é criada; ela sai depois (`SendReplyJob`). Falha posterior
  (provedor ou `SendGuard`) é pega pelo `NoticeDispatchJob#fail_undelivered!` (até 2 h): o aviso vira
  `failed: delivery_failed` e o responsável é avisado. O convite de teste não tem essa conferência: a falha aparece na
  própria conversa, para quem testou.
- Prévia da tela (também a das opções da IA): texto sem `{{horario.link_gestao}}` mostra a linha do link (`manage_line` do
  `CustomTextSetup`) e, só com caixa de avisos `whatsapp_cloud` (`notice_channel`), a nota de que o link vai num botão.

## Conversa que conta

`Notices::Route#conversation`: a do convite se é desta caixa e deste contato; senão a mais recente do contato nesta
caixa (qualquer status). Sem conversa na caixa de avisos (o cliente falou em outra caixa), o `Delivery` abre uma nova
pelo modelo: janela desconhecida, sem botão.

## Fora deste passo

Modelo da Meta com botão de URL dinâmica (passo 2, com o chat Modelos WhatsApp) e o teste real nos números do Rodrigo.

## Ajustes decididos pelo Rodrigo (14/10/2026)

- Editor: o texto padrão (`CustomText.default_text`) vem sem `{{horario.link_gestao}}`; editar a partir dele mantém
  o botão (ou a linha fixa).
- IA: `prompts/whatsapp_texto.md` (só os avisos do agendamento usam este canal) manda não pôr link; o agendamento passa
  à IA `CustomText::AI_KEYS` (sem o link), então opção com o campo do link é descartada. `comum.md` e
  `whatsapp_campanha.md` não mudaram. Casos da bateria simulada reescritos sem o campo do link.
- Rótulo por tipo (`Notices::Button::LABELS`): aviso de reunião marcada "Ver meu horário"; convite para marcar
  ("Testar no meu WhatsApp") "Escolher horário" (en "Pick a time").
