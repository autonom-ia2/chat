# Recusa da resposta de e-mail nova (#1786) na criação da conversa pela API: "Encaminhar sem Para"
# (ConversaCanal::MessageBuilderComCitacao::Recusa) vira 422 com a frase, não 500. O MessagesController#create do Chatwoot
# já devolve 422 para qualquer erro; o ConversationsController#create (conversa nova com a primeira mensagem, numa
# transação) não tinha o rescue. Entra por um include (config/initializers/conversa_canal_email.rb), sem editar o
# controller do Chatwoot.
module ConversaCanal::RecusaDoEmailNaApi
  extend ActiveSupport::Concern

  included do
    rescue_from ConversaCanal::MessageBuilderComCitacao::Recusa do |erro|
      render json: { error: erro.message }, status: :unprocessable_entity
    end
  end
end
