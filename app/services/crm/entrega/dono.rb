# A entrega dirigida ao dono do card (R13 do #1150, outro canal; decisões do Rodrigo em 15/10). A Crm::Entrega pergunta
# daqui quem é a fila e se o dono passa na frente do agente de IA da regra:
#
# - dono fora da fila de quem cuida (sem o funil, fora da caixa, "Só as suas"): nada muda, vale a fila de sempre;
# - sem regra de Atribuição no funil: a fila é só o dono, e a conversa espera por ele;
# - com regra: o dono online é a fila inteira, e nem o agente de IA da regra entra; offline, a regra decide entre todos,
#   inclusive passando ao agente de IA;
# - presença fora do ar (Presenca.online_ids!, o ponto único): não se sabe se ele está online, então segue dirigida a
#   ele, e o seletor, ao ler a presença, segura (a marca guarda o dono para a fila tentar de novo).
class Crm::Entrega::Dono
  # Para quem a entrega foi dirigida nesta rodada (a marca de segurar guarda o id), ou nil.
  attr_reader :dirigido

  def initialize(conversation:, pessoa:)
    @conversation = conversation
    @pessoa = pessoa
  end

  def fila(pessoas, regra:)
    dono = @pessoa && pessoas.find { |pessoa| pessoa.id == @pessoa.id }
    @dirigido = dono if dono && (regra.nil? || online?(dono))
    @dirigido ? [@dirigido] : pessoas
  end

  # O dono passa na frente do agente de IA da regra? O bloco monta a fila (e decide o dirigido).
  def na_frente?
    return false if @pessoa.nil?

    yield
    @dirigido.present?
  end

  private

  def online?(pessoa)
    Crm::Entrega::Presenca.online_ids!(@conversation.account_id).include?(pessoa.id)
  rescue Crm::Ai::HandoffMemberSelector::PresencaIndisponivel
    true
  end
end
