# A primeira mensagem de verdade da conversa (#2527): nem atividade da plataforma nem nota interna, na ordem em que
# aconteceu (created_at; no empate, o id). Diz quem começou a conversa e se a mensagem do gatilho é a primeira.
#
# O histórico importado (coexistência do WhatsApp) chega com a data original: é ele que diz quem começou, e a mensagem
# nova não é a primeira. A conversa resolvida que o cliente reabre continua começada por quem a começou.
#
# A conversa que nasce de comentário (#2526): quem a abriu foi a plataforma, não o cliente. Vale para todo filtro
# conversa.iniciada_por, não só para a Boas-vindas.
# - A que a IA dos comentários abre para a equipe (Crm::MetaAds::ComentariosIa::Conversa.para_voce!, Instagram e
#   Facebook) só tem atividade até o cliente escrever no direct: é "equipe" já de saída, pela marca `meta_ads_comment`.
# - A do privado (`private_reply` na marca, pelo anotar!) segue a primeira mensagem: na conversa nova é o privado que
#   saiu (equipe); na que o cliente já tinha aberta na caixa, é a dele (cliente).
# - O privado que a pessoa da equipe manda pela tela (InstagramPrivateReply) não marca a conversa, e a primeira
#   mensagem já é o privado que saiu (equipe).
module Autonomia::Automacao::PrimeiraMensagem
  module_function

  def da(conversa) = conversa.messages.chat.reorder(:created_at, :id).first

  # "cliente" quando a primeira chegou do cliente; "equipe" quando saiu daqui (resposta, modelo, campanha); vazio sem
  # mensagem, como na conversa recém-criada cuja mensagem ainda não foi gravada.
  def iniciada_por(conversa)
    return 'equipe' if aberta_para_o_comentario?(conversa)

    primeira = da(conversa)
    return if primeira.nil?

    primeira.incoming? ? 'cliente' : 'equipe'
  end

  def primeira?(mensagem)
    primeira = da(mensagem.conversation)
    primeira.present? && primeira.id == mensagem.id
  end

  def aberta_para_o_comentario?(conversa)
    origem = conversa.additional_attributes.to_h['meta_ads_comment']
    origem.is_a?(Hash) && origem['private_reply'] != true
  end
end
