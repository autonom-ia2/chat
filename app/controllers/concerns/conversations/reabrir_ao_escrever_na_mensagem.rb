# #2216 — Prepend em Api::V1::Accounts::Conversations::MessagesController (config/initializers/reabrir_ao_escrever.rb).
# A gaveta Nova conversa (e o "Começar conversa" da busca, que abre a mesma gaveta) manda a mensagem para a conversa
# visível de uma caixa com "Reabrir a mesma conversa" pela API de mensagem, com o sinal `reabrir_ao_escrever`. Com o
# pedido (Conversations::PedidoDeReabrir: sinal, pessoa com sessão do painel, mensagem que não é nota privada), a
# conversa resolvida ou adiada reabre antes de a mensagem entrar, sem mudar quem cuida (#2067), como na criação
# (Conversations::ReabrirAoEscrever). Sem o pedido, a resposta comum segue como sempre.
# Permissão: a do envio (BaseController autoriza show? antes; quem só lê, #1800, e quem só atende as conversas em que
# participa são recusados ali).
# Na mesma transação: o `create` do Chatwoot devolve 422 sem levantar o erro, então a falha é vista pela mensagem não
# gravada, e a reabertura volta atrás.
module Conversations::ReabrirAoEscreverNaMensagem
  include Conversations::PedidoDeReabrir

  def create
    return super unless pedido_de_reabrir?(privada: ActiveModel::Type::Boolean.new.cast(params[:private]))

    ActiveRecord::Base.transaction do
      @conversation.reabrir_ao_escrever!
      super
      raise ActiveRecord::Rollback unless @message&.persisted?
    end
  end
end
