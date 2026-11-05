# Uma regra antiga (`AutomationRule`) lida como receita do motor novo (#2568, F9). Só leitura: não grava nada.
#
# Uma regra vira uma automação: o evento vira o gatilho, as condições viram o filtro do gatilho e cada ação vira um
# passo, na mesma ordem. O que não tem equivalente vai para as faltas, e a regra só é convertível sem falta nenhuma.
class Autonomia::Automacao::Conversao::DaRegra
  Mapa = Autonomia::Automacao::Conversao::Mapa

  def initialize(regra)
    @regra = regra
    @faltas = []
    @ressalvas = []
    @passos = []
  end

  def resultado
    gatilho = gatilho!
    filtro = filtro!(gatilho)
    Array(@regra.actions).each { |acao| passo!(acao.to_h.stringify_keys) }
    espera!

    Autonomia::Automacao::Conversao::Resultado.new(
      origem: 'regra', id: @regra.id, ligada: @regra.active, autor_conhecido: autor_conhecido?,
      receita: receita(gatilho, filtro), faltas: @faltas, ressalvas: @ressalvas
    )
  end

  private

  def receita(gatilho, filtro)
    return unless gatilho

    corpo = { 'tipo' => gatilho }
    corpo['filtros'] = [filtro] if filtro
    { 'gatilho' => corpo, 'passos' => @passos }
  end

  def gatilho!
    tipo = Mapa::GATILHO_DA_REGRA[@regra.event_name]
    falta('gatilho_conversa_atualizada', @regra.event_name) unless tipo
    tipo
  end

  def filtro!(gatilho)
    condicoes = Autonomia::Automacao::Conversao::Condicoes.new(@regra.conditions, gatilho: gatilho)
    filtro = condicoes.filtro
    @faltas.concat(condicoes.faltas)
    @ressalvas.concat(condicoes.ressalvas)
    filtro
  end

  # A regra com espera (`execution_delay`) rearma por episódio (status, cliente sem resposta, atendente sem resposta) e
  # reconfere as condições na hora. O "esperar" do motor novo não sabe do episódio: falta até a F9.0 dizer como.
  def espera!
    falta('espera_de_episodio', "#{@regra.execution_delay} min") if @regra.execution_delay.to_i.positive?
  end

  # O EE guarda quem criou a regra no audit; sem EE (ou regra criada pelo console), ninguém.
  def autor_conhecido?
    return false unless defined?(Audited::Audit)

    Audited::Audit.exists?(auditable_type: 'AutomationRule', auditable_id: @regra.id, action: 'create')
  end

  # Ações que esperam um passo de outra fase: a falta diz qual.
  FALTA_DA_ACAO = {
    'perguntar_ao_decisor' => 'passo_decidir', 'send_webhook_event' => 'passo_webhook', 'add_private_note' => 'nota_privada',
    **Mapa::DE_CARD.index_with('passo_de_card')
  }.freeze

  def passo!(acao)
    nome = acao['action_name'].to_s
    params = Array(acao['action_params'])
    return passo_de_conversa!(nome, params) if CONVERSA.include?(nome)
    return falta(FALTA_DA_ACAO[nome], nome) if FALTA_DA_ACAO.key?(nome)
    return mensagem!(params) if nome == 'send_message'
    return aviso_por_email!(nome) if nome == 'send_email_to_team'

    falta('acao_sem_equivalente', nome)
  end

  CONVERSA = %w[assign_agent assign_team remove_assigned_agent remove_assigned_team add_label remove_label change_status
                resolve open pending_conversation snooze change_priority].freeze

  # Atribuir e tirar: a ação antiga → o campo da rota de atribuição e se o valor vem do parâmetro.
  ATRIBUICAO = { 'assign_agent' => ['assignee_id', true], 'assign_team' => ['team_id', true],
                 'remove_assigned_agent' => ['assignee_id', false], 'remove_assigned_team' => ['team_id', false] }.freeze

  def passo_de_conversa!(nome, params)
    if ATRIBUICAO.key?(nome)
      campo, com_valor = ATRIBUICAO[nome]
      return atribuir!(campo, com_valor ? params.first : nil)
    end

    case nome
    when 'add_label' then acao!(:etiquetas, 'por' => params)
    when 'remove_label' then acao!(:etiquetas, 'tirar' => params)
    when 'change_priority' then acao!(:prioridade, 'priority' => params.first == 'nil' ? nil : params.first)
    else status!(nome, params)
    end
  end

  def atribuir!(campo, valor)
    return falta('atribuir_ultimo_que_respondeu', campo) if valor.to_s == 'last_responding_agent'

    valor = nil if valor.to_s == 'nil' || valor.to_s == '0'
    @ressalvas << "#{campo}_vazio: tirar o responsável pela rota de atribuição" if valor.nil?
    acao!(:atribuir, campo => valor)
  end

  def status!(nome, params)
    status = nome == 'change_status' ? params.first.to_s : Mapa::STATUS_DA_ACAO.fetch(nome)
    @ressalvas << 'adiar_sem_prazo: o antigo adia até a próxima mensagem; o novo pede prazo' if status == 'snoozed'
    acao!(:status, 'status' => status)
  end

  def acao!(qual, corpo)
    acao, caminho = Mapa::ACAO.fetch(qual)
    @passos << { 'id' => "p#{@passos.size + 1}", 'tipo' => 'acao', 'acao' => acao, 'caminho' => caminho,
                 'descricao' => "Convertido da regra #{@regra.id}", 'corpo' => corpo }
  end

  # O texto antigo aceita variável Liquid (`{{contact.name}}`); o novo usa valor estruturado. Texto com variável é
  # convertido pelo conversor (F9), à mão de quem revisa, nunca adivinhado aqui.
  def mensagem!(params)
    texto = params.first.to_s
    return falta('texto_com_variavel', 'send_message') if texto.include?('{{')

    @passos << { 'id' => "p#{@passos.size + 1}", 'tipo' => 'mensagem', 'texto' => [texto] }
  end

  def aviso_por_email!(nome)
    falta('acao_sem_equivalente', "#{nome} (o avisar novo não manda e-mail para o time)")
  end

  def falta(chave, detalhe)
    @faltas << { chave: chave, fase: Mapa::FALTA.fetch(chave), detalhe: detalhe.to_s }
    nil
  end
end
