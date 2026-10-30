class ContactMergeAction
  include Events::Types
  pattr_initialize [:account!, :base_contact!, :mergee_contact!]

  # chat#713: da origem de recusa mais firme para a mais fraca, na mescla de dois contatos que recusaram. A que perde não se
  # apaga de vez: os cards do absorvido passam para o que fica (merge_crm_cards), e desfeita a que ficou, release_opt_out!
  # passa a recusa para o card marcado no follow-up, o e-mail descadastrado ou o lead recusado que ainda valem, nesta
  # mesma ordem (Contacts::OptOutInheritance#source_for, chat#1325). Uma origem por linha.
  OPT_OUT_PRECEDENCE = %w[
    manual
    follow_up_reply
    campaign_reply
    email_unsubscribe
    prospecting
  ].freeze

  def perform
    # This case happens when an agent updates a contact email in dashboard,
    # while the contact also update his email via email collect box
    return @base_contact if base_contact.id == mergee_contact.id

    ActiveRecord::Base.transaction do
      validate_contacts
      merge_conversations
      merge_messages
      merge_contact_inboxes
      merge_contact_notes
      merge_calls
      merge_prospecting_leads
      merge_crm_records
      merge_and_remove_mergee_contact
    end
    @base_contact
  end

  private

  def validate_contacts
    return if belongs_to_account?(@base_contact) && belongs_to_account?(@mergee_contact)

    raise StandardError, 'contact does not belong to the account'
  end

  def belongs_to_account?(contact)
    @account.id == contact.account_id
  end

  def merge_conversations
    Conversation.where(contact_id: @mergee_contact.id).update(contact_id: @base_contact.id)
  end

  def merge_contact_notes
    Note.where(contact_id: @mergee_contact.id, account_id: @mergee_contact.account_id).update(contact_id: @base_contact.id)
  end

  def merge_messages
    Message.where(sender: @mergee_contact).update(sender: @base_contact)
  end

  def merge_contact_inboxes
    ContactInbox.where(contact_id: @mergee_contact.id).update(contact_id: @base_contact.id)
  end

  def merge_calls
    # overridden in enterprise/app/actions/enterprise/contact_merge_action.rb
  end

  # chat#713: o lead da Prospecção é o que sustenta a recusa de origem 'prospecting' no contato. Sem isto a FK anularia o
  # contact_id ao apagar o absorvido, e a recusa herdada ficaria sem lead que a sustente.
  def merge_prospecting_leads
    Autonomia::Prospecting::Lead.where(account_id: @account.id, contact_id: @mergee_contact.id)
                                .update_all(contact_id: @base_contact.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # O contato absorvido é apagado logo depois. Sem isto, os cards ficariam sem contato (o Rails anula o vínculo) e os
  # follow-ups e convidados de reunião seriam apagados em cascata pelo banco.
  def merge_crm_records
    merge_crm_cards
    merge_crm_follow_ups
    merge_crm_meeting_guests
    merge_crm_booking_invites
    merge_crm_booking_notice_stops
    merge_crm_memoria
  end

  # #1601 (C1): a memória das IAs do absorvido passa para o que fica antes do destroy!, que a apagaria em cascata.
  def merge_crm_memoria
    Crm::Memoria::Mescla.mesclar!(account: @account, absorvido: @mergee_contact, fica: @base_contact)
  end

  # #1192: "parar avisos" é da pessoa. Se só o absorvido tinha parado, a parada passa para o que fica; se os dois
  # tinham, fica a do que fica (único por conta e contato) e a do absorvido some com ele.
  def merge_crm_booking_notice_stops
    stops = Crm::BookingNoticeStop.where(account_id: @account.id, contact_id: @mergee_contact.id)
    return stops.delete_all if Crm::BookingNoticeStop.stopped?(account_id: @account.id, contact_id: @base_contact.id)

    stops.update_all(contact_id: @base_contact.id) # rubocop:disable Rails/SkipsModelValidations
  end

  # #1190: o link por cliente é do contato; sem isto a FK em cascata apagaria os convites do absorvido.
  def merge_crm_booking_invites
    Crm::BookingInvite.where(account_id: @account.id, contact_id: @mergee_contact.id)
                      .update_all(contact_id: @base_contact.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def merge_crm_cards
    Crm::Card.where(account_id: @account.id, contact_id: @mergee_contact.id)
             .update_all(contact_id: @base_contact.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    # chat#1325: o pedido de parar no follow-up marcado para o absorvido continua provando a recusa do que fica.
    Crm::FollowUps::CardOptOut.transfer_marks!(account: @account, from: @mergee_contact, to: @base_contact)
  end

  def merge_crm_follow_ups
    Crm::FollowUp.where(account_id: @account.id, contact_id: @mergee_contact.id)
                 .update_all(contact_id: @base_contact.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # Quem já é convidado da reunião pelo contato que fica não precisa de um segundo convite: o do absorvido some com ele.
  def merge_crm_meeting_guests
    base_meeting_ids = Crm::MeetingGuest.where(account_id: @account.id, contact_id: @base_contact.id).select(:meeting_id)
    Crm::MeetingGuest.where(account_id: @account.id, contact_id: @mergee_contact.id)
                     .where.not(meeting_id: base_meeting_ids)
                     .update_all(contact_id: @base_contact.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def merge_and_remove_mergee_contact
    [@base_contact, @mergee_contact].sort_by(&:id).each(&:lock!)
    mergable_attribute_keys = %w[identifier name email phone_number additional_attributes custom_attributes]
    base_contact_attributes = base_contact.attributes.slice(*mergable_attribute_keys).compact_blank
    mergee_contact_attributes = mergee_contact.attributes.slice(*mergable_attribute_keys).compact_blank

    # attributes in base contact are given preference
    merged_attributes = mergee_contact_attributes.deep_merge(base_contact_attributes)
    @mergee_contact.reload
    merged_attributes = merged_attributes.merge(inherited_attributes)

    @mergee_contact.destroy!
    Rails.configuration.dispatcher.dispatch(CONTACT_MERGED, Time.zone.now, contact: @base_contact,
                                                                           tokens: [@base_contact.contact_inboxes.filter_map(&:pubsub_token)])
    atualizar_contato_que_fica(merged_attributes)
  end

  # #1601: copiar os atributos do absorvido não é correção de uma pessoa na memória das IAs.
  def atualizar_contato_que_fica(merged_attributes)
    Crm::Memoria::Correcao.sem_correcao(@base_contact) { @base_contact.update!(merged_attributes) }
  end

  # #1144: cliente é da pessoa. Se um dos dois já era cliente, o que fica é cliente, com a data mais antiga.
  # O que é da pessoa e passa do absorvido para o que fica: a recusa de mensagens, ser cliente e a marca "Este contato é".
  def inherited_attributes
    inherited_opt_out.merge(inherited_customer).merge(inherited_relacao)
  end

  def inherited_customer
    customers = [@base_contact, @mergee_contact].select(&:customer?)
    return {} if customers.empty?

    { 'contact_type' => 'customer', 'customer_since' => customers.filter_map(&:customer_since).min }
  end

  # #2084: "Este contato é" foi marcado por uma pessoa. Se o contato que fica é interessado (o padrão) e o absorvido
  # foi marcado parceiro ou não é negócio, a marca passa para o que fica, junto com os cards dele. Se os dois foram
  # marcados, vale a do que fica.
  def inherited_relacao
    return {} unless @base_contact.relacao_interessado? && !@mergee_contact.relacao_interessado?

    { 'relacao' => @mergee_contact.relacao }
  end

  # chat#713: a recusa de mensagens ativas é da pessoa. Se só o contato absorvido tinha recusado, a recusa (data, origem
  # e autor) passa para o que fica. Se os dois recusaram, fica a origem mais firme (OPT_OUT_PRECEDENCE: a manual, o pedido
  # de parar no follow-up, o pedido de parar na resposta a campanha (#1449), o descadastro de e-mail e, por último, a da
  # Prospecção, que o "Desfazer" do lead solta sozinho) e a data mais antiga. Assim a mescla não apaga uma recusa manual atrás de uma da Prospecção.
  def inherited_opt_out
    return {} unless @mergee_contact.opted_out?
    return opt_out_attributes(@mergee_contact) unless @base_contact.opted_out?

    kept = opt_out_rank(@mergee_contact) < opt_out_rank(@base_contact) ? @mergee_contact : @base_contact
    opt_out_attributes(kept).merge('opted_out_at' => [@base_contact.opted_out_at, @mergee_contact.opted_out_at].min)
  end

  def opt_out_attributes(contact)
    contact.attributes.slice('opted_out_at', 'opt_out_source', 'opted_out_by_id')
  end

  def opt_out_rank(contact)
    OPT_OUT_PRECEDENCE.index(contact.opt_out_source) || OPT_OUT_PRECEDENCE.size
  end
end

ContactMergeAction.prepend_mod_with('ContactMergeAction')
