# O erro inesperado de um passo do pacote (chat#1709) vai ao rastreador SEM a mensagem original: a de um erro de banco
# ou de parse pode carregar texto do cliente. Vai a mesma classe, com uma mensagem genérica e o backtrace; o log do
# módulo registra só a classe.
module Waha::RichNative::SafeReport
  GENERIC = 'chat#1709: mensagem original omitida'.freeze

  module_function

  def capture(error, account:)
    ChatwootExceptionTracker.new(sanitized(error), account: account).capture_exception
  end

  def sanitized(error)
    copy = begin
      error.class.new(GENERIC)
    rescue StandardError
      StandardError.new("#{error.class}: #{GENERIC}")
    end
    copy.set_backtrace(error.backtrace) if error.backtrace
    copy
  end
end
