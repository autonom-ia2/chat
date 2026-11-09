# A mensagem que dispararia agora o gatilho de mensagem, para o ensaio (#2498), que não tem evento. O "Testar este
# passo" (#2500) não lê este arquivo: só herda dele, pelo Ensaio#entrariam, a escolha das conversas em que rodar.
# - "mensagem criada": a última da conversa, pela régua da Escuta (atividade não é mensagem de ninguém; a nota privada
#   conta);
# - "mensagem que falhou" (G53): a última recusada (MensagemQueFalhou.ultima), que faz o `falhou.texto` dos passos
#   mostrar o texto real.
# Nos outros gatilhos não há mensagem.
module Autonomia::Automacao::MensagemDoGatilho
  module_function

  def pede?(tipo) = [::Autonomia::Automacao::Valores::GATILHO_DA_MENSAGEM, falhou].include?(tipo)

  def falhou?(tipo) = tipo == falhou

  def de(conversa, tipo)
    return ::Autonomia::Automacao::MensagemQueFalhou.ultima(conversa) if falhou?(tipo)

    conversa.messages.where.not(message_type: :activity).reorder(created_at: :desc, id: :desc).first if pede?(tipo)
  end

  # O motivo do ensaio quando o gatilho pede a mensagem e ela falta; senão, nil.
  def faltando(tipo, mensagem)
    return if mensagem || !pede?(tipo)

    falhou?(tipo) ? 'sem_mensagem_que_falhou' : 'sem_mensagem'
  end

  def falhou = ::Autonomia::Automacao::MensagemQueFalhou::TIPO
end
