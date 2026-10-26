# #2216 — Prepend em Api::V1::Accounts::Conversations::MessagesController (config/initializers/reabrir_ao_escrever.rb).
# A gaveta Nova conversa (e o "Começar conversa" da busca, que abre a mesma gaveta) manda a mensagem para a conversa
# visível de uma caixa com "Reabrir a mesma conversa" pela API de mensagem, com o sinal `reabrir_ao_escrever`. Com o
# sinal, a conversa resolvida ou adiada reabre antes de a mensagem entrar, sem mudar quem cuida (#2067), como na
# criação (Conversations::ReabrirAoEscrever). Sem o sinal, a resposta comum segue como sempre. Nota privada não reabre.
# Permissão: a do envio (BaseController autoriza show? antes; quem só lê, #1800, é recusado ali).
# Na mesma transação: o `create` do Chatwoot devolve 422 sem levantar o erro, então a falha é vista pela mensagem não
# gravada, e a reabertura volta atrás.
module Conversations::ReabrirAoEscreverNaMensagem
  def create
    return super unless reabrir_ao_escrever?

    ActiveRecord::Base.transaction do
      @conversation.reabrir_ao_escrever!
      super
      raise ActiveRecord::Rollback unless @message&.persisted?
    end
  end

  private

  def reabrir_ao_escrever?
    sinal = ActiveModel::Type::Boolean.new.cast(params[:reabrir_ao_escrever])
    privada = ActiveModel::Type::Boolean.new.cast(params[:private])
    sinal == true && privada != true
  end
end
