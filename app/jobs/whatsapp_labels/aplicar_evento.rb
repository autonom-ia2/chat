# Evento de etiqueta do app WhatsApp Business do celular (#1823, F1b). Quem chama é o webhook de etiquetas do Híbrido
# (Waha::LabelsWebhookController), que confere a assinatura, normaliza e já tira os grupos. Contrato do `evento`:
#   { inbox_id, chat_id, contact_phone (E.164 ou nil), label_wa_id, nome, color_index,
#     acao: 'criada' | 'renomeada' | 'apagada' | 'vinculada' | 'desvinculada', origem: 'celular', at (ISO8601) }
# O trabalho fica no Etiquetas::AplicarEventoDoCelular; sem a flag `etiquetas_do_celular` na conta da caixa, nada muda.
# Erro de banco sobe (a fila tenta de novo); evento malformado é descartado com log.
class WhatsappLabels::AplicarEvento < ApplicationJob
  queue_as :default

  # Evento malformado (ação desconhecida, `at` inválido) nunca vai dar certo: descarta com log, sem o telefone.
  discard_on Etiquetas::AplicarEventoDoCelular::EventoInvalido do |job, error|
    evento = job.arguments.first.to_h.with_indifferent_access
    Rails.logger.warn("[etiquetas_do_celular] evento inválido descartado: #{error.class} inbox=#{evento[:inbox_id]} " \
                      "acao=#{evento[:acao]}")
  end

  def perform(evento)
    Etiquetas::AplicarEventoDoCelular.new(evento).perform
  end
end
