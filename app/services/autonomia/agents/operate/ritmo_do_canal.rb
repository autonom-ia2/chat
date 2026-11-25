# PARIDADE DA CONVERSA (#3211), P5: o ritmo dos pedaços por canal, só com `conversa_ritmo_do_canal` ligada no agente.
# Reescreve o `delay_ms` de cada pedaço (a espera ANTES de postá-lo), sem tocar no resto:
#   - pausa pós-envio: o pedaço `i` espera, a mais, uma pausa que depende da espera do pedaço anterior (1–3 s);
#   - WhatsApp oficial: o "digitando" some em 25 s. A espera fica cheia no 1º pedaço e quando o pedaço cruza uma
#     fronteira de 25 s acumulados (o digitando recomeça); nos demais, vale 1/5 da espera.
# Função pura: devolve hashes novos e não muta a entrada.
module Autonomia::Agents::Operate::RitmoDoCanal
  JANELA_DO_DIGITANDO_MS = 25_000
  FRACAO_DA_ESPERA = 5
  PAUSAS_MS = [[3_000, 1_000], [15_000, 2_000]].freeze
  PAUSA_MAXIMA_MS = 3_000
  PROVEDOR_OFICIAL = 'whatsapp_cloud'.freeze

  module_function

  # Pausa depois de postar, conforme a espera que o pedaço teve (do fluxo externo, passo `Wait1`).
  def pausa_depois_do_envio(espera_ms)
    PAUSAS_MS.each { |teto, pausa| return pausa if espera_ms <= teto }
    PAUSA_MAXIMA_MS
  end

  def aplicar(chunks, whatsapp_oficial:)
    esperas = chunks.map { |pedaco| pedaco['delay_ms'].to_i }
    acumulado = 0
    chunks.each_with_index.map do |pedaco, i|
      antes = acumulado
      acumulado += esperas[i]
      espera = espera_do_pedaco(esperas[i], antes, acumulado, i, whatsapp_oficial)
      pausa = i.positive? ? pausa_depois_do_envio(esperas[i - 1]) : 0
      pedaco.merge('delay_ms' => espera + pausa)
    end
  end

  def whatsapp_oficial?(conversation)
    canal = conversation&.inbox&.channel
    canal.is_a?(::Channel::Whatsapp) && canal.provider == PROVEDOR_OFICIAL
  end

  def para(chunks, agent:, conversation:)
    return chunks unless ::Autonomia::Agents::ParidadeDaConversa.ritmo_do_canal?(agent, conversation&.inbox)

    aplicar(chunks, whatsapp_oficial: whatsapp_oficial?(conversation))
  end

  def espera_do_pedaco(espera, antes, depois, indice, whatsapp_oficial)
    return espera unless whatsapp_oficial && indice.positive?
    # Cruzou a fronteira de 25 s: o "digitando" recomeça, a espera é cheia.
    return espera unless depois / JANELA_DO_DIGITANDO_MS == antes / JANELA_DO_DIGITANDO_MS

    (espera / FRACAO_DA_ESPERA.to_f).round
  end
  private_class_method :espera_do_pedaco
end
