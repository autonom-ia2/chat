# Os gatilhos da Automação livre num lugar só (#2499, F6). Cada entrada diz em quem a execução roda (`alvo`), de onde
# o gatilho vem (`origem`: o despacho de eventos ou a varredura de tempo), o que a pessoa escolhe nele (`parametros`) e
# como o evento vira a marca única da coluna `evento` da execução.
#
# A marca é o que impede o mesmo fato de abrir duas execuções: o EventDispatcherJob repete o evento, e o índice único
# (automacao_id, evento) do #2494 barra a segunda, mesmo depois de a primeira fechar. Evento sem id próprio usa o
# instante do despacho com microssegundos, nunca o segundo: reabrir e resolver no mesmo segundo são dois fatos. O card
# usa o id da atividade (Crm::Activity), que nasce no mesmo commit da mudança.
#
# Os parâmetros (`etapa_id`, `funil_id`) são opcionais ou obrigatórios pelo esquema da receita; o evento traz o valor
# dele, e o gatilho só casa quando cada parâmetro escolhido bate com o do evento.
#
# Os de tempo (#2499, PR3) não vêm de evento: a varredura (TempoJob) acha os alvos da janela pelos parâmetros (`dias`,
# a data de um campo, a hora) e a marca é o próprio fato ("parado desde tal instante", "a data do campo vale tal dia").
# O recorrente (#2635, G7) também é da varredura: na ocorrência (todo dia, toda semana, todo mês, numa hora), age em
# cada card ou contato da seleção, e a marca é a ocorrência com o alvo. O conta.recorrente não tem seleção: roda uma vez
# por ocorrência, com a própria conta como alvo (o "disparar" de campanha da G14 escolhe o público), e a marca é só a
# ocorrência.
#
# Acrescentar um gatilho: a entrada aqui, o tipo no esquema da receita, a frase (en e pt_BR) e, se for evento, o
# método do AutomacaoListener. A Partida, o Executor e a varredura não mudam.
module Autonomia::Automacao::Gatilhos
  Entrada = Data.define(:tipo, :alvo, :origem, :parametros)

  CARD = 'Crm::Card'.freeze
  CONTATO = 'Contact'.freeze
  CONTA = 'Account'.freeze
  DA_DATA = %w[campo dias quando hora].freeze
  DO_RECORRENTE = %w[frequencia dia_da_semana dia_do_mes hora selecao].freeze
  DA_OCORRENCIA = %w[frequencia dia_da_semana dia_do_mes hora].freeze
  VARRIDOS = %i[tempo recorrente].freeze

  LISTA = [
    Entrada.new(tipo: 'conversa.criada', alvo: 'Conversation', origem: :evento, parametros: []),
    Entrada.new(tipo: 'conversa.aberta', alvo: 'Conversation', origem: :evento, parametros: []),
    Entrada.new(tipo: 'conversa.resolvida', alvo: 'Conversation', origem: :evento, parametros: []),
    Entrada.new(tipo: 'mensagem.criada', alvo: 'Conversation', origem: :evento, parametros: []),
    Entrada.new(tipo: 'card.criado', alvo: CARD, origem: :evento, parametros: %w[funil_id]),
    Entrada.new(tipo: 'card.entrou_na_etapa', alvo: CARD, origem: :evento, parametros: %w[etapa_id]),
    Entrada.new(tipo: 'card.saiu_da_etapa', alvo: CARD, origem: :evento, parametros: %w[etapa_id]),
    Entrada.new(tipo: 'card.ganho', alvo: CARD, origem: :evento, parametros: %w[funil_id]),
    Entrada.new(tipo: 'card.perdido', alvo: CARD, origem: :evento, parametros: %w[funil_id]),
    Entrada.new(tipo: 'card.parado', alvo: CARD, origem: :tempo, parametros: %w[etapa_id dias]),
    Entrada.new(tipo: 'card.data', alvo: CARD, origem: :tempo, parametros: DA_DATA),
    Entrada.new(tipo: 'contato.data', alvo: CONTATO, origem: :tempo, parametros: DA_DATA),
    Entrada.new(tipo: 'card.recorrente', alvo: CARD, origem: :recorrente, parametros: DO_RECORRENTE),
    Entrada.new(tipo: 'contato.recorrente', alvo: CONTATO, origem: :recorrente, parametros: DO_RECORRENTE),
    Entrada.new(tipo: 'conta.recorrente', alvo: CONTA, origem: :recorrente, parametros: DA_OCORRENCIA)
  ].index_by(&:tipo).freeze

  # O evento do emissor do CRM (Crm::Webhooks::Emitter) e os gatilhos que ele pode disparar. O card criado já nasce
  # numa etapa: conta como "entrou" nela, venha da tela, da API, da IA ou de uma automação.
  DO_EVENTO_DO_CARD = {
    Events::Types::CRM_CARD_CREATED => %w[card.criado card.entrou_na_etapa],
    Events::Types::CRM_CARD_MOVED => %w[card.saiu_da_etapa card.entrou_na_etapa],
    Events::Types::CRM_CARD_WON => %w[card.ganho],
    Events::Types::CRM_CARD_LOST => %w[card.perdido]
  }.freeze

  module_function

  def tipos = LISTA.keys

  def entrada(tipo) = LISTA[tipo.to_s]

  # O tipo do alvo (`Conversation`, `Crm::Card`, `Contact`, `Account`) do gatilho; nil quando o tipo não existe.
  def alvo(tipo) = entrada(tipo)&.alvo

  def do_card?(tipo) = alvo(tipo) == CARD

  # Os da varredura: os de tempo e o recorrente.
  def de_tempo?(tipo) = VARRIDOS.include?(entrada(tipo)&.origem)

  def recorrente?(tipo) = entrada(tipo)&.origem == :recorrente

  # O conta.recorrente: sem seleção, uma execução por ocorrência na própria conta.
  def da_conta?(tipo) = alvo(tipo) == CONTA

  # Os tipos que a varredura de tempo acha.
  def de_tempo = LISTA.values.select { |item| VARRIDOS.include?(item.origem) }.map(&:tipo)

  # O gatilho vale na conta agora? Os de conversa vêm com o motor; os de card pedem a flag da F6 e o CRM; o de tempo
  # do contato pede a flag, mas não o CRM.
  def disponivel?(tipo, conta)
    return false unless entrada(tipo)
    return ::Autonomia::Automacao::Motor.gatilhos?(conta) if do_card?(tipo)
    return ::Autonomia::Automacao::Motor.gatilhos_sem_crm?(conta) if de_tempo?(tipo)

    ::Autonomia::Automacao::Motor.ligado?(conta)
  end

  # Cada parâmetro escolhido no gatilho (`gatilho` da receita) bate com o que o evento traz (`dados`)? O que a pessoa
  # deixou em branco vale para qualquer valor.
  def casa?(gatilho, dados)
    entrada(gatilho['tipo'])&.parametros.to_a.all? do |nome|
      gatilho[nome].nil? || gatilho[nome].to_i == dados[nome].to_i
    end
  end

  # A marca de um evento do despacho sem id próprio: "conversa.aberta:<id>:<instante em µs, UTC>".
  def marca_do_despacho(tipo, registro, instante)
    "#{tipo}:#{registro.id}:#{instante.utc.iso8601(6)}"
  end

  # O mesmo movimento dispara "saiu" e "entrou": o tipo entra na marca para cada um ter a sua.
  def marca_da_atividade(tipo, activity_id) = "#{tipo}:atividade:#{activity_id}"

  # Parado: o instante em que o card entrou na etapa. Se ele sair e voltar, o instante muda e conta de novo.
  def marca_do_parado(card) = "card.parado:#{card.id}:#{card.entered_stage_at.utc.iso8601(6)}"

  # A data do campo: uma vez por alvo, campo e dia.
  def marca_da_data(tipo, alvo, campo, dia) = "#{tipo}:#{alvo.id}:#{campo}:#{dia.iso8601}"

  # O recorrente: uma vez por ocorrência e alvo; o da conta, uma vez por ocorrência. A ocorrência em UTC: a hora local
  # ambígua do horário de verão não repete nem pula.
  def marca_do_recorrente(tipo, alvo_id, ocorrencia)
    marca = "recorrente:#{ocorrencia.utc.iso8601}:#{tipo}"
    da_conta?(tipo) ? marca : "#{marca}:#{alvo_id}"
  end
end
