# Uma resposta do Decisor (#858) sobre UMA mensagem de uma conversa.
#
# A linha é única por (decisor, conversa, mensagem): a segunda regra que pergunta a mesma coisa sobre
# a mesma mensagem reaproveita esta resposta, e o Jev é chamado uma vez só.
#
# `esperas` lista cada regra ({regra, indice}) parada esperando a resposta chegar depois (dúvida
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
  belongs_to :conversation
  belongs_to :message
  belongs_to :resolvida_por, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :message_id, uniqueness: { scope: [:decisor_id, :conversation_id] }

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
  def aguardar!(regra_id, indice)
    return self unless parada?

    espera = [{ 'regra' => regra_id, 'indice' => indice }].to_json
    self.class.where(id: id, status: PARADAS).where.not('esperas @> ?::jsonb', espera)
        .update_all(['esperas = esperas || ?::jsonb, updated_at = ?', espera, Time.current])
    reload
  end

  # Marca que a regra vai seguir depois desta decisão. -> false quando ela já tinha seguido: a
  # retomada chegou de novo (Guia e pessoa, retry do job) e os passos não podem rodar outra vez.
  def seguir!(regra_id, indice)
    marca = [{ 'regra' => regra_id, 'indice' => indice }].to_json
    self.class.where(id: id).where.not('seguidas @> ?::jsonb', marca)
        .update_all(['seguidas = seguidas || ?::jsonb, updated_at = ?', marca, Time.current]) == 1
  end
  # rubocop:enable Rails/SkipsModelValidations
end
