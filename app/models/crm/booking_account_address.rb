# Endereço da conta no link de agendamento (#1299): o `<conta>` de `/a/<conta>/<página>`. As regras moram em
# `Crm::BookingV2::AccountAddress`; os dois índices únicos garantem um endereço por conta e um dono por endereço.
# == Schema Information
#
# Table name: crm_booking_account_addresses
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_crm_booking_account_addresses_on_account_id  (account_id) UNIQUE
#  index_crm_booking_account_addresses_on_name        (name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::BookingAccountAddress < ApplicationRecord
  self.table_name = 'crm_booking_account_addresses'

  belongs_to :account

  before_validation :normalize_name
  validates :account_id, uniqueness: true
  validate :name_must_be_usable

  private

  def normalize_name
    self.name = ::Crm::BookingV2::ShortName.normalize(name)
  end

  def name_must_be_usable
    problem = ::Crm::BookingV2::AccountAddress.problem(name, account_id: account_id)
    errors.add(:name, problem) if problem
  end
end
