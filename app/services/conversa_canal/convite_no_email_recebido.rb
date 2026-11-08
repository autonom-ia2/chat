# Por cima do MailPresenter (#1984): o convite de reunião que vem como parte text/calendar entra em
# content_attributes.email.convite (ConversaCanal::ConviteDoEmail). Sem convite, nada muda. O recebimento chama
# serialized_data mais de uma vez por e-mail; o convite é lido uma vez só.
module ConversaCanal::ConviteNoEmailRecebido
  def serialized_data
    @convite_do_email = ConversaCanal::ConviteDoEmail.ler(@mail) unless defined?(@convite_do_email)
    @convite_do_email ? super.merge(convite: @convite_do_email) : super
  end
end
