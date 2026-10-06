# O que fazer quando a Meta recusa uma leitura de insights (#1073).
#
# - Limite de uso: pausa a conta de anúncios (Usage); a conexão continua como está (CA-2.2).
# - Token recusado: mesma regra das outras leituras (mark_invalid!; no modo parceira, só o código).
# - Sem permissão ou objeto inexistente na conta de anúncios: o cliente retirou o compartilhamento ou a chave
#   perdeu o acesso; a conta para de ser lida e o passo 1 mostra o motivo (CA-2.6).
# - Qualquer outra coisa é passageira: fica no log do cliente da Graph e a próxima rodada tenta de novo.
module Crm::MetaAds::Insights::Failure
  module_function

  # Devolve o símbolo do que aconteceu, para quem chama registrar.
  def handle!(connection, result)
    return :paused if Crm::MetaAds::Insights::Usage.track!(connection.ad_account_id, result)

    if result.token_invalid?
      connection.mark_invalid!(result.error_message)
      :token_invalid
    elsif result.scope_error? || result.object_error?
      connection.mark_access_lost!
      :access_lost
    else
      :transient
    end
  end
end
