# #2067: de qual agente de IA veio a conversa que está com uma pessoa, para o "Devolver para <agente>" da caixa de
# resposta. Lê o registro de passagens (#1606, Crm::Passagens.ultimas_abertas): a passagem em aberto mais recente da
# conversa foi de uma IA para a pessoa que está com ela agora. Pessoa que recebeu de outra pessoa (IA → Ana → Bia) não vê:
# a Bia não recebeu da IA. Quem vê o botão (só a dona da conversa) é a tela que decide.
#
# Sai para onde a conversa volta, e por qual porta:
# - `tipo: 'ia'` (agente nosso, com a Fase 2 dos Agentes): `id` é o agente, e a tela devolve pelo "Passar para"
#   (POST passar_para, Autonomia::Agents::PassarParaIa com `por: :pessoa`): evento, turno refeito e recusas, como
#   qualquer passagem para a IA.
# - `tipo: 'robo'`: `id` é o AgentBot, e a tela devolve pela atribuição de robô (POST assignments): o robô de outro
#   sistema (n8n) e o agente nosso numa conta sem a Fase 2 (o espelho do vínculo dele na caixa).
# O nome é o de agora (o agente, ou o robô), nunca o gravado na passagem: renomear o agente muda o botão.
#
# Só agente que atende cliente agora (o predicado dos Agentes, Agent#atende_cliente?, com os Agentes ligados na conta) e
# só robô ainda ligado nesta caixa. A IA passou sem ponta gravada (motivo da IA, `de` vazio): o primeiro robô ativo da
# caixa que passa no mesmo filtro. Sem para onde voltar, nada: a tela não oferece o que não funcionaria. Sem o CRM, nada.
#
#   Crm::Passagens::VeioDaIa.da_lista(conversas) -> { conversation_id => { tipo:, id:, name: } } (consultas fixas)
#   Crm::Passagens::VeioDaIa.de(conversa)        -> { tipo:, id:, name: } | nil
module Crm::Passagens::VeioDaIa
  AGENTE = 'Autonomia::Agents::Agent'.freeze
  ROBO = 'AgentBot'.freeze

  module_function

  def de(conversation)
    da_lista([conversation])[conversation.id]
  end

  def da_lista(conversations)
    return {} unless Crm::Config.enabled?

    com_pessoa = conversations.select { |conversation| conversation.assignee_type == 'User' }
    return {} if com_pessoa.empty?

    pares = vindas_da_ia(com_pessoa)
    pares.empty? ? {} : Resolvedor.new(pares).mapa
  end

  # Para o partial da conversa: a página que a lista já leu, senão a consulta da conversa.
  def da_pagina_ou_de(conversation, pagina)
    pagina ? pagina[conversation.id] : de(conversation)
  end

  # #2067: só a troca de dono (que vai só para a equipe, nunca ao contato) leva de qual IA a conversa veio, para o
  # "Devolver para" de quem recebeu. Os outros eventos não calculam: a tela guarda o que já sabia (veioDaIaPreservado).
  def no_evento(data, conversation)
    return data unless Conversations::FicarAoEnviar.ligado?(conversation.account)

    data.merge(meta: data[:meta].merge(veio_da_ia: de(conversation)))
  end

  # [conversa, passagem] das conversas cuja passagem em aberto mais recente veio de uma IA para quem está com ela.
  def vindas_da_ia(conversations)
    abertas = Crm::Passagens.ultimas_abertas(conversations.map(&:id))
    conversations.filter_map do |conversation|
      passagem = abertas[conversation.id]
      [conversation, passagem] if passagem && da_ia_para?(passagem, conversation)
    end
  end

  # Para a pessoa que está com a conversa, vinda de uma IA: a ponta gravada não é pessoa, ou não há ponta e o motivo é
  # da IA (Crm::Passagem::MOTIVOS_DA_IA, o mesmo critério do filtro "Recebidas da IA").
  def da_ia_para?(passagem, conversation)
    return false unless passagem.para_type == 'User' && passagem.para_id == conversation.assignee_id
    return passagem.de_type != 'User' if passagem.de_type.present?

    Crm::Passagem::MOTIVOS_DA_IA.include?(passagem.motivo)
  end

  # Carrega de uma vez, para a página inteira: contas, vínculos das caixas (com os agentes) e robôs ativos.
  class Resolvedor
    def initialize(pares)
      @pares = pares
      inboxes = pares.map { |conversation, _passagem| conversation.inbox_id }.uniq
      @contas = Account.where(id: pares.map { |conversation, _passagem| conversation.account_id }.uniq).index_by(&:id)
      @vinculos = Autonomia::Agents::AgentInbox.kept.where(inbox_id: inboxes, account_id: @contas.keys).includes(:agent).to_a
      @ativos = AgentBotInbox.active.where(inbox_id: inboxes).order(:id).pluck(:inbox_id, :agent_bot_id)
      @nomes = AgentBot.where(id: @ativos.map(&:last).uniq).pluck(:id, :name).to_h
    end

    def mapa
      @pares.each_with_object({}) do |(conversation, passagem), mapa|
        destino = destino(conversation, passagem)
        mapa[conversation.id] = destino if destino
      end
    end

    private

    def destino(conversation, passagem)
      case passagem.de_type
      when AGENTE then do_agente(conversation, vinculo_do_agente(conversation, passagem.de_id))
      when ROBO then do_robo(conversation, passagem.de_id)
      else primeiro_ativo(conversation)
      end
    end

    # Robô ligado nesta caixa: se é o espelho de um vínculo nosso, vale a regra do agente; senão, é de outro sistema.
    def do_robo(conversation, robo_id)
      return unless ativos_da_caixa(conversation).include?(robo_id)

      vinculo = vinculo_do_espelho(conversation, robo_id)
      return do_agente(conversation, vinculo) if vinculo

      { tipo: 'robo', id: robo_id, name: @nomes[robo_id].presence }
    end

    def primeiro_ativo(conversation)
      ativos_da_caixa(conversation).lazy.filter_map { |robo_id| do_robo(conversation, robo_id) }.first
    end

    def do_agente(conversation, vinculo)
      agente = vinculo&.agent
      conta = @contas[conversation.account_id]
      return unless agente && agente.account_id == conversation.account_id && atende?(agente, conta)

      return { tipo: 'ia', id: agente.id, name: agente.name } if fase2?(conta)

      { tipo: 'robo', id: vinculo.agent_bot_id, name: agente.name }
    end

    def atende?(agente, conta)
      agentes_ligados?(conta) && agente.atende_cliente?
    end

    def agentes_ligados?(conta)
      (@ligados ||= {}).fetch(conta.id) { @ligados[conta.id] = Autonomia::Agents::Config.enabled?(conta) }
    end

    # O "Passar para" só existe com a Fase 2 (Crm::AgentesIa.ligado?, a porta do PassarParaController).
    def fase2?(conta)
      (@fase2 ||= {}).fetch(conta.id) { @fase2[conta.id] = Crm::AgentesIa.ligado?(conta) }
    end

    def vinculo_do_agente(conversation, agente_id)
      @vinculos.find do |vinculo|
        vinculo.inbox_id == conversation.inbox_id && vinculo.autonomia_agent_id == agente_id &&
          vinculo.account_id == conversation.account_id
      end
    end

    def vinculo_do_espelho(conversation, robo_id)
      @vinculos.find do |vinculo|
        vinculo.inbox_id == conversation.inbox_id && vinculo.agent_bot_id == robo_id && vinculo.account_id == conversation.account_id
      end
    end

    def ativos_da_caixa(conversation)
      @ativos.filter_map { |inbox_id, robo_id| robo_id if inbox_id == conversation.inbox_id }
    end
  end
end
