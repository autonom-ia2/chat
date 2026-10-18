# Depois do create da mensagem (#1702): se ela pode ganhar prévia de link, agenda a leitura da página na fila low.
# A conferência aqui é barata (chave da conta, tipo da mensagem, primeiro endereço do texto); a página só é lida no
# job (ConversaCanal::PreviaDeLinkJob). Registrado como `after_commit on: :create` em
# config/initializers/conversa_canal_previa_de_link.rb, sem tocar no model do Chatwoot.
class ConversaCanal::PreviaDeLinkNaMensagem
  def self.after_commit(message)
    return unless ConversaCanal::PreviaDeLink.buscar?(message)

    ConversaCanal::PreviaDeLinkJob.perform_later(message.id)
  end
end
