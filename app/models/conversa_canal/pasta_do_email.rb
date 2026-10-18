# == Schema Information
#
# Table name: conversa_canal_pastas_do_email
#
#  id              :bigint           not null, primary key
#  pasta           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  user_id         :bigint
#
# Indexes
#
#  index_conversa_canal_pastas_do_email_on_account_id_and_pasta  (account_id,pasta)
#  index_conversa_canal_pastas_do_email_on_conversation_id       (conversation_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#
# Conversa de e-mail fora da Entrada (#1809): no Spam ou na Lixeira do painel. Sem linha, a conversa está na Entrada.
class ConversaCanal::PastaDoEmail < ApplicationRecord
  self.table_name = 'conversa_canal_pastas_do_email'
  PASTAS = %w[spam lixeira].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :user, optional: true

  validates :pasta, inclusion: { in: PASTAS }
  validates :conversation_id, uniqueness: true
end
