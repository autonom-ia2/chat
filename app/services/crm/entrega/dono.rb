# A entrega dirigida ao dono do card (R13 do #1150, outro canal; decisões do Rodrigo em 15/10). A Crm::Entrega pergunta
# daqui quem é a fila e se o dono passa na frente do agente de IA da regra:
#
# - dono fora da fila de quem cuida (sem o funil, fora da caixa, "Só as suas"): nada muda, vale a fila de sempre;
# - sem regra de Atribuição no funil: a fila é só o dono, e a conversa espera por ele;
# - com regra: o dono online é a fila inteira, e nem o agente de IA da regra entra; offline, a regra decide entre todos,
#   inclusive passando ao agente de IA;
# - presença fora do ar (Presenca.online_ids!, o ponto único): não se sabe se ele está online, então a entrega segue
#   dirigida a ele e a Entrega exige presença do seletor (#sem_presenca?), que relê, não consegue e segura, qualquer que
#   seja a regra. Nunca entrega no escuro; a marca guarda o dono para a fila tentar de novo.
#
# Decide de novo a cada fila pedida: a nova tentativa depois de o agente de IA recusar (Crm::Entrega#concluir_para_ia!)
# não reusa a decisão da primeira.
class Crm::Entrega::Dono
  # Para quem a entrega foi dirigida nesta fila (a marca de segurar guarda o id), ou nil.
  attr_reader :dirigido

  # `excluir`: ids de quem deixou um convite desta espera vencer (#1694); saem da fila antes de tudo, o dono também,
  # menos quando são todos (#so_quem_venceu?).
  def initialize(conversation:, pessoa:, excluir: [])
    @conversation = conversation
    @pessoa = pessoa
    @excluir = Array(excluir).map(&:to_i)
  end

  def fila(pessoas, regra:)
    @sem_presenca = false
    pessoas = sem_os_excluidos(pessoas)
    dono = @pessoa && pessoas.find { |pessoa| pessoa.id == @pessoa.id }
    @dirigido = dono && (regra.nil? || online?(dono)) ? dono : nil
    @dirigido ? [@dirigido] : pessoas
  end

  # O dono passa na frente do agente de IA da regra? O bloco monta a fila (e decide o dirigido).
  def na_frente?
    return false if @pessoa.nil?

    yield
    @dirigido.present?
  end

  # Na última fila, só sobrou quem deixou um convite desta espera vencer (#1694, opção "a").
  def so_quem_venceu?
    @so_quem_venceu == true
  end

  # A presença não respondeu na última fila: a Entrega pede presença ao seletor, que segura.
  def sem_presenca?
    @sem_presenca == true
  end

  private

  # Todos da fila deixaram vencer: a fila fica inteira, e a Entrega entrega ao primeiro que ficar online, sem convite.
  def sem_os_excluidos(pessoas)
    restantes = pessoas.reject { |pessoa| @excluir.include?(pessoa.id) }
    @so_quem_venceu = @excluir.any? && restantes.empty? && pessoas.any?
    @so_quem_venceu ? pessoas : restantes
  end

  def online?(pessoa)
    Crm::Entrega::Presenca.online_ids!(@conversation.account_id).include?(pessoa.id)
  rescue Crm::Ai::HandoffMemberSelector::PresencaIndisponivel
    @sem_presenca = true
  end
end
