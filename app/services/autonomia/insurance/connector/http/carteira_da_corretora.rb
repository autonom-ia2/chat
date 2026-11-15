# A CARTEIRA DA CORRETORA no transporte real (E7, #2900; contrato em `client.rb`). O corpo vai em camelCase, como o
# adapter lê; a resposta volta traduzida para snake_case em `normalize_keys`, como todas. Usa o `invoke` da classe.
module Autonomia::Insurance::Connector::Http::CarteiraDaCorretora
  def portfolio_sync_start(provider:, session:, desde:, ate:)
    invoke("/v1/#{provider}/portfolio/sync/start", { session: session, desde: desde, ate: ate })
  end

  def portfolio_sync_status(provider:, session:, sync_id:)
    invoke("/v1/#{provider}/portfolio/sync/status", { session: session, syncId: sync_id })
  end

  def portfolio_policies(provider:, session:, sync_id:, cursor: nil)
    payload = { session: session, syncId: sync_id }
    payload[:cursor] = cursor if cursor.present?
    invoke("/v1/#{provider}/portfolio/policies", payload)
  end

  def portfolio_document(provider:, session:, ref:)
    invoke("/v1/#{provider}/portfolio/document", { session: session, ref: ref })
  end
end
