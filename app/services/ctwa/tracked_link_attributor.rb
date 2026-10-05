class Ctwa::TrackedLinkAttributor
  CLICK_PATTERN = /#([A-Z2-9]{8})\b/
  CODE_PATTERN = /#([A-Z2-9]{6})\b/
  INFERRED_CLICK_WINDOW = 10.minutes
  # O aviso da página pode chegar depois da mensagem com #TOKEN: procura a mensagem até
  # este tempo antes do clique gravado.
  LATE_CLICK_WINDOW = 10.minutes

  def self.attribute!(conversation, message_content)
    new.attribute!(conversation, message_content)
  end

  def self.attribute_late_click!(click)
    new.attribute_late_click!(click)
  end

  def attribute!(conversation, message_content)
    return if conversation.blank? || message_content.blank?

    # Cheap regex gates FIRST: ordinary inbound messages must not pay attribution queries.
    content = message_content.to_s
    token = message_click_token(content)
    return attribute_click_token!(conversation, token) if token.present?

    code = content.match(CODE_PATTERN)&.[](1)
    return attribute_code!(conversation, code) if code.present?

    attribute_inferred_click!(conversation)
  end

  # Aviso gravado DEPOIS da mensagem que trazia o #TOKEN (rede lenta): a mensagem já passou
  # pelo atribuidor sem achar o clique. Procura essa mensagem na caixa do link e liga.
  def attribute_late_click!(click)
    return if click.blank? || click.conversation_id.present?

    message = late_click_message(click)
    return if message.blank? || message_click_token(message.content) != click.token

    attribute_click!(message.conversation, click)
  end

  private

  def message_click_token(content)
    content.to_s.match(CLICK_PATTERN)&.[](1)
  end

  def late_click_message(click)
    link = click.tracked_link
    return if link.blank?

    # Janela fechada nas duas pontas (mensagem posterior ao clique já passa pelo atribuidor
    # normal; a folga cobre a corrida entre os dois) e LIMIT 1: o LIKE só filtra as mensagens
    # da janela, lidas por faixa do índice de created_at, nunca a caixa inteira.
    # reorder: Message tem default_scope por created_at ASC, que venceria um `order` somado.
    # A primeira mensagem com o token é a de quem clicou (cópia encaminhada vem depois).
    Message.incoming
           .where(account_id: click.account_id, inbox_id: link.inbox_id)
           .where(created_at: (click.created_at - LATE_CLICK_WINDOW)..(click.created_at + LATE_CLICK_WINDOW))
           .where('messages.content LIKE ?', "%##{Message.sanitize_sql_like(click.token)}%")
           .reorder(created_at: :asc)
           .first
  end

  # O marcador (#CODIGO ou #TOKEN) e intencao explicita: veio do texto pre-preenchido do link.
  # Nao exigimos que seja a primeira mensagem da conversa — contato recorrente que clica num
  # link novo tem de ser atribuido igual. Reenvio do mesmo marcador e no-op: o CampaignBuilder
  # deduplica por source_id e so entao incrementamos o contador do link.
  def attribute_code!(conversation, code)
    # O codigo tem de pertencer a inbox em que a mensagem chegou: colar o marcador de um link
    # de outra inbox da mesma conta nao pode atribuir a conversa a ele.
    link = Ctwa::TrackedLink.for_account(conversation.account).find_by(code: code, inbox_id: conversation.inbox_id)
    return if link.blank?

    already_counted = conversation_already_on_link?(conversation, link)

    # CampaignBuilder derives `source` as meta_organic without ctwa_clid. For MVP the
    # canonical discriminator for trackable links is `source_type: tracked_link`.
    attributed = Ctwa::CampaignBuilder.attribute!(
      conversation,
      source_id: "link:#{code}",
      source_type: 'tracked_link',
      headline: link.name
    )
    return unless attributed

    link.increment!(:conversations_count) unless already_counted # rubocop:disable Rails/SkipsModelValidations
  end

  def attribute_click_token!(conversation, token)
    click = Ctwa::TrackedLinkClick.active
                                  .joins(:tracked_link)
                                  .includes(:tracked_link)
                                  .find_by(
                                    account_id: conversation.account_id,
                                    token: token,
                                    ctwa_tracked_links: { inbox_id: conversation.inbox_id }
                                  )
    return if click.blank?

    attribute_click!(conversation, click)
  end

  def attribute_inferred_click!(conversation)
    return unless eligible_for_inferred_click?(conversation)

    # Memory gates above guarantee only the webhook cycle that created the conversation
    # reaches these queries, so ordinary inbound traffic pays none of them.
    scope = inferred_click_scope(conversation)
    return unless scope.exists?

    clicks = scope.limit(2).to_a
    return unless clicks.one?

    attribute_click!(conversation, clicks.first, inferred: true)
  end

  def attribute_click!(conversation, click, inferred: false)
    return unless claim_click!(conversation, click, inferred)

    link = click.tracked_link
    return if link.blank?

    already_counted = conversation_already_on_link?(conversation, link, except_click_id: click.id)

    referral = click.params.to_h.merge(click_referral(link, click))
    referral[:inferred] = true if inferred

    attributed = Ctwa::CampaignBuilder.attribute!(
      conversation,
      referral.compact
    )
    store_lead_form!(conversation, link, click) unless inferred
    return unless attributed

    link.increment!(:conversations_count) unless already_counted # rubocop:disable Rails/SkipsModelValidations
  end

  # Inferido (sem #TOKEN) não prova que o autor da conversa é quem clicou: liga a conversa
  # (CA-1.5), mas apaga o formulário e os sinais da Meta do clique, para o card não mostrar
  # dado de outra pessoa nem o CAPI mandar sinal dela.
  def claim_click!(conversation, click, inferred)
    claim = { conversation_id: conversation.id }
    claim = claim.merge(Ctwa::TrackedLinkClick::PERSONAL_DATA_RESET) if inferred
    Ctwa::TrackedLinkClick.active.where(id: click.id).update_all(claim) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  # Link de QR: um toque por clique. Link de página (#1011): um toque por CAMPANHA, para o
  # filtro de campanha do CRM agrupar os cliques dela e o segundo clique da mesma campanha
  # na mesma conversa não duplicar o toque.
  def click_referral(link, click)
    return { source_id: "click:#{click.token}", source_type: 'bridge', headline: link.name } unless link.website?

    campaign_key = click.campaign_key.presence || Ctwa::TrackedLinkClick::NO_CAMPAIGN_KEY
    utm_campaign = click.params.to_h['utm_campaign'].presence
    {
      source_id: "site:#{link.code}:#{campaign_key}",
      source_type: 'bridge',
      headline: [link.name, utm_campaign].compact.join(' · '),
      source_url: click.page_url.presence
    }
  end

  # O formulário da página é a fonte da verdade do card (não o texto que o cliente
  # editou antes de mandar). O mais recente vence; as outras chaves da conversa ficam.
  # Só link de página: o QR não tem formulário.
  def store_lead_form!(conversation, link, click)
    return unless link.website?

    fields = click.lead_data.to_h['fields']
    return if fields.blank?

    lead_form = { 'link_code' => link.code, 'fields' => fields, 'captured_at' => click.created_at.utc.iso8601 }
    # reload: descarta o display_id em memória, que o with_lock recusaria como mudança pendente.
    conversation.reload.with_lock do
      conversation.update!(additional_attributes: conversation.additional_attributes.to_h.merge('lead_form' => lead_form))
    end
    Crm::Cards::RebroadcastConversationCardsJob.perform_later(conversation.id) if Crm::Config.enabled?
  end

  # conversations_count conta CONVERSAS, nao toques. Um segundo clique no mesmo link, na mesma
  # conversa, gera outro source_id e seria contado de novo — o que antes nao acontecia so porque
  # o portao de primeira mensagem barrava o segundo toque.
  def conversation_already_on_link?(conversation, link, except_click_id: nil)
    touches = Ctwa::CampaignBuilder.existing_touches(conversation)
    return true if touches.any? { |touch| touch['source_id'] == "link:#{link.code}" }

    scope = Ctwa::TrackedLinkClick.where(tracked_link_id: link.id, conversation_id: conversation.id)
    scope = scope.where.not(id: except_click_id) if except_click_id
    scope.exists?
  end

  def inferred_click_scope(conversation)
    Ctwa::TrackedLinkClick.active
                          .joins(:tracked_link)
                          .includes(:tracked_link)
                          .where(account_id: conversation.account_id, ctwa_tracked_links: { inbox_id: conversation.inbox_id })
                          .where('ctwa_tracked_link_clicks.created_at >= ?', INFERRED_CLICK_WINDOW.ago)
                          .order(created_at: :desc)
  end

  def eligible_for_inferred_click?(conversation)
    return false if conversation.campaign_id.present? || conversation.additional_attributes.to_h['campaign'].present?
    # In-memory stand-in for "first inbound message": only the process that just built the
    # conversation sees previously_new_record? true, so existing conversations exit here
    # without paying any query on the webhook hot path.
    return false unless conversation.previously_new_record?
    return false if conversation.created_at < INFERRED_CLICK_WINDOW.ago

    true
  end
end
