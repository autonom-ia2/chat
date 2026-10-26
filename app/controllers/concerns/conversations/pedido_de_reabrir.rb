# #2216 — Quem pode pedir a reabertura ao escrever (Conversations::ReabrirAoEscrever e ReabrirAoEscreverNaMensagem).
# Só a gaveta Nova conversa pede, com o sinal explícito `reabrir_ao_escrever`, e só uma pessoa com sessão do painel:
# token de API (de pessoa ou de robô/n8n), token de integração e MCP ficam fora, porque os fluxos deles (avisos,
# lembretes, agentes) não decidiram reabrir conversa. Nota privada nunca reabre.
module Conversations::PedidoDeReabrir
  private

  # `privada`: a mensagem é nota privada (já convertida em booleano por quem chama, de onde o pedido a traz).
  def pedido_de_reabrir?(privada:)
    sinal = ActiveModel::Type::Boolean.new.cast(params[:reabrir_ao_escrever])
    sinal == true && privada != true && sessao_do_painel?
  end

  def sessao_do_painel?
    Current.user.is_a?(User) && !authenticate_by_access_token? && !integration_token_request?
  end
end
