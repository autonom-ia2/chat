# O pedido direto ao WAHA feito pela conversa (reação pelo PUT /api/reaction, lida pelo sendSeen) vai ao motor da
# caixa, o que serve o `webhook_url` dela (Waha::EngineCapabilities.engine_for, #1709), e não ao WAHA_API_URL padrão:
# com mais de um motor, a sessão só existe no motor da caixa. Caixa cujo motor não está em WAHA_RICH_NATIVE_ENGINES: o
# cliente padrão, como antes. A chave é a mesma de todos os motores (Waha::Config.api_key), como no
# Waha::EngineCapabilities.
module ConversaCanal::ClienteDoMotor
  Motor = Struct.new(:api_url, :api_key)

  module_function

  def para(canal)
    motor = Waha::EngineCapabilities.engine_for(canal.webhook_url)
    return Waha::Client.new if motor.blank?

    Waha::Client.new(config: Motor.new(motor.chomp('/'), Waha::Config.api_key))
  end
end
