# Cria o link por cliente (#1190, J1-A1/A8/A9). Recebe em `client` o card, a conversa e o contato JÁ autorizados
# pelo controller (quem chama confere que a pessoa vê o cliente); aqui só se decide página, link individual,
# contato e validade.
#
# Página: a pedida (tem de estar entre as publicadas e utilizáveis da conta) ou, sem pedido, a página em que a
# pessoa atende; senão a primeira publicada. Sem página utilizável: ArgumentError 'no_page'. Dados que não fecham
# (conversa ou card de outro contato, nenhum contato): ArgumentError 'invite_invalid'.
class Crm::BookingV2::InviteCreator
  def initialize(account:, user:, page_id: nil, client: {})
    @account = account
    @user = user
    @page_id = page_id
    @card = client[:card]
    @conversation = client[:conversation]
    @contact = client[:contact]
  end

  # Mesma pessoa, mesmo contato: um convite ATIVO (não agendado, não vencido, não cancelado) da mesma página é
  # devolvido como está (`reused?` verdadeiro), para o cliente não receber dois links. Pedido de outra página
  # cancela os ativos anteriores da pessoa para o contato e cria o novo.
  def perform
    page = choose_page
    raise Crm::BookingV2::InviteError, 'no_page' if page.blank?

    contact = resolved_contact
    ActiveRecord::Base.transaction do
      existing = pending_invites(contact).lock.to_a
      @reused = existing.find { |invite| invite.booking_profile_id == page.id }
      next @reused if @reused

      existing.each { |invite| Crm::BookingV2::InviteCanceler.new(invite).perform }
      build(page, contact).tap(&:save!)
    end
  rescue ActiveRecord::RecordInvalid
    raise Crm::BookingV2::InviteError, 'invite_invalid'
  end

  def reused?
    @reused.present?
  end

  private

  attr_reader :account, :user, :page_id, :card, :conversation

  def pending_invites(contact)
    Crm::BookingInvite.where(account_id: account.id, contact_id: contact.id, created_by_id: user.id,
                             canceled_at: nil, scheduled_at: nil)
                      .where('expires_at > ?', Time.current).order(:id)
  end

  def pages
    @pages ||= Crm::BookingV2::InvitePages.new(account)
  end

  def choose_page
    return pages.default_for(user) if page_id.blank?

    pages.usable.find { |page| page.id == page_id.to_i }
  end

  def build(page, contact)
    Crm::BookingInvite.new(
      account: account, booking_profile: page, booking_link: pages.link_for(page, user), contact: contact,
      card: card, conversation: conversation, created_by: user,
      channel: conversation.present? ? 'conversation' : 'copy', expires_at: page.invite_ttl_days.days.from_now
    )
  end

  # O contato vem do card, depois da conversa, depois do informado. Tudo que veio junto tem de ser desse contato:
  # conferido aqui (e não só na validação do modelo) porque o convite ativo reaproveitado não passa por ela.
  def resolved_contact
    contact = card&.contact || conversation&.contact || @contact
    raise Crm::BookingV2::InviteError, 'invite_invalid' unless contact.present? && same_contact?(contact)

    contact
  end

  def same_contact?(contact)
    [card&.contact_id, conversation&.contact_id, @contact&.id].compact.all?(contact.id)
  end
end
