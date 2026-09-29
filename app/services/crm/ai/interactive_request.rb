# Estado temporário, como Autonomia::Guide::Pedido. Nunca entra no banco de negócio.
class Crm::Ai::InteractiveRequest
  TTL = 30.minutes
  PREFIX = 'crm:ai:interactive:'.freeze

  def self.create(account_user:, operation:, inputs:, locale:, integration_token_id: nil)
    id = SecureRandom.uuid
    data = { 'account_id' => account_user.account_id, 'account_user_id' => account_user.id,
             'operation' => operation, 'inputs' => inputs, 'locale' => locale,
             'integration_token_id' => integration_token_id, 'status' => 'pending' }
    Redis::Alfred.set("#{PREFIX}#{id}", data.to_json, ex: TTL.to_i)
    id
  end

  def self.read(id)
    value = Redis::Alfred.get("#{PREFIX}#{id}")
    JSON.parse(value) if value.present?
  end

  # Sidekiq pode reentregar após reinício. Não repetir ferramentas nem ações de negócio.
  def self.claim(id)
    Redis::Alfred.set("#{PREFIX}#{id}:claimed", '1', nx: true, ex: TTL.to_i)
  end

  def self.finish(id, status:, result: nil)
    data = read(id)
    return if data.nil?

    data['status'] = status
    data['result'] = result
    # KEEPTTL: a conclusão não ressuscita um pedido já expirado.
    Redis::Alfred.with { |conn| conn.set("#{PREFIX}#{id}", data.to_json, xx: true, keepttl: true) }
  end
end
