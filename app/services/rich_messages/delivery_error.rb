# Um tipo levanta este erro quando não consegue montar o envio (chat#1473). A mensagem do erro é o motivo que o
# atendente lê: a mensagem do painel fica `failed` com ela, e o job de envio não cai.
class RichMessages::DeliveryError < StandardError
end
