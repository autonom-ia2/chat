# #2216 — Prepend em Api::V1::Accounts::Conversations::MessagesController (config/initializers/reabrir_ao_escrever.rb).
# A gaveta Nova conversa (e o "Começar conversa" da busca, que abre a mesma gaveta) manda a mensagem para a conversa
# visível de uma caixa com "Reabrir a mesma conversa" pela API de mensagem, com o sinal `reabrir_ao_escrever`. Com o
# sinal, a conversa resolvida ou adiada reabre antes de a mensagem entrar, sem mudar quem cuida (#2067). Sem o sinal,
# a resposta comum segue como sempre.
# Só pessoa com sessão do painel: token de API (de pessoa ou de robô/n8n), token de integração e MCP ficam fora, porque
# os fluxos deles (avisos, lembretes, agentes) não decidiram reabrir conversa. Nota privada nunca reabre.
# Permissão: a do envio (BaseController autoriza show? antes; quem só lê, #1800, e quem só atende as conversas em que
# participa são recusados ali).
# A conversa oculta (a pessoa não pode vê-la, #1505) vai pela criação de conversa, que entra nela e não reabre: ela
# continua resolvida ou adiada até o cliente responder (Message#reopen_conversation).
# Na mesma transação: o `create` do Chatwoot devolve 422 sem levantar o erro, então a falha é vista pela mensagem não
# gravada, e a reabertura volta atrás.
module Conversations::ReabrirAoEscreverNaMensagem
  def create
    return super unless pedido_de_reabrir?

    ActiveRecord::Base.transaction do
      @conversation.reabrir_ao_escrever!
      super
      raise ActiveRecord::Rollback unless @message&.persisted?
    end
  end

  private

  def pedido_de_reabrir?
    sinal = ActiveModel::Type::Boolean.new.cast(params[:reabrir_ao_escrever])
    privada = ActiveModel::Type::Boolean.new.cast(params[:private])
    sinal == true && privada != true && sessao_do_painel?
  end

  def sessao_do_painel?
    Current.user.is_a?(User) && !authenticate_by_access_token? && !integration_token_request?
  end
end
