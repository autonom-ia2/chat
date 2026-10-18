# Por cima do MessagesController#translate do Chatwoot (#1786), sem editar o arquivo dele: sem o Google Tradutor, a
# conversa de e-mail nova traduz pela IA da conta num job (ConversaCanal::TraduzirEmailJob) e responde 202 na hora.
# A tradução chega pelo message.updated. Com o Google ligado, ou fora do e-mail novo, tudo como antes.
# O idioma tem de ser um dos do painel: cada pedido é uma chamada paga na IA da conta. Uma tradução por vez para cada
# mensagem e idioma (ConversaCanal::TraduzirEmailJob.reservar): o pedido repetido enquanto ela corre responde 202 sem
# outro job.
module ConversaCanal::TraducaoEmSegundoPlano
  def translate
    return super unless ConversaCanal::TraducaoDoEmail.em_segundo_plano?(message)
    return head :ok if already_translated_content_available?

    idioma = permitted_params[:target_language].to_s
    return head :unprocessable_entity unless ConversaCanal::TraducaoDoEmail.idioma_do_painel?(idioma)

    ConversaCanal::TraduzirEmailJob.perform_later(message.id, idioma) if ConversaCanal::TraduzirEmailJob.reservar(message.id, idioma)
    head :accepted
  end
end
