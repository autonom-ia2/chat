require Rails.root.join('lib/oauth_conexoes_antigas')

# #3106 — a conexão OAuth passa a valer para todas as contas que a pessoa administra. As conexões feitas antes
# prometiam uma conta só; esta migration as desativa (só `revoked_at`, nada é apagado), e a pessoa conecta de novo uma
# vez. O porquê e o como estão em lib/oauth_conexoes_antigas.rb.
#
# O `down` não reativa nada: reativar devolveria justamente a conexão de uma conta com acesso a todas. A volta é
# conectar de novo. O código anterior aguenta o schema e os dados daqui (token desativado já era recusado).
class RevogarConexoesOauthDeUmaConta < ActiveRecord::Migration[7.2]
  def up
    desativadas = OauthConexoesAntigas.revogar!(ate: Time.current)
    say("conexões desativadas: tokens=#{desativadas[:tokens]} autorizações=#{desativadas[:autorizacoes]}")
  end

  def down
    say('nada a desfazer: a conexão desativada volta conectando de novo')
  end
end
