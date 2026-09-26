# RECUSAS ANTIGAS PASSAM PARA O CONTATO (chat#713).
#
# Leads em no_consent (recusados antes da coluna consent_refused_at) e descadastros de e-mail já gravados eram pedidos
# para não receber mensagem ativa que o contato não carregava. O job marca os contatos, conta por conta, fora do deploy.
# Migration separada da 20260926170000 para o job só rodar depois de a coluna da recusa do lead estar gravada.
# Nada a desfazer no down: tirar a recusa de quem pediu não é reversão de schema.
class EnqueueBackfillContactOptOutJob < ActiveRecord::Migration[7.2]
  def up
    Migration::BackfillContactOptOutJob.perform_later
  end

  def down; end
end
