# Lista "abriram o link e não marcaram" do painel de resultados (#1194, J7-A4, J8-A12).
#
# Entra o convite real (fora o de teste e o do link público) aberto no período, não agendado e não cancelado, de um
# cliente que não marcou depois por outro link. Um por cliente (o mais recente) e só de clientes que a pessoa vê
# (`ClientVisibility`). `user` presente = "Meus números": só os links que a pessoa criou.
#
# Cada linha diz se dá para "Enviar de novo" ali (`can_resend`: a conversa do convite, ou a principal do card, é
# uma que a pessoa vê) e quando o cliente recebeu um link depois de abrir (`resent_at`). Página de 20, até 50.
class Crm::BookingV2::OpenedNotBooked
  PER_PAGE = 20
  MAX_PAGE = 50
  NOT_BOOKED_LATER_SQL = <<~SQL.squish.freeze
    NOT EXISTS (
      SELECT 1 FROM crm_booking_invites booked
      WHERE booked.account_id = crm_booking_invites.account_id
        AND booked.contact_id = crm_booking_invites.contact_id
        AND booked.scheduled_at >= crm_booking_invites.first_opened_at
    )
  SQL

  def initialize(account:, visibility:, period: nil, user: nil, page: 1)
    @account = account
    @visibility = visibility
    @period = period
    @user = user
    @page = page.to_i.clamp(1, MAX_PAGE)
  end

  # Convites que a pessoa pode reenviar: os da lista, sem o corte de período.
  def candidates
    scope = visibility.apply(
      Crm::BookingInvite.real.where(account_id: account.id).where.not(channel: 'public')
                        .where.not(first_opened_at: nil).where(scheduled_at: nil, canceled_at: nil)
                        .where(NOT_BOOKED_LATER_SQL)
    )
    user ? scope.where(created_by_id: user.id) : scope
  end

  def rows
    invites = page_invites
    conversations = invites.to_h { |invite| [invite.id, resend_conversation(invite)] }
    visible_ids = visibility.visible_conversation_ids(conversations.values.map { |conversation| conversation&.id })
    resent = resent_at_by_contact(invites)

    invites.map { |invite| row(invite, conversations[invite.id], visible_ids, resent[invite.contact_id]) }
  end

  def meta
    { page: page, per_page: PER_PAGE, total: [latest.count, PER_PAGE * MAX_PAGE].min }
  end

  # A conversa onde o reenvio sai: a do convite ou, sem ela, a principal do card.
  def self.resend_conversation(invite)
    invite.conversation || invite.card&.primary_conversation
  end

  private

  attr_reader :account, :visibility, :period, :user, :page

  def resend_conversation(invite)
    self.class.resend_conversation(invite)
  end

  def in_period
    candidates.where(first_opened_at: period.range)
  end

  def latest
    in_period.where(id: in_period.group(:contact_id).select('MAX(crm_booking_invites.id)'))
  end

  def page_invites
    latest.includes(:contact, :booking_profile, :created_by, :conversation, card: :primary_conversation)
          .order(first_opened_at: :desc, id: :desc).offset((page - 1) * PER_PAGE).limit(PER_PAGE).to_a
  end

  def resent_at_by_contact(invites)
    return {} if invites.empty?

    Crm::BookingInvite.real.where(account_id: account.id, contact_id: invites.map(&:contact_id), canceled_at: nil)
                      .where.not(sent_at: nil).group(:contact_id).maximum(:sent_at)
  end

  def row(invite, conversation, visible_ids, last_sent_at)
    {
      id: invite.id, contact: { id: invite.contact.id, name: invite.contact.name },
      opened_at: invite.first_opened_at.iso8601, open_count: invite.open_count, sent_at: invite.sent_at&.iso8601,
      page: { id: invite.booking_profile.id, title: invite.booking_profile.title },
      sent_by: invite.created_by && { id: invite.created_by.id, name: invite.created_by.name },
      can_resend: conversation.present? && visible_ids.include?(conversation.id),
      resent_at: last_sent_at.present? && last_sent_at > invite.first_opened_at ? last_sent_at.iso8601 : nil
    }
  end
end
