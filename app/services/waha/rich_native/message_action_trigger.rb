# A entrega do evento de reação ou edição ao conector (Waha::RichNative::MessageActionDeliveryJob), pelos mesmos cabeçalhos,
# assinatura e tempos do Webhooks::Trigger, mas LEVANTANDO na falha: o original só registra o erro, e o job precisa
# saber que não chegou para tentar de novo.
class Waha::RichNative::MessageActionTrigger < Webhooks::Trigger
  def execute
    perform_request
  end
end
