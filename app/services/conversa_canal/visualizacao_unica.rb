# Mensagem de visualização única do WhatsApp (#1702). Decisão do Rodrigo (16/10): quando o provedor entrega a mídia, o
# chat2you guarda e mostra ao atendente, como qualquer foto, vídeo ou áudio. A marca `meta.is_view_once` no anexo (no
# padrão de `is_sticker`) só diz que o cliente mandou como "ver uma vez". Nada se esconde, expira ou apaga. Sem coluna.
#
# O que cada provedor entrega (pesquisado em 16/10):
# - Cloud API e 360dialog: a Meta não manda a mídia. Chega `type: "unsupported"` (erro 131051), e a lista oficial de
#   `unsupported.type` não tem valor para visualização única. Sem sinal confiável, continua o aviso genérico de "não
#   suportada" (Whatsapp::IncomingMessageBaseService#create_unsupported_message). O WhatsApp Híbrido recebe pela
#   Cloud, então vale o mesmo.
# - Caixa WAHA comum: quem cria a mensagem é o conector do WAHA, pela API da caixa. A conversão para esta marca é do
#   #1709 (WhatsApp Híbrido), atrás da flag `whatsapp_rich_native`. Se o aparelho vinculado não recebeu a chave da
#   mídia, não há arquivo para guardar.
module ConversaCanal::VisualizacaoUnica
  CHAVE = 'is_view_once'.freeze

  module_function

  def marcado?(anexo)
    anexo.meta.is_a?(Hash) && anexo.meta[CHAVE] == true
  end
end
