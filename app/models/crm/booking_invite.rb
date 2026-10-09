# Link por cliente do agendamento (#1190, F1-C). Um convite é a CAPACIDADE de acesso de um contato a uma página
# nova (e, depois de agendado, à reunião): quem abre `/b/<code>` vê a página já sabendo quem é, sem e-mail nem
# verificação (J1-A2). O código é curto, opaco e sem caracteres que se confundem ao ler em voz alta (J1-A9).
#
# Tudo que o convite aponta (perfil, link individual, contato, card, conversa, reunião, autor) tem de ser da mesma
# conta; conversa e card têm de ser do mesmo contato. Sem isso um id de outra conta viraria acesso cruzado.
class Crm::BookingInvite < ApplicationRecord
  self.table_name = 'crm_booking_invites'

  # Sem 0/O/o, 1/l/I: quem lê o link em voz alta ou digita de um print não erra.
  CODE_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz'.chars.freeze
  CODE_LENGTH = 8
  CHANNELS = %w[conversation copy ai public].freeze
  # Depois de virar reunião, o mesmo link serve para gerir a reunião até 1 dia depois do fim dela (J5-A2).
  MANAGE_GRACE = 1.day

  belongs_to :account
  belongs_to :booking_profile, class_name: 'Crm::AgentBookingProfile'
  belongs_to :booking_link, class_name: 'Crm::AgentBookingLink', optional: true
  belongs_to :contact
  belongs_to :card, class_name: 'Crm::Card', optional: true
  belongs_to :conversation, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :meeting, class_name: 'Crm::Meeting', optional: true

  before_validation :assign_code, on: :create

  validates :code, presence: true, uniqueness: true, length: { is: CODE_LENGTH }
  validates :channel, inclusion: { in: CHANNELS }
  validates :expires_at, presence: true
  validates :metadata, jsonb_attributes_length: true
  validate :records_must_belong_to_account
  validate :records_must_belong_to_contact

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def self.generate_code
    Array.new(CODE_LENGTH) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.size)] }.join
  end

  def self.base_url
    ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
  end

  # Estado do convite, do mais forte para o mais fraco: cancelado vence tudo; agendado vence a validade (o link
  # passa a ser o de gestão da reunião); depois vencido, aberto, enviado e criado.
  def state
    return 'canceled' if canceled_at.present?
    return 'scheduled' if scheduled_at.present?
    return 'expired' if expired?
    return 'opened' if first_opened_at.present?
    return 'sent' if sent_at.present?

    'created'
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # Ainda dá acesso: não foi cancelado e, se não virou reunião, está dentro da validade; se virou, até 1 dia depois
  # do fim da reunião.
  def active?
    return false if canceled_at.present?
    return !expired? if scheduled_at.blank?

    meeting.present? && meeting.ends_at + MANAGE_GRACE > Time.current
  end

  def url
    "#{self.class.base_url}/b/#{code}"
  end

  private

  # Sorteia de novo enquanto colidir com um código existente (o índice único segura a corrida rara entre dois
  # sorteios iguais ao mesmo tempo).
  def assign_code
    return if code.present?

    self.code = self.class.generate_code
    self.code = self.class.generate_code while self.class.exists?(code: code)
  end

  def records_must_belong_to_account
    return if account_id.blank?

    { booking_profile: booking_profile, booking_link: booking_link, contact: contact, card: card,
      conversation: conversation, meeting: meeting }.each do |name, record|
      errors.add(name, 'must belong to the same account') if record.present? && record.account_id != account_id
    end
    errors.add(:created_by, 'must belong to the same account') if created_by_id.present? && !account.users.exists?(id: created_by_id)
  end

  def records_must_belong_to_contact
    errors.add(:conversation, 'must belong to the same contact') if conversation.present? && conversation.contact_id != contact_id
    errors.add(:card, 'must belong to the same contact') if card.present? && card.contact_id != contact_id
    return if booking_link.blank? || booking_link.booking_profile_id == booking_profile_id

    errors.add(:booking_link, 'must belong to the same booking page')
  end
end
