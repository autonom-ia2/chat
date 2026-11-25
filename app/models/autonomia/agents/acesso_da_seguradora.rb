# == Schema Information
#
# Table name: autonomia_acessos_da_seguradora
#
#  id                 :bigint           not null, primary key
#  capacidades        :jsonb            not null
#  conferido_em       :datetime
#  estado             :string           default("nao_conferido"), not null
#  login              :text
#  login_dica         :string
#  motivo             :string
#  seguradora         :string           default("universal"), not null
#  senha              :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  autonomia_agent_id :bigint           not null
#
# Indexes
#
#  index_autonomia_acessos_da_seguradora_on_account_id          (account_id)
#  index_autonomia_acessos_da_seguradora_on_autonomia_agent_id  (autonomia_agent_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (autonomia_agent_id => autonomia_agents.id) ON DELETE => cascade
#
# O acesso do corretor à seguradora (#3211), um por agente. Login e senha ficam cifrados; a tela e o modelo só
# veem o `payload_publico`, que traz a dica do login e nunca o login nem a senha.
class Autonomia::Agents::AcessoDaSeguradora < ApplicationRecord
  self.table_name = 'autonomia_acessos_da_seguradora'

  ESTADOS = %w[nao_conferido ok recusado].freeze
  SEGURADORAS = %w[universal].freeze
  PONTOS_DA_DICA = '•••'.freeze
  LOGIN_CURTO = 4

  belongs_to :account
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id,
                     inverse_of: false

  # Incondicional, como Autonomia::Insurance::Connection: sem as chaves do cofre a validação abaixo impede a
  # escrita, então nunca existe linha em texto puro para o `encrypts` tropeçar.
  encrypts :login
  encrypts :senha

  validates :estado, inclusion: { in: ESTADOS }
  validates :seguradora, inclusion: { in: SEGURADORAS }
  validates :autonomia_agent_id, uniqueness: true
  validates :motivo, inclusion: { in: Autonomia::Seguradoras::Universal::Codigos::TODOS }, allow_nil: true
  validate :credenciais_exigem_cofre

  before_validation :derivar_login_dica, if: :login_changed?

  def ok?
    estado == 'ok'
  end

  def so_cotacao?
    capacidades.to_h['so_cotacao'] == true
  end

  def tarifa_acordo?
    capacidades.to_h['tarifa_acordo'] == true
  end

  def payload_publico
    { seguradora: seguradora, login_dica: login_dica, estado: estado, motivo: motivo,
      conferido_em: conferido_em, so_cotacao: so_cotacao? }
  end

  private

  def credenciais_exigem_cofre
    return if login.blank? && senha.blank?
    return if Chatwoot.encryption_configured?

    errors.add(:base, I18n.t('autonomia.insurance.errors.encryption_unavailable'))
  end

  def derivar_login_dica
    self.login_dica = if login.blank?
                        nil
                      elsif login.length > LOGIN_CURTO
                        "#{login.first(2)}•••#{login.last(2)}"
                      else
                        PONTOS_DA_DICA
                      end
  end
end
