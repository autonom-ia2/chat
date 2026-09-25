# Recusa depois do segmento (#732) fora da requisição: o PATCH do lead e o descarte em lote gravam a recusa e respondem;
# este job tira as etiquetas de segmento dos contatos recusados (SegmentRefusalSync). Rodar de novo não muda nada, então
# a repetição do Sidekiq numa falha geral é segura; a falha de um contato já fica no registro sem derrubar o job.
class Autonomia::Prospecting::SegmentRefusalSyncJob < ApplicationJob
  queue_as :prospecting

  def perform(account_id, lead_ids)
    account = Account.find_by(id: account_id)
    return if account.nil?

    Autonomia::Prospecting::SegmentRefusalSync.new(account: account).perform(lead_ids)
  end
end
