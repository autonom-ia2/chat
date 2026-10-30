# #2211 — as conversas que a lista de conversas mostra a esta pessoa, para a busca da lista mostrar exatamente as
# mesmas. Segue o ConversationFinder da lista, sem regra nova:
# - acesso: Conversations::PermissionFilterService com for_reading (caixa, funil, funções personalizadas; quem só lê,
#   pelo conversation_view, também acha);
# - a conversa "Integração WhatsApp" do conector fica de fora (Waha::ConversationFinderSemIntegracao);
# - com a conversa de e-mail nova ligada, o que está no Spam ou na Lixeira do painel fica de fora
#   (ConversaCanal::ConversationFinderComPastas, sem `pasta` pedida).
class SearchService::ConversasVisiveisNaLista
  def initialize(user:, account:)
    @user = user
    @account = account
  end

  def conversas
    permitidas = Conversations::PermissionFilterService.new(@account.conversations, @user, @account, for_reading: true).perform
    visiveis = permitidas.fora_da_integracao_whatsapp
    return visiveis unless @account.feature_enabled?('conversa_email_nova')

    visiveis.where.not(id: ConversaCanal::PastaDoEmail.where(account_id: @account.id).select(:conversation_id))
  end
end
