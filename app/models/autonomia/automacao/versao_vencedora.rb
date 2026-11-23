# #3099 (F3 do épico #3095): o teste das duas versões de um passo "mensagem" de uma automação. Uma linha por automação e
# passo (índice único).
#
# - `teste_desde`: quando o teste (re)começou. Os números contam só os envios daqui em diante. Mudar o texto ou o modelo
#   de uma das versões, ou ligar as duas versões, grava agora e zera a vencedora (DuasVersoes.versao_salva!);
# - `vencedora`: a versão que fica para todos (1 ou 2), nil enquanto testa;
# - `escolhida_por`: 'sistema' (a melhor pela régua), 'empate' (parecidas ou poucas respostas: a versão 1) ou 'voce'
#   (alguém com automation_manage escolheu, `escolhida_por_user_id`).
class Autonomia::Automacao::VersaoVencedora < ApplicationRecord
  self.table_name = 'autonomia_automacao_versoes_vencedoras'

  belongs_to :account
  belongs_to :automacao, class_name: 'Autonomia::Automacao::Definicao'
  belongs_to :escolhida_por_user, class_name: 'User', optional: true

  validates :passo, presence: true, uniqueness: { scope: :automacao_id }
  validates :teste_desde, presence: true
  validates :vencedora, inclusion: { in: CampaignJourney::DuasVersoes::VERSOES }, allow_nil: true
  validates :escolhida_por, inclusion: { in: CampaignJourney::DuasVersoes::ESCOLHIDA_POR }, allow_nil: true
  validate :da_mesma_conta

  scope :testando, -> { where(vencedora: nil) }

  def escolhida? = vencedora.present?

  private

  def da_mesma_conta
    errors.add(:automacao, :invalid) if automacao && automacao.account_id != account_id
  end
end
