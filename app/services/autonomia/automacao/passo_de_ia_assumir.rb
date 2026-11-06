# O passo "ia_assumir" (#2414 G15): passa a conversa à agente de IA escolhida pela Atribuição do CRM
# (Crm::Entrega::ParaIa, o motor único de entrega), nunca pela atribuição direta ao robô.
#
# Pede como o CRM (`por: :crm`): pessoa no nome vence, e o passo pula com `pessoa_atribuida` (D1). Toda recusa do serviço
# dos Agentes (sem vínculo na caixa, não atende cliente, Fase 2 desligada, conversa resolvida) vira pulo com o código,
# nunca outro agente. Erro inesperado sobe ao executor, como nos outros passos.
#
# Antes de passar, de novo a cada rodada: a conversa do alvo (NaConversa; no card, a principal), quem ligou enxerga a
# conversa (senão a automação pausa), as áreas de IA ligadas na conta e o agente ainda desta conta. A troca sai assinada
# pela automação (Ato, #2568 P7), dentro da cadeia da rodada: o evento da troca não redispara a mesma automação.
class Autonomia::Automacao::PassoDeIaAssumir
  include ::Autonomia::Automacao::NaConversa

  MOTIVO = 'automacao'.freeze
  JA_E_O_DONO = 'ja_e_o_dono'.freeze
  OK = [::Crm::Entrega::ParaIa::PASSOU, JA_E_O_DONO].freeze

  def self.agente(conta, id) = ::Autonomia::Agents::Agent.kept.find_by(account_id: conta.id, id: id)

  # Os agentes que o passo oferece na tela: os que podem receber conversa em alguma caixa da conta (quem atende primeiro
  # e quem recebe quando alguém passa), só com id e nome. Sem as áreas de IA, nenhum.
  def self.opcoes(conta)
    return [] unless ::Crm::AgentesIa.ligado?(conta)

    conta.inboxes.flat_map { |caixa| ::Autonomia::Agents::PassarParaIa.destinos_na_caixa(caixa) }.uniq
         .sort_by { |agente| [agente.name.to_s.downcase, agente.id] }.map { |agente| { id: agente.id, name: agente.name } }
  end

  # Para a Receita, ao salvar: o agente tem de ser desta conta.
  def self.problemas_ao_salvar(conta, passo)
    return [] if agente(conta, passo['agente_id'])

    [I18n.t('autonomia.automacao.receita.agente_de_ia_invalido', passo: passo['id'], id: passo['agente_id'])]
  end

  # Para o ensaio: [o que faria, dados], pelas mesmas perguntas do serviço dos Agentes, sem gravar nem chamá-lo.
  def self.ensaiar(passo, conversa)
    agente = agente(conversa.account, passo['agente_id'])
    return ['agente_sumiu', {}] if agente.nil?

    [motivo_no_ensaio(conversa, agente) || 'ia_assumir', { agente: agente.name }]
  end

  def self.motivo_no_ensaio(conversa, agente)
    return 'fase2_desligada' unless ::Crm::AgentesIa.ligado?(conversa.account)
    return 'conversa_resolvida' if conversa.resolved?
    return 'pessoa_atribuida' if conversa.assignee_id.present?
    return if ::Autonomia::Agents::PassarParaIa.destinos_possiveis(conversa).include?(agente)

    agente.atende_cliente? ? 'sem_vinculo_na_caixa' : 'nao_atende_cliente'
  end
  private_class_method :motivo_no_ensaio

  def executar
    return sem_conversa if @conversa.nil?

    negado = sem_acesso
    return negado if negado
    return pulado('fase2_desligada') unless ::Crm::AgentesIa.ligado?(@execucao.account)

    agente = self.class.agente(@execucao.account, @passo['agente_id'])
    return pulado('agente_sumiu') if agente.nil?

    codigo = passar(agente)
    dados = { 'agente_id' => agente.id }
    return Resultado.new(tipo: :ok, dados: dados.merge('trocou' => codigo != JA_E_O_DONO)) if OK.include?(codigo)

    pulado(codigo, dados)
  end

  private

  # Quem estava com a conversa, lido do banco agora: o agente de IA dono, a pessoa no nome ou o robô.
  def passar(agente)
    origem = ::Crm::AgentesIa.dono(@conversa) || @conversa.assignee || @conversa.ai_assignee
    ::Autonomia::Automacao::Ato.da(@execucao.automacao_id) do
      ::Crm::Entrega::ParaIa.passar!(conversation: @conversa, agent: agente, por: :crm, motivo: MOTIVO, origem: origem)
    end
  end

  def pulado(motivo, dados = {}) = Resultado.new(tipo: :pulado, motivo: motivo, dados: dados)
end
