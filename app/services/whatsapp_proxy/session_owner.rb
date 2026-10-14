# De quem é a sessão do motor e de que tipo (#1516): conta da caixa e Híbrido (conexão auxiliar de caixa Cloud) ou
# WAHA comum (canal API com provider=waha). O tipo escolhe o plano do IP: Híbrido → isp, WAHA → datacenter.
class WhatsappProxy::SessionOwner
  Owner = Struct.new(:account_id, :kind, :inbox_id) do
    def pool
      kind == :hybrid ? 'isp' : 'datacenter'
    end
  end

  def self.find(session_name)
    connection = WhatsappHybrid::Connection.find_by(session_name: session_name)
    return Owner.new(connection.account_id, :hybrid, connection.inbox_id) if connection

    channel = Channel::Api.where("additional_attributes ->> 'provider' = ?", 'waha')
                          .find_by("additional_attributes ->> 'session' = ?", session_name)
    Owner.new(channel.account_id, :waha, channel.inbox&.id) if channel
  end
end
