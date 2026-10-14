# "Parar avisos" de um contato (#1192, J5-A7/J2-A9/RA-18): enquanto a linha existir, nenhuma mensagem automática do
# agendamento sai para ele, em reunião nenhuma (as próximas também). Uma por contato e conta: o índice único segura
# (sem validação de unicidade no modelo, para `create_or_find_by!` resolver a corrida de dois toques ao mesmo tempo).
class Crm::BookingNoticeStop < ApplicationRecord
  self.table_name = 'crm_booking_notice_stops'

  belongs_to :account
  belongs_to :contact

  validate :contact_must_belong_to_account

  def self.stopped?(account_id:, contact_id:)
    contact_id.present? && exists?(account_id: account_id, contact_id: contact_id)
  end

  private

  def contact_must_belong_to_account
    errors.add(:contact, 'must belong to the same account') if contact.present? && contact.account_id != account_id
  end
end
