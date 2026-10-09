# "Testar no meu WhatsApp" (#1192, J3-A11): manda ao número que o admin informou, pela caixa de avisos da página,
# um link igual ao que o cliente recebe (um convite de verdade, que abre a página e marca de verdade).
#
# O convite de teste leva `metadata.test = true`: fica fora da lista do botão Agendar, do reaproveitamento de
# convites e dos números (F2-C usa `Crm::BookingInvite.real`); a reunião marcada por ele também leva `test: true`
# (`Crm::Meeting.real` a exclui). Vale a mesma regra de canal dos avisos (`Notices::Route`, só texto: fora da janela
# do WhatsApp oficial é preciso mandar uma mensagem ao número da empresa antes), a mesma parada (recusou mensagens
# ou parou os avisos) e o mesmo teto por número.
#
# Quem testa precisa enxergar a caixa de avisos (`policy_scope(::Inbox)`, o mesmo escopo da escolha da caixa) e, se a
# mensagem vai para uma conversa que já existe, poder responder nela (`ConversationPolicy#show?`, o mesmo critério do
# envio de mensagem do painel). Tudo é decidido antes de gravar: recusa não cria contato nem convite.
#
# Recusas (`Refused`, com `reason` quando é do canal): notice_inbox_missing, notice_inbox_forbidden (reason
# `conversation_forbidden` quando é a conversa), page_not_published, invalid_phone, cannot_send.
class Crm::BookingV2::TestInvite
  class Refused < StandardError
    attr_reader :reason

    def initialize(code, reason = nil)
      super(code)
      @reason = reason
    end
  end

  # user_context: o `pundit_user` do controller ({ user:, account:, account_user: }).
  def initialize(page:, user_context:, phone:)
    @page = page
    @user_context = user_context
    @user = user_context[:user]
    @raw_phone = phone
  end

  def perform
    validate!
    contact = Crm::BookingV2::PhoneLookup.find_contact(account: page.account, e164: phone) ||
              page.account.contacts.new(name: user.name, phone_number: phone)
    decision = Crm::BookingV2::Notices::Route.new(inbox: page.notice_inbox, contact: contact).decide
    ensure_can_send!(contact, decision)
    contact.save! if contact.new_record?
    send_invite!(contact, decision)
  end

  private

  attr_reader :page, :user, :user_context

  def validate!
    raise Refused, 'notice_inbox_missing' unless page.notices_usable?
    raise Refused, 'notice_inbox_forbidden' unless Pundit.policy_scope!(user_context, ::Inbox).exists?(id: page.notice_inbox_id)
    raise Refused, 'page_not_published' unless pages.usable?(page)
    raise Refused, 'invalid_phone' if phone.blank?
  end

  def ensure_can_send!(contact, decision)
    raise Refused.new('cannot_send', 'stopped') if stopped?(contact)
    raise Refused.new('cannot_send', decision.reason) unless decision.send?
    raise Refused.new('notice_inbox_forbidden', 'conversation_forbidden') unless can_reply?(decision.conversation)
    raise Refused.new('cannot_send', 'number_cap') if number_capped?(contact)
  end

  def stopped?(contact)
    contact.opted_out? || Crm::BookingNoticeStop.stopped?(account_id: page.account_id, contact_id: contact.id)
  end

  def can_reply?(conversation)
    conversation.nil? || Pundit.policy!(user_context, conversation).show?
  end

  def pages
    @pages ||= Crm::BookingV2::InvitePages.new(page.account)
  end

  def phone
    @phone ||= Crm::BookingV2::PhoneLookup.normalize(@raw_phone, region: Crm::BookingV2::PhoneLookup.region_for(page.resolved_timezone))
  end

  def number_capped?(contact)
    Crm::BookingV2::Notices::Sender.recent_for_contact(contact) >= Crm::BookingV2::Notices::Sender::NUMBER_LIMIT
  end

  def send_invite!(contact, decision)
    ActiveRecord::Base.transaction do
      invite = Crm::BookingInvite.create!(
        account: page.account, booking_profile: page, booking_link: pages.link_for(page, user), contact: contact, created_by: user,
        channel: 'copy', expires_at: page.invite_ttl_days.days.from_now, metadata: { 'test' => true }
      )
      Crm::BookingV2::Notices::Delivery.new(decision: decision, inbox: page.notice_inbox, contact: contact, sender: user,
                                            content: content(invite)).perform
      invite.update!(sent_at: Time.current)
    end
  end

  def content(invite)
    prefix = I18n.t('crm.booking_v2.notices.test_prefix', locale: Crm::BookingV2::Notices::Text.locale(page.account))
    "#{prefix}\n\n#{Crm::BookingV2::InviteText.new(invite)}"
  end
end
