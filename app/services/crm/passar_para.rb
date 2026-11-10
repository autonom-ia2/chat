# #1593 — o "Passar para…" da conversa: quem atende escolhe quem assume, entre as pessoas da caixa e, com a Fase 2 dos
# Agentes, os agentes de IA que podem receber a conversa (Crm::AgentesIa, regra dos Agentes).
#
#   Crm::PassarPara.new(conversation:, usuario:).retrato             # GET: agentes, com quem está e a origem
#   Crm::PassarPara.new(conversation:, usuario:).passar!(tipo:, id:)  # POST
#
# - Pessoa: a atribuição de hoje (Conversations::AssignmentService). A passagem vai para o registro do CRM pelo escritor
#   único de toda atribuição a pessoa (o listener do #1606); aqui só se marca o motivo (Crm::Passagens.com_motivo). O
#   registro carimba a devolução quando a pessoa é a origem da passagem aberta.
# - Agente de IA: o serviço dos Agentes (Crm::Entrega::ParaIa.passar!), que troca o dono, solta a pessoa e grava a
#   passagem ele mesmo. A recusa volta com o código, e a tela diz o porquê em linguagem simples.
# - Robô de outro sistema ligado à caixa (#2882, Crm::PassarPara::RobosDaCaixa): a atribuição de robô de hoje
#   (Conversations::AssignmentService com AgentBot), a mesma do "Devolver para". A pessoa sai, e o listener do #1606
#   grava a passagem dela para o robô com o motivo passar_para.
#
# A origem (quem passou para o agente que está com a conversa) vem da última passagem aberta: é o selo "Com Lia ·
# passada por Ana" e o "Devolver para Ana" no topo da lista.
class Crm::PassarPara
  Resultado = Struct.new(:ok, :codigo, :assignee, keyword_init: true)
  TIPOS = %w[pessoa ia robo].freeze
  MOTIVO = 'passar_para'.freeze
  # O agente já estava com a conversa: nada muda, e a tela só fecha.
  OK_DA_IA = [Crm::Entrega::ParaIa::PASSOU, 'ja_e_o_dono'].freeze

  def initialize(conversation:, usuario:)
    @conversation = conversation
    @usuario = usuario
    @inbox = conversation.inbox
  end

  def retrato
    ligado = Crm::AgentesIa.ligado?(@conversation.account)
    dono = ligado ? Crm::AgentesIa.dono(@conversation) : nil
    {
      fase2: ligado,
      sem_robo: ligado && sem_robo?,
      pessoas: pessoas_da_caixa.map { |user| pessoa(user) },
      agentes: Crm::AgentesIa.destinos(@conversation).map { |agente| item(agente, dono) },
      robos: robos,
      com_ia: dono && { id: dono.id, name: dono.name, bot_id: @conversation.assignee_agent_bot_id },
      origem: dono && origem_de(dono)
    }
  end

  def passar!(tipo:, id:)
    return recusa('destino_invalido') unless TIPOS.include?(tipo.to_s) && id.to_i.positive?

    case tipo.to_s
    when 'ia' then para_ia(id.to_i)
    when 'robo' then para_robo(id.to_i)
    else para_pessoa(id.to_i)
    end
  end

  private

  def robos
    robos_da_caixa.map { |robo| { id: robo.id, name: robo.name, com_a_conversa: com_o_robo?(robo) } }
  end

  # Ninguém atende a caixa primeiro: nem a porta de um agente nosso nem um robô de outro sistema (#2882).
  def sem_robo?
    ::Autonomia::Agents::QuemResponde.porta_da_caixa(@inbox).blank? && robos_da_caixa.empty?
  end

  def item(agente, dono)
    { id: agente.id, name: agente.name, com_a_conversa: dono&.id == agente.id }
  end

  # Só a passagem aberta que levou a conversa ao agente que está com ela. Origem pessoa: diz se ela ainda pode receber
  # aqui (senão a tela não oferece "Devolver para").
  def origem_de(agente)
    passagem = Crm::Passagens.ultima_aberta(@conversation)
    de = passagem&.de
    return if de.nil? || !para_este_agente?(passagem.para, agente)

    pessoa = de.classe.to_s == 'User'
    { tipo: de.tipo.to_s, classe: de.classe.to_s, id: de.id, name: de.nome, pode_receber: pessoa && pessoa_da_caixa(de.id).present? }
  end

  # O registro identifica por classe + id: o agente, ou o espelho dele que é o dono da conversa.
  def para_este_agente?(para, agente)
    case para&.classe.to_s
    when 'Autonomia::Agents::Agent' then para.id.to_i == agente.id
    when 'AgentBot' then para.id.to_i == @conversation.assignee_agent_bot_id
    else false
    end
  end

  def para_pessoa(user_id)
    pessoa = pessoa_da_caixa(user_id)
    return recusa('pessoa_fora_da_caixa') if pessoa.nil?

    Crm::Passagens.com_motivo(MOTIVO) do
      Conversations::AssignmentService.new(conversation: @conversation, assignee_id: pessoa.id).perform
    end
    Resultado.new(ok: true, assignee: pessoa)
  end

  # Quem pode receber é a regra dos Agentes: o serviço deles recusa com o código (parado, sem vínculo na caixa, sem a
  # Fase 2, conversa resolvida…). Aqui só o agente precisa ser desta conta.
  def para_ia(agent_id)
    agente = ::Autonomia::Agents::Agent.kept.find_by(account_id: @conversation.account_id, id: agent_id)
    return recusa('destino_invalido') if agente.nil?

    codigo = Crm::Entrega::ParaIa.passar!(conversation: @conversation, agent: agente, por: :pessoa, motivo: MOTIVO,
                                          origem: quem_esta_agora, pedida_por: @usuario)
    OK_DA_IA.include?(codigo) ? Resultado.new(ok: true) : recusa(codigo)
  end

  # Só robô oferecido na lista (ativo na caixa, não espelho de agente nosso). Conversa resolvida não recebe ninguém, como
  # na IA; o robô que já está com ela não muda nada, e a tela só fecha. O AssignmentService devolve nil quando o robô
  # deixou de existir entre a lista e o clique: a tela recebe a recusa, nunca um "pronto" sem troca.
  def para_robo(robo_id)
    robo = robos_da_caixa.find { |item| item.id == robo_id }
    return recusa('robo_fora_da_caixa') if robo.nil?
    return recusa('conversa_resolvida') if @conversation.resolved?
    return Resultado.new(ok: true) if com_o_robo?(robo)

    antes = quem_esta_agora
    # A troca e a passagem valem juntas: uma falha no registro desfaz a troca, e a tela recebe o erro.
    atribuido = ActiveRecord::Base.transaction do
      feito = Crm::Passagens.com_motivo(MOTIVO) do
        Conversations::AssignmentService.new(conversation: @conversation, assignee_id: robo.id, assignee_type: 'AgentBot').perform
      end
      registrar_sem_pessoa!(antes, robo) if feito == robo
      feito
    end
    atribuido == robo ? Resultado.new(ok: true) : recusa('robo_fora_da_caixa')
  end

  # Com uma pessoa na conversa, quem grava a passagem dela para o robô é o listener do #1606 (a troca de pessoa). Sem
  # pessoa (um agente de IA nosso, outro robô ou ninguém), não há troca de pessoa e o listener não grava: a passagem de
  # quem estava para o robô sai daqui, e a passagem aberta de antes (Ana → Lia) fica devolvida.
  # Ponta que o registro não conhece (outro tipo de dono, como o Captain::Assistant) vira "ninguém".
  def registrar_sem_pessoa!(antes, robo)
    return if antes.is_a?(User)

    de = antes if antes.is_a?(AgentBot) || antes.is_a?(::Autonomia::Agents::Agent)
    Crm::Passagens.registrar!(conversation: @conversation, de: de, para: robo, pedida_por: @usuario, motivo: MOTIVO)
  end

  def robos_da_caixa
    @robos_da_caixa ||= Crm::PassarPara::RobosDaCaixa.de(@conversation)
  end

  def com_o_robo?(robo)
    @conversation.ai_assignee_type == 'AgentBot' && @conversation.assignee_agent_bot_id == robo.id
  end

  # Quem pode ser atribuído na caixa (membros dela e administradores da conta, Inbox#assignable_agents) e vê a conversa
  # pelo acesso por funil (#1148, o mesmo filtro do motor de entrega).
  # A lista da tela e a aceitação do `passar!` leem daqui (#1140, correção 5): a tela só oferece quem o servidor aceita.
  def pessoas_da_caixa
    @pessoas_da_caixa ||= Crm::Access::Recipients.new(@conversation).filter(@inbox.assignable_agents)
  end

  def pessoa_da_caixa(user_id)
    pessoas_da_caixa.find { |user| user.id == user_id.to_i }
  end

  def pessoa(user)
    { id: user.id, name: user.name, thumbnail: user.avatar_url, availability_status: user.availability_status }
  end

  # Quem estava com a conversa antes de passar: o agente de IA dono, a pessoa no nome ou o robô (externo).
  def quem_esta_agora
    Crm::AgentesIa.dono(@conversation) || @conversation.assignee || @conversation.ai_assignee
  end

  def recusa(codigo)
    Resultado.new(ok: false, codigo: codigo)
  end
end
