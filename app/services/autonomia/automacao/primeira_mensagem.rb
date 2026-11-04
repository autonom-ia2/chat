# A primeira mensagem de verdade da conversa (#2527): nem atividade da plataforma nem nota interna, na ordem em que
# aconteceu (created_at; no empate, o id). Diz quem começou a conversa e se a mensagem do gatilho é a primeira.
#
# O histórico importado (coexistência do WhatsApp) chega com a data original: é ele que diz quem começou, e a mensagem
# nova não é a primeira. A conversa resolvida que o cliente reabre continua começada por quem a começou.
module Autonomia::Automacao::PrimeiraMensagem
  module_function

  def da(conversa) = conversa.messages.chat.reorder(:created_at, :id).first

  # "cliente" quando a primeira chegou do cliente; "equipe" quando saiu daqui (resposta, modelo, campanha); vazio sem
  # mensagem, como na conversa recém-criada cuja mensagem ainda não foi gravada.
  def iniciada_por(conversa)
    primeira = da(conversa)
    return if primeira.nil?

    primeira.incoming? ? 'cliente' : 'equipe'
  end

  def primeira?(mensagem)
    primeira = da(mensagem.conversation)
    primeira.present? && primeira.id == mensagem.id
  end
end
