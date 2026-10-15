# Caixas no CRM → Quem cuida do quê? (#1447): os agentes de IA de área da caixa e os funis de cada um, gravados junto
# com o resto da caixa (Crm::Caixas::Gravador, na mesma transação).
#
# `lista` é a lista inteira dos agentes de área que ficam na caixa: [{ 'id' =>, 'pipeline_ids' => [] }].
# - Agente que entra: Autonomia::Agents::Areas.vincular!(ativar: true) — vincula e liga num passo só.
# - Agente que sai: as linhas dele na caixa saem e Autonomia::Agents::Areas.desvincular!. Sendo a última caixa dele, o
#   Agentes IA o para sozinho (a tela avisa antes).
# - Os funis: uma linha em crm_inbox_ai_agents por funil marcado; um funil tem um agente só na caixa.
# O vínculo é do Agentes IA: esta classe nunca escreve em autonomia_agent_inboxes direto.
#
# Trava todos os agentes envolvidos (por id) antes de qualquer vínculo: o Areas trava agente e depois caixa, e travar o
# segundo agente com a caixa já presa inverteria a ordem.
class Crm::Caixas::GravadorDeAgentes
  Invalida = Crm::Caixas::Gravador::Invalida
  # Código do Autonomia::Agents::Areas.caixa_aceita_area? (leitor único da regra da caixa, #1433) -> código da tela.
  CODIGO_DA_CAIXA = {
    principal_parado: 'crm.caixas.principal_parado',
    robo_externo: 'crm.caixas.robo_externo',
    fase2_desligada: 'crm.caixas.agentes_desligados'
  }.freeze

  def initialize(account:, inbox:, lista:, pipeline_ids:)
    @account = account
    @inbox = inbox
    @itens = Array(lista)
    @lista = @itens.index_by { |item| item['id'].to_i }
    @pipeline_ids = pipeline_ids
  end

  def perform
    validar!
    travar_agentes!
    saindo.each { |agente| tirar!(agente) }
    entrando.each { |agente| vincular!(agente) }
    gravar_funis!
  end

  private

  def validar!
    raise Invalida, 'crm.caixas.agentes_desligados' unless Crm::Ai::Config.areas_ligadas?(@account)
    raise Invalida, 'crm.caixas.agente_invalido' if agente_invalido?

    recusa = recusa_da_caixa
    raise Invalida, recusa if recusa
    raise Invalida, 'crm.caixas.funil_invalido' if (funis_pedidos - @pipeline_ids).any?
    raise Invalida, 'crm.caixas.funil_com_dois_agentes' if funis_pedidos.size != funis_pedidos.uniq.size
  end

  # Só quando entra alguém: a caixa tem de aceitar área agora (principal atendendo, ou só de pessoas, #1433). Quem já
  # está na caixa não trava o salvar dos funis. O Areas confere de novo, com a caixa travada.
  def recusa_da_caixa
    return if (@lista.keys - atuais).empty?

    CODIGO_DA_CAIXA[::Autonomia::Agents::Areas.caixa_aceita_area?(@inbox, conferir_fase2: false).codigo]
  end

  # O mesmo agente duas vezes, ou quem não pode ser área desta caixa.
  def agente_invalido?
    @itens.size != @lista.size || (@lista.keys - candidatos.keys).any?
  end

  # Quem pode ser área desta caixa: agente da conta, não apagado, que fala com cliente (não interno, não de sistema) e
  # que não é a porta dela. Filtro largo de propósito (não o escopo podem_ser_area): quem já está na caixa e foi pausado
  # não pode travar o salvar da tela. Quem ENTRA é conferido pelo Areas (pode_ser_area?), com o agente travado.
  def candidatos
    @candidatos ||= begin
      lista = agentes_da_conta.kept.where.not(id: porta&.autonomia_agent_id).to_a
      lista.reject { |agente| agente.actuation_internal? || agente.config&.dig('system_key').present? }.index_by(&:id)
    end
  end

  def agentes_da_conta
    ::Autonomia::Agents::Agent.where(account_id: @account.id)
  end

  def porta
    return @porta if defined?(@porta)

    @porta = ::Autonomia::Agents::AgentInbox.kept.porta.find_by(account_id: @account.id, inbox_id: @inbox.id)
  end

  def atuais
    @atuais ||= ::Autonomia::Agents::AgentInbox.kept.area.where(account_id: @account.id, inbox_id: @inbox.id).pluck(:autonomia_agent_id)
  end

  def travar_agentes!
    ids = (atuais + @lista.keys).uniq
    ::Autonomia::Agents::Agent.where(id: ids).order(:id).lock.load if ids.any?
  end

  def saindo
    agentes_da_conta.where(id: atuais - @lista.keys).order(:id)
  end

  def entrando
    (@lista.keys - atuais).sort.map { |id| candidatos.fetch(id) }
  end

  def tirar!(agente)
    Crm::InboxAiAgent.where(account_id: @account.id, inbox_id: @inbox.id, autonomia_agent_id: agente.id).delete_all
    ::Autonomia::Agents::Areas.desvincular!(agent: agente, inbox: @inbox)
  end

  # Recusa do Areas vira código para a tela: agente que não pode falar com cliente, ou que não liga (cadastro
  # incompleto); caixa que não aceita área (pelo código do leitor).
  def vincular!(agente)
    ::Autonomia::Agents::Areas.vincular!(agent: agente, inbox: @inbox, ativar: true)
  rescue ::Autonomia::Agents::Areas::AgenteRascunho
    # #1570: rascunho tem frase própria na tela.
    raise Invalida, 'crm.caixas.agente_rascunho'
  rescue ::Autonomia::Agents::Areas::AgenteInterno, ::Autonomia::Agents::Areas::AgenteDeSistema,
         ::Autonomia::Agents::Areas::AgenteNaoPodeSerArea
    raise Invalida, 'crm.caixas.agente_invalido'
  rescue ::Autonomia::Agents::Areas::CaixaNaoAceitaArea => e
    raise Invalida, CODIGO_DA_CAIXA.fetch(e.codigo, 'crm.caixas.agente_invalido')
  rescue ActiveRecord::RecordInvalid => e
    raise Invalida, codigo_da_recusa(e.record)
  end

  def codigo_da_recusa(record)
    return 'crm.caixas.agente_nao_liga' if record.is_a?(::Autonomia::Agents::Agent)

    if record.errors.include?(:papel)
      codigo = ::Autonomia::Agents::Areas.caixa_aceita_area?(@inbox, conferir_fase2: false).codigo
      return CODIGO_DA_CAIXA.fetch(codigo, 'crm.caixas.agente_invalido')
    end

    'crm.caixas.agente_invalido'
  end

  # Funis da caixa desmarcados (ou de agente que saiu) perdem a linha; cada funil marcado fica com o agente dele. Funil
  # arquivado não aparece na tela: a linha dele fica como está.
  def gravar_funis!
    desejados = @lista.flat_map { |id, item| funis_de(item).map { |pipeline_id| [pipeline_id, id] } }.to_h
    linhas = Crm::InboxAiAgent.where(account_id: @account.id, inbox_id: @inbox.id)
    linhas.where(pipeline_id: @pipeline_ids).where.not(pipeline_id: desejados.keys).delete_all
    desejados.each do |pipeline_id, agent_id|
      linha = linhas.find_or_initialize_by(pipeline_id: pipeline_id)
      linha.update!(autonomia_agent_id: agent_id)
    end
  end

  def funis_de(item)
    Array(item['pipeline_ids']).map(&:to_i).uniq
  end

  def funis_pedidos
    @funis_pedidos ||= @lista.values.flat_map { |item| funis_de(item) }
  end
end
