# IA cuida dos comentários (#2458; #2469, PR 3a do #2436): quem escreve as respostas de um cuidado numa caixa. É o agente
# da porta da caixa (Autonomia::Agents::QuemResponde.porta_da_caixa), resolvido na hora: o cuidado guarda a caixa, não
# o agente. Uma regra só para o motor (Escrita) e para a tela (o cartão do post em Agentes, o "O que sabe" e o Testar).
#
# `motivo` é nil quando o agente escreve; senão, por que ficam as frases fixas: sem caixa, caixa ou agente de outra
# conta, a conta sem a chave dela, agentes desligados na conta, sem agente na porta, a Lia (`insurance_quote` não fala em
# comentário público), agente que não pode falar com cliente agora (Agent#atende_cliente?, o mesmo do QuemResponde) ou
# agente em piloto só para telefones de teste (o mesmo contrato do Operate.authorized_agent_inbox).
class Crm::MetaAds::ComentariosIa::Porta
  LIA = 'insurance_quote'.freeze

  def initialize(care:, inbox:)
    @care = care
    @inbox = inbox
  end

  def motivo
    return @motivo if defined?(@motivo)

    @motivo = motivo_da_caixa || motivo_do_agente
  end

  # O agente da porta, mesmo quando não pode escrever (a tela diz quem é e por que não escreve). nil sem caixa da conta.
  def agente
    return @agente if defined?(@agente)

    @agente = (Autonomia::Agents::QuemResponde.porta_da_caixa(@inbox)&.agent if da_conta?)
  end

  private

  def da_conta?
    @inbox.present? && @inbox.account_id == @care.account_id
  end

  def motivo_da_caixa
    return 'sem_caixa' if @inbox.nil?
    return 'outra_conta' unless da_conta?
    return 'sem_chave' if Crm::MetaAds::ComentariosIa::ChaveDaConta.de(@care.account).nil?

    'agentes_desligados' unless Autonomia::Agents::Config.enabled?(@care.account)
  end

  def motivo_do_agente
    return 'sem_porta' if agente.nil?
    return 'outra_conta' unless agente.account_id == @care.account_id
    return 'lia' if agente.agent_type == LIA
    return 'porta_parada' unless agente.atende_cliente?

    # Agente em piloto, só para os telefones de teste: quem comenta não tem telefone, então nunca está na lista.
    'piloto' unless Autonomia::Agents::Operate.test_allowlist_permits?(nil, agente)
  end
end
