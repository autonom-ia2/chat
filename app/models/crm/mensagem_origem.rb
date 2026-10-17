# Quem escreveu uma mensagem e se ela chegou ao cliente (#1601), calculado pelo código (Crm::Memoria::Origem), nunca
# pelo modelo. Uma linha por mensagem. `corrigido_por_user_id`: uma pessoa corrigiu a autoria; o código não a regrava.
class Crm::MensagemOrigem < ApplicationRecord
  self.table_name = 'crm_mensagem_origens'

  AUTORES = %w[cliente pessoa_painel pessoa_celular ia_nossa follow_up_nosso robo_externo sistema desconhecido].freeze
  # Quem é da equipe de verdade (ver #resposta_da_pessoa?).
  PESSOAS = %w[pessoa_painel pessoa_celular].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :contact

  validates :autor_tipo, inclusion: { in: AUTORES }
  validates :message_id, :regra, :classificador_versao, presence: true

  # Não vale como prova de fato nem como fala no bilhete. A encaminhada pode ser fala de outro cliente (#1702b).
  def descartavel?
    duplicata_de_message_id.present? || indisponivel? || sem_conteudo? || encaminhada?
  end

  # Uma pessoa da equipe respondeu ao cliente de verdade: pelo painel ou pelo celular, pública, não falhou e não é
  # encaminhamento (#1702b). Nota privada e envio que falhou nunca contam.
  def resposta_da_pessoa?
    PESSOAS.include?(autor_tipo) && foi_ao_cliente? && !encaminhada?
  end
end
