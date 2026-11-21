# #3106 — antes deste PR, uma conexão OAuth (Claude, ChatGPT, Em d.ia) valia para a conta escolhida no consentimento.
# Agora vale para todas as contas que a pessoa administra. Uma conexão feita com a promessa antiga não pode ganhar as
# outras contas sem novo consentimento, então ela é desativada e a pessoa conecta de novo uma vez.
#
# Desativar é só `revoked_at`: nada é apagado. Não se desfaz: a volta é conectar de novo (o token desativado não volta
# a valer, e o app pede o consentimento outra vez sozinho).
#
# Usado pela migration 20261121140000 (no deploy, antes da troca de tráfego) e pela tarefa
# `mcp:revogar_conexoes_antigas`, que a Orquestração roda logo depois da troca para pegar uma conexão que o servidor
# antigo tenha emitido enquanto a migration já tinha rodado (docs/mcp-nativo.md).
module OauthConexoesAntigas
  module_function

  # Desativa os tokens e as autorizações ainda ativos criados até `ate`. Devolve quantos de cada.
  # update_all de propósito: só o revoked_at, em lote, sem callback (o mesmo que o Doorkeeper faz ao revogar).
  def revogar!(ate:)
    agora = Time.current
    # rubocop:disable Rails/SkipsModelValidations
    {
      tokens: Doorkeeper::AccessToken.where(revoked_at: nil, created_at: ..ate).update_all(revoked_at: agora),
      autorizacoes: Doorkeeper::AccessGrant.where(revoked_at: nil, created_at: ..ate).update_all(revoked_at: agora)
    }
    # rubocop:enable Rails/SkipsModelValidations
  end
end
