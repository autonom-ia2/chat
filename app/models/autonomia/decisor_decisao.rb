# Uma resposta do Decisor (#858) sobre UMA mensagem de uma conversa, ou sobre um card num gatilho de etapa.
#
# A linha é única por (decisor, conversa, mensagem) — ou por (decisor, card, gatilho), na automação de
# etapa do CRM, onde não há mensagem: o gatilho é a marca daquela entrada ou saída de etapa. A segunda
# automação que pergunta a mesma coisa sobre o mesmo alvo reaproveita esta resposta, e o Jev é chamado uma vez só.
#
# `esperas` lista cada automação ({regra, indice} ou {etapa, execucao}) parada esperando a resposta chegar depois (dúvida
# resolvida pelo Guia ou por uma pessoa): todas retomam. `seguidas` lista as que já rodaram os passos
# seguintes, para que uma retomada repetida não mande a mesma mensagem duas vezes. `motivo` guarda só a
# justificativa curta, nunca a conversa.
#
# As trocas de status saem de UM lugar só, `reivindicar!`: o Guia e a pessoa podem responder o mesmo
# caso ao mesmo tempo, e só quem ganha a troca retoma a automação.
class Autonomia::DecisorDecisao < ApplicationRecord
  self.table_name = 'autonomia_decisor_decisoes'

  STATUSES = %w[decidida duvida decidida_pelo_guia esperando_pessoa resolvida vencida sem_cota sem_conteudo].freeze
  # Uma dúvida parada mais do que isto não retoma mais a automação: mover card ou mandar mensagem dias
  # depois agiria fora de hora.
  PRAZO_PESSOA = 2.days
  DECIDIDAS = %w[decidida decidida_pelo_guia resolvida].freeze
  PARADAS = %w[duvida esperando_pessoa].freeze

  belongs_to :decisor, class_name: 'Autonomia::Decisor', inverse_of: :decisoes
  belongs_to :account
  belongs_to :automation_rule, optional: true
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  belongs_to :card, class_name: 'Crm::Card', foreign_key: :crm_card_id, optional: true, inverse_of: false
  belongs_to :resolvida_por, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :message_id, uniqueness: { scope: [:decisor_id, :conversation_id] }, allow_nil: true
  validates :gatilho, uniqueness: { scope: [:decisor_id, :crm_card_id] }, allow_nil: true
  validate :com_alvo

  scope :esperando_pessoa, -> { where(status: 'esperando_pessoa') }

  def decidida?
    DECIDIDAS.include?(status)
  end

  def parada?
    PARADAS.include?(status)
  end

  def vencida_por_prazo?
    status == 'esperando_pessoa' && created_at < PRAZO_PESSOA.ago
  end

  # As três abaixo escrevem com `update_all` de propósito: a condição no WHERE é o que torna a troca
  # atômica. Os valores vêm das constantes acima, então não há validação a pular.
  # rubocop:disable Rails/SkipsModelValidations

  # Troca o status só se ele ainda for um dos que `estava`, numa única instrução SQL: entre duas trocas
  # ao mesmo tempo, uma ganha e a outra fica sabendo. -> true quando esta ganhou.
  def reivindicar!(estava:, **atributos)
    trocou = self.class.where(id: id, status: Array(estava)).update_all(atributos.merge(updated_at: Time.current)) == 1
    reload
    trocou
  end

  # A regra passa a esperar esta decisão, se ela ainda está parada. Quem troca o status lê `esperas`
  # DEPOIS da troca, e a inscrição só entra enquanto o status é de parada: as duas não se cruzam.
  # -> a decisão relida, decidida se a resposta chegou nesse meio-tempo.
  def aguardar!(marca)
    return self unless parada?

    espera = [marca].to_json
    self.class.where(id: id, status: PARADAS).where.not('esperas @> ?::jsonb', espera)
        .update_all(['esperas = esperas || ?::jsonb, updated_at = ?', espera, Time.current])
    reload
  end

  # Marca que a regra vai seguir depois desta decisão. -> false quando ela já tinha seguido: a
  # retomada chegou de novo (Guia e pessoa, retry do job) e os passos não podem rodar outra vez.
  def seguir!(marca)
    seguida = [marca].to_json
    self.class.where(id: id).where.not('seguidas @> ?::jsonb', seguida)
        .update_all(['seguidas = seguidas || ?::jsonb, updated_at = ?', seguida, Time.current]) == 1
  end
  # rubocop:enable Rails/SkipsModelValidations

  private

  def com_alvo
    errors.add(:base, 'needs a conversation or a card') if conversation_id.blank? && crm_card_id.blank?
  end
end
