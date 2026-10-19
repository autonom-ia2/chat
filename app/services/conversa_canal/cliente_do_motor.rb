# O pedido direto ao WAHA feito pela conversa (reação pelo PUT /api/reaction, lida pelo sendSeen) vai ao motor da
# caixa, o que serve o `webhook_url` dela (Waha::EngineCapabilities.engine_for, #1709), e não ao WAHA_API_URL padrão:
# com mais de um motor, a sessão só existe no motor da caixa. Caixa cujo motor não está em WAHA_RICH_NATIVE_ENGINES: o
# cliente padrão, como antes. A chave é a mesma de todos os motores (Waha::Config.api_key), como no
# Waha::EngineCapabilities. Sem a flag `whatsapp_rich_native`, sempre o cliente padrão (nada muda sem a flag).
module ConversaCanal::ClienteDoMotor
  Motor = Struct.new(:api_url, :api_key)

  module_function

  # Só com a flag `whatsapp_rich_native` na conta; sem ela, o cliente padrão, como na main.
  def para(canal)
    return Waha::Client.new unless Waha::RichNative.enabled?(canal.account)

    motor = Waha::EngineCapabilities.engine_for(canal.webhook_url)
    return Waha::Client.new if motor.blank?

    Waha::Client.new(config: Motor.new(motor.chomp('/'), Waha::Config.api_key))
  end
end
