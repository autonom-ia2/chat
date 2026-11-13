# O passo "ia_assumir" (#2414 G15): passa a conversa à agente de IA escolhida pela Atribuição do CRM
# (Crm::Entrega::ParaIa, o motor único de entrega), nunca pela atribuição direta ao robô.
#
# Pede como o CRM (`por: :crm`): pessoa no nome vence, e o passo pula com `pessoa_atribuida` (D1). A exceção é a opção
# `cobrir_pessoa`, "Cobrir a pessoa enquanto ela não responde" (decisão 18 do Rodrigo, exemplo 17), desligada por
# padrão: com ela e uma pessoa no nome, quem pede é quem ligou a automação (`por: :pessoa`, como o "Passar para…" da
# tela), a agente fica com a conversa e o registro da cobertura (`cobrindo_pessoa`, Cobertura) guarda de quem ela foi
# tirada e qual conversa ela cobre. A conversa fica travada do começo ao fim: quem pede, a troca e o registro da
# cobertura saem da mesma leitura e da mesma transação. Quando essa pessoa escrever na conversa, ela volta para ela
# (Cobertura). A agente fala com
# o cliente pelo turno de quem recebe a passagem (Operate::AoReceberPassagem), sabendo quem passou. Sem pessoa no nome,
# a opção não muda nada. Fora deste passo, nada muda. Toda recusa do serviço
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
  # e quem recebe quando alguém passa), só com id e nome. Sem as áreas de IA, nenhum. A mesma regra do
  # PassarParaIa.destinos_na_caixa (vínculo vivo e agente atendendo cliente), numa consulta para a conta toda.
  def self.opcoes(conta)
    return [] unless ::Crm::AgentesIa.ligado?(conta)

    ::Autonomia::Agents::AgentInbox.kept.where(account_id: conta.id, inbox_id: conta.inboxes.select(:id)).includes(:agent)
                                   .filter_map(&:agent).uniq.select { |agente| agente.account_id == conta.id && agente.atende_cliente? }
                                   .sort_by { |agente| [agente.name.to_s.downcase, agente.id] }.map { |agente| { id: agente.id, name: agente.name } }
  end

  # Para a Receita, ao salvar: o agente tem de ser desta conta.
  def self.problemas_ao_salvar(conta, passo)
    return [] if agente(conta, passo['agente_id'])

    [I18n.t('autonomia.automacao.receita.agente_de_ia_invalido', passo: passo['id'], id: passo['agente_id'])]
  end

  # Para o ensaio: [o que faria, dados], pelas mesmas perguntas do serviço dos Agentes e na mesma ordem
  # (PassarParaIa#recusa_antes_da_trava e #decidir), sem gravar nem chamá-lo. O spec compara os dois motivo a motivo.
  def self.ensaiar(passo, conversa)
    agente = agente(conversa.account, passo['agente_id'])
    return ['agente_sumiu', {}] if agente.nil?

    [motivo_no_ensaio(conversa, agente, cobrir_pessoa?(passo)) || 'ia_assumir', { agente: agente.name }]
  end

  # Decisão 18: a opção do passo, desligada por padrão.
  def self.cobrir_pessoa?(passo) = passo['cobrir_pessoa'] == true

  # Cobertura (decisão 18): a agente que cobre ainda pode atender esta conversa, pelas mesmas perguntas do ensaio.
  def self.pode_cobrir?(conversa, agente_id)
    agente = agente(conversa.account, agente_id)
    agente.present? && motivo_no_ensaio(conversa, agente, true).nil?
  end

  def self.motivo_no_ensaio(conversa, agente, cobrir_pessoa)
    return 'fase2_desligada' unless ::Crm::AgentesIa.ligado?(conversa.account)
    return 'nao_atende_cliente' unless agente.atende_cliente?
    return 'conversa_resolvida' if conversa.resolved?
    return 'pessoa_atribuida' if conversa.assignee_id.present? && !cobrir_pessoa

    'sem_vinculo_na_caixa' unless ::Autonomia::Agents::AgentInbox.kept.exists?(account_id: conversa.account_id, inbox_id: conversa.inbox_id,
                                                                               autonomia_agent_id: agente.id)
  end
  private_class_method :motivo_no_ensaio

  def executar
    return sem_conversa if @conversa.nil?

    negado = sem_acesso
    return negado if negado
    return pulado('fase2_desligada') unless ::Crm::AgentesIa.ligado?(@execucao.account)

    agente = self.class.agente(@execucao.account, @passo['agente_id'])
    return pulado('agente_sumiu') if agente.nil?

    assumir(agente)
  end

  private

  # Sob a trava da conversa: quem pede lê a pessoa no nome agora, e a pessoa tirada (lida pelo serviço sob a mesma trava)
  # grava a cobertura na transação da troca. Sem return dentro do with_lock (dispararia ROLLBACK).
  def assumir(agente)
    resultado = nil
    @conversa.with_lock do
      resultado = passar(agente)
      cobrir(agente, resultado.pessoa_tirada_id) if resultado.pessoa_tirada_id
    end
    codigo = resultado.codigo.to_s
    dados = { 'agente_id' => agente.id, **tirada(resultado.pessoa_tirada_id) }
    return Resultado.new(tipo: :ok, dados: dados.merge('trocou' => codigo != JA_E_O_DONO)) if OK.include?(codigo)

    pulado(codigo, dados)
  end

  # Quem estava com a conversa, lido do banco agora: o agente de IA dono, a pessoa no nome ou o robô.
  def passar(agente)
    origem = ::Crm::AgentesIa.dono(@conversa) || @conversa.assignee || @conversa.ai_assignee
    ::Autonomia::Automacao::Ato.da(@execucao.automacao_id) do
      ::Crm::Entrega::ParaIa.resultado!(conversation: @conversa, agent: agente, motivo: MOTIVO, origem: origem, **quem_pede)
    end
  end

  # Decisão 18: com a opção e uma pessoa no nome (lida sob a trava), quem ligou pede, como na tela; senão, o CRM (pessoa
  # no nome vence).
  def quem_pede
    tira_da_pessoa? ? { por: :pessoa, pedida_por: @execucao.dona.ligada_por } : { por: :crm }
  end

  def cobrir(agente, pessoa_id)
    ::Autonomia::Automacao::Cobertura.comecar!(@execucao, @passo['id'], @conversa, pessoa_id, agente.id)
  end

  def tirada(pessoa_id) = pessoa_id ? { 'tirada_de' => pessoa_id } : {}

  def tira_da_pessoa? = self.class.cobrir_pessoa?(@passo) && @conversa.assignee_id.present?

  def pulado(motivo, dados = {}) = Resultado.new(tipo: :pulado, motivo: motivo, dados: dados)
end
