# "Testar antes de ligar" do Decisor (#858): responde a pergunta em conversas reais e mostra os campos
# que extrairia, SEM gravar nada — nem decisão, nem exemplo, nem campo.
#
# Roda dentro da requisição, em sequência, com prazo de 10 s: o rack-timeout de produção mata tudo aos
# 15 s. Primeiro o Jev em todas (~170 ms cada), depois a extração com o tempo que sobrar. Estourou o
# prazo, devolve o que deu: "testei 6 de 10".
#
# Nenhuma chamada repete aqui dentro: uma nova tentativa usaria o prazo inteiro de novo, mais a espera.
# A folga de cada uma é o pior caso dela — o Jev pode levar 3 s para conectar e 3 s para ler. A
# conversa sem texto (só áudio ou imagem) fica de fora: não há o que perguntar.
class Autonomia::Decisores::Teste
  PRAZO = 10.0
  MAX_QUANTIDADE = 10
  QUANTIDADE_PADRAO = 5
  # Abaixo disto não começa uma chamada nova: ela não terminaria antes do teto da requisição.
  JEV_LEITURA = 3
  FOLGA_JEV = TypesafeAi::Client::OPEN_TIMEOUT + JEV_LEITURA
  FOLGA_EXTRACAO = 3.0

  def initialize(decisor:, conversations:, relogio: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @decisor = decisor
    @conversations = conversations
    @relogio = relogio
    @comeco = relogio.call
  end

  def perform
    casos = @conversations.filter_map { |conversation| caso(conversation) }
    resultados = casos.filter_map { |estado| decidir(estado) }
    extrair(resultados) if Array(@decisor.campos).present?
    { resultados: resultados.map { |item| item.except(:estado) }, resumo: resumo(resultados),
      testados: resultados.size, pedidos: casos.size }
  end

  private

  def caso(conversation)
    message = conversation.messages.incoming.reorder(id: :desc).first
    estado = message && Autonomia::Decisores::Estado.new(conversation: conversation, message: message)
    estado unless estado.nil? || estado.vazio?
  end

  def decidir(estado)
    return if restante < FOLGA_JEV

    resultado = jev.decidir(decisor: @decisor, estado: estado)
    duvida = resultado.certeza < @decisor.certeza_minima
    base(estado).merge(resposta: resultado.resposta, certeza: resultado.certeza.round(3), duvida: duvida)
  rescue TypesafeAi::Decisor::Error => e
    base(estado).merge(resposta: nil, certeza: nil, duvida: true, erro: e.code)
  end

  def base(estado)
    conversation = estado.conversation
    { estado: estado, conversation_id: conversation.id, display_id: conversation.display_id,
      contato: conversation.contact&.name, trecho: estado.trecho }
  end

  # Só onde houve resposta segura: na dúvida a automação não seguiria, então não gravaria campo.
  def extrair(resultados)
    resultados.each do |item|
      next item[:campos] = nil if item[:duvida]
      next item[:campos_pendentes] = true if restante < FOLGA_EXTRACAO

      item[:campos] = Autonomia::Decisores::Extrator.new(decisor: @decisor, timeout: (restante - 1).floor, max_retries: 0)
                                                    .extrair(item[:estado])
    rescue Autonomia::Decisores::Extrator::Error => e
      item[:campos] = nil
      item[:erro_campos] = e.message
    end
  end

  def resumo(resultados)
    respondidos = resultados.reject { |item| item[:resposta].nil? }
    { total: resultados.size, por_resposta: respondidos.group_by { |item| item[:resposta] }.transform_values(&:size),
      duvidas: resultados.count { |item| item[:duvida] } }
  end

  def restante
    PRAZO - (@relogio.call - @comeco)
  end

  def jev
    @jev ||= TypesafeAi::Decisor.new(client: TypesafeAi::Client.new(read_timeout: JEV_LEITURA, retry_limit: 0))
  end
end
