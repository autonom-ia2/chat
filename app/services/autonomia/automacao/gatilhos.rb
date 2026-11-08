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
#
# Acrescentar um gatilho: a entrada aqui, o tipo no esquema da receita, a frase (en e pt_BR) e, se for evento, o
# método do AutomacaoListener. A Partida, o Executor e a varredura não mudam.
module Autonomia::Automacao::Gatilhos
  Entrada = Data.define(:tipo, :alvo, :origem, :parametros)

  CARD = 'Crm::Card'.freeze
  CONTATO = 'Contact'.freeze
  DA_DATA = %w[campo dias quando hora].freeze

  LISTA = [
    Entrada.new(tipo: 'conversa.criada', alvo: 'Conversation', origem: :evento, parametros: []),
    Entrada.new(tipo: 'conversa.aberta', alvo: 'Conversation', origem: :evento, parametros: []),
    Entrada.new(tipo: 'conversa.resolvida', alvo: 'Conversation', origem: :evento, parametros: []),
    Entrada.new(tipo: 'mensagem.criada', alvo: 'Conversation', origem: :evento, parametros: []),
    Entrada.new(tipo: 'mensagem.falhou', alvo: 'Conversation', origem: :evento, parametros: []),
    Entrada.new(tipo: 'card.criado', alvo: CARD, origem: :evento, parametros: %w[funil_id]),
    Entrada.new(tipo: 'card.entrou_na_etapa', alvo: CARD, origem: :evento, parametros: %w[etapa_id]),
    Entrada.new(tipo: 'card.saiu_da_etapa', alvo: CARD, origem: :evento, parametros: %w[etapa_id]),
    Entrada.new(tipo: 'card.ganho', alvo: CARD, origem: :evento, parametros: %w[funil_id]),
    Entrada.new(tipo: 'card.perdido', alvo: CARD, origem: :evento, parametros: %w[funil_id]),
    Entrada.new(tipo: 'card.reuniao_marcada', alvo: CARD, origem: :evento, parametros: %w[funil_id]),
    Entrada.new(tipo: 'card.reuniao_remarcada', alvo: CARD, origem: :evento, parametros: %w[funil_id]),
    Entrada.new(tipo: 'card.reuniao_cancelada', alvo: CARD, origem: :evento, parametros: %w[funil_id]),
    Entrada.new(tipo: 'card.parado', alvo: CARD, origem: :tempo, parametros: %w[etapa_id dias]),
    Entrada.new(tipo: 'card.data', alvo: CARD, origem: :tempo, parametros: DA_DATA),
    Entrada.new(tipo: 'contato.data', alvo: CONTATO, origem: :tempo, parametros: DA_DATA)
  ].index_by(&:tipo).freeze

  # O evento do emissor do CRM (Crm::Webhooks::Emitter) e os gatilhos que ele pode disparar. O card criado já nasce
  # numa etapa: conta como "entrou" nela, venha da tela, da API, da IA ou de uma automação.
  DO_EVENTO_DO_CARD = {
    Events::Types::CRM_CARD_CREATED => %w[card.criado card.entrou_na_etapa],
    Events::Types::CRM_CARD_MOVED => %w[card.saiu_da_etapa card.entrou_na_etapa],
    Events::Types::CRM_CARD_WON => %w[card.ganho],
    Events::Types::CRM_CARD_LOST => %w[card.perdido],
    Events::Types::CRM_MEETING_SCHEDULED => %w[card.reuniao_marcada],
    Events::Types::CRM_MEETING_RESCHEDULED => %w[card.reuniao_remarcada],
    Events::Types::CRM_MEETING_CANCELED => %w[card.reuniao_cancelada]
  }.freeze

  # Os gatilhos de reunião (G12): só neles a receita lê `reuniao.*`, a reunião da atividade que disparou.
  DE_REUNIAO = %w[card.reuniao_marcada card.reuniao_remarcada card.reuniao_cancelada].freeze

  FALHOU = 'mensagem.falhou'.freeze

  # O pedaço da marca entre o tipo e o id da atividade (marca_da_atividade).
  ATIVIDADE = 'atividade'.freeze

  module_function

  def tipos = LISTA.keys

  def entrada(tipo) = LISTA[tipo.to_s]

  # O tipo do alvo (`Conversation`, `Crm::Card`, `Contact`) do gatilho; nil quando o tipo não existe.
  def alvo(tipo) = entrada(tipo)&.alvo

  def do_card?(tipo) = alvo(tipo) == CARD

  def de_tempo?(tipo) = entrada(tipo)&.origem == :tempo

  # Os tipos que a varredura de tempo acha.
  def de_tempo = LISTA.values.select { |item| item.origem == :tempo }.map(&:tipo)

  # O gatilho vale na conta agora? Os de conversa vêm com o motor; os de card pedem a flag da F6 e o CRM; os de reunião,
  # também as reuniões da instalação ligadas (sem elas nenhuma reunião nasce).
  def disponivel?(tipo, conta)
    return false unless entrada(tipo)
    return ::Autonomia::Automacao::Motor.gatilhos?(conta) && ::Crm::Config.calendar_meetings_enabled? if de_reuniao?(tipo)
    return ::Autonomia::Automacao::Motor.gatilhos?(conta) if do_card?(tipo)
    return ::Autonomia::Automacao::Motor.gatilhos_sem_crm?(conta) if de_tempo?(tipo)

    ::Autonomia::Automacao::Motor.ligado?(conta)
  end

  # Por que o gatilho de card não vale na conta agora (a chave do texto da receita), ou nil quando vale.
  def desligado(tipo, conta)
    return if disponivel?(tipo, conta)

    de_reuniao?(tipo) && ::Autonomia::Automacao::Motor.gatilhos?(conta) ? :reunioes_desligadas : :gatilho_desligado
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

  def de_reuniao?(tipo) = DE_REUNIAO.include?(tipo.to_s)

  # A mensagem que falhou (G8, #2637): a própria mensagem é o fato. O canal que repete o aviso de falha não abre outra.
  def marca_da_falha(mensagem) = "#{FALHOU}:#{mensagem.id}"

  # O id da mensagem numa marca de marca_da_falha; nil em marca de outro formato.
  def mensagem_da_marca(marca)
    tipo, id = marca.to_s.split(':', 2)
    Integer(id, 10, exception: false) if tipo == FALHOU && id
  end

  # O mesmo movimento dispara "saiu" e "entrou": o tipo entra na marca para cada um ter a sua.
  def marca_da_atividade(tipo, activity_id) = "#{tipo}:#{ATIVIDADE}:#{activity_id}"

  # O id da atividade numa marca de marca_da_atividade; nil em marca de outro formato.
  def atividade_da_marca(marca)
    tipo, pedaco, id = marca.to_s.split(':', 3)
    Integer(id, 10, exception: false) if tipo.present? && pedaco == ATIVIDADE && id
  end

  # Parado: o instante em que o card entrou na etapa. Se ele sair e voltar, o instante muda e conta de novo.
  def marca_do_parado(card) = "card.parado:#{card.id}:#{card.entered_stage_at.utc.iso8601(6)}"

  # A data do campo: uma vez por alvo, campo e dia.
  def marca_da_data(tipo, alvo, campo, dia) = "#{tipo}:#{alvo.id}:#{campo}:#{dia.iso8601}"
end
