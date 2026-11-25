# A RAJADA DO CLIENTE (#3211, P1). Com `conversa_espera_a_fala`, a pergunta enviada à IA é tudo o que o cliente escreveu
# desde a última fala do agente, não só a última mensagem.
#
# "Desde a última fala" conta a FALA, não o pedaço: a entrega em pedaços (ReplyChunker) posta vários outgoing seguidos, e
# com `conversa_entrega_inteira` uma mensagem nova do cliente pode chegar entre o 1º pedaço e o 2º. Os pedaços que vêm
# depois do primeiro (`autonomia_chunk_index` > 0) são continuação da mesma fala e não fecham a rajada; sem isso, a lista
# ficaria vazia (a última outgoing seria um pedaço posterior) e a pergunta seria vazia ou a já respondida. O 1º pedaço
# (índice 0) e qualquer outra saída (pessoa, outro robô) fecham a rajada.
#
# Mensagem automática do Chatwoot (`message_type` template: a coleta de e-mail do site, a saudação, o fora do horário)
# também não fecha: ela é criada logo depois da mensagem do cliente, sem ser fala de ninguém, e fechar nela deixava a
# rajada vazia (a pergunta e a busca na base iam vazias no 1º turno). Antes do #3211 a pergunta já a pulava
# (`last_incoming_message` só olha incoming).
module Autonomia::Agents::Operate::RajadaDoCliente
  CHAVE_DO_PEDACO = 'autonomia_chunk_index'.freeze

  module_function

  # `recent_messages` em ordem cronológica -> as incoming da rajada, em ordem cronológica.
  def mensagens(recent_messages)
    rajada = []
    recent_messages.reverse_each do |message|
      if message.incoming?
        rajada << message
      elsif !continuacao_de_cadeia?(message) && !message.template?
        break
      end
    end
    rajada.reverse
  end

  # O bloco dá o texto de cada mensagem. Tira vazias e repetida SEGUIDA (igual à anterior já aceita); junta com "\n".
  def texto(mensagens)
    anterior = nil
    linhas = mensagens.filter_map do |message|
      linha = yield(message).to_s.strip
      next if linha.empty? || linha == anterior

      anterior = linha
    end
    linhas.join("\n")
  end

  def continuacao_de_cadeia?(message)
    atributos = message.content_attributes
    atributos.respond_to?(:[]) && atributos[CHAVE_DO_PEDACO].to_i.positive?
  end
  private_class_method :continuacao_de_cadeia?
end
