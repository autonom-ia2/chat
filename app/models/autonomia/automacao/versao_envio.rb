# #3099 (F3 do épico #3095): qual das duas versões de um passo "mensagem" cada execução mandou. Uma linha por envio que
# saiu (o passo que pulou não conta). Quem escreve é Autonomia::Automacao::DuasVersoes::Envio; quem lê são os números do
# teste (DuasVersoes::Numeros), contados desde o `teste_desde` da vencedora do passo.
class Autonomia::Automacao::VersaoEnvio < ApplicationRecord
  self.table_name = 'autonomia_automacao_versoes_envios'

  belongs_to :account
  belongs_to :automacao, class_name: 'Autonomia::Automacao::Definicao'
  belongs_to :execucao, class_name: 'Autonomia::Automacao::Execucao', optional: true
  belongs_to :contact, optional: true

  validates :passo, :alvo_type, :alvo_id, presence: true
  validates :versao, inclusion: { in: CampaignJourney::DuasVersoes::VERSOES }
  validate :da_mesma_conta

  scope :do_passo, ->(automacao_id, passo) { where(automacao_id: automacao_id, passo: passo) }

  private

  def da_mesma_conta
    errors.add(:automacao, :invalid) if automacao && automacao.account_id != account_id
  end
end
