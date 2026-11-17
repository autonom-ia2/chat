# A resposta do segurado ao "Algo mudou?" da renovação (E8, #2901), no molde do Crm::BookingNoticeStopReplyListener: a
# mensagem recebida vai a Carteira::Cotacao::Resposta, que casa pelo payload do botão e pela mensagem citada, nunca pelo
# texto. Conta sem a chave da cotação para logo ali (a chave está na conta, sem consulta).
#
# Erro aqui não pode derrubar os outros ouvintes da mensagem: vai ao rastreador.
class Carteira::CotacaoRespostaListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return unless message&.incoming?

    Carteira::Cotacao::Resposta.new(message).call
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: message&.account).capture_exception
  end
end
