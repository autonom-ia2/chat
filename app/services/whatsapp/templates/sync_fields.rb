# Sync dos modelos com a lista de campos explícita (#1330). Sem `fields=` a Graph não manda o motivo de recusa nem a
# qualidade; com `fields=` ela manda SÓ o que foi pedido. Por isso a lista cobre tudo o que alguém já lê de
# `channel_whatsapp.message_templates`: envio (`TemplateProcessorService`: name, language, status, components), guard de
# autenticação (category), pedido de contato (components[].buttons), agendamento (name, language, status, category,
# components com type/text/format/buttons[].url, rejected_reason), CRM, relatório de anúncios e o painel
# (`TemplateNormalizer`: parameter_format; prévia: sub_category). Mais o que a tela nova de Modelos usa: id,
# quality_score, correct_category e previous_category.
#
# Prependido em `Whatsapp::Providers::WhatsappCloudService` por `config/initializers/whatsapp_templates.rb`. A
# paginação segue a do Chatwoot (cursor `paging.cursors.after`); a recursão passa por este método, então toda página
# pede os mesmos campos.
#
# Se a Graph recusar um campo (400, código 100), o sync desce de nível em vez de parar de atualizar a lista:
# `full` (FIELDS) → `minimal` (MINIMAL_FIELDS, o que o envio e o agendamento leem) → `none` (sem `fields=`, como o
# Chatwoot; aí o motivo de recusa some, por isso `error` no log). O nível escolhido vale para as páginas seguintes.
module Whatsapp::Templates::SyncFields
  FIELDS = %w[id name language status category sub_category previous_category correct_category parameter_format
              components rejected_reason quality_score].join(',').freeze
  MINIMAL_FIELDS = %w[id name language status category components rejected_reason].join(',').freeze
  LEVELS = { 'full' => FIELDS, 'minimal' => MINIMAL_FIELDS }.freeze
  NEXT_LEVEL = { 'full' => 'minimal', 'minimal' => 'none' }.freeze
  # A Graph responde 400 com o código 100 quando não reconhece um parâmetro (um campo, por exemplo).
  INVALID_PARAMETER = 100

  def fetch_whatsapp_templates(after: nil)
    level = sync_fields_level
    return super if level == 'none'

    query = { fields: LEVELS.fetch(level) }
    query[:after] = after if after.present?
    response = HTTParty.get("#{business_account_path}/message_templates",
                            headers: { 'Authorization' => "Bearer #{whatsapp_channel.template_access_token}" }, query: query)
    if fields_refused?(response)
      lower_fields_level(response)
      return fetch_whatsapp_templates(after: after)
    end
    return failed_sync(response) unless response.success?

    next_cursor = response.dig('paging', 'cursors', 'after')
    return response['data'] + fetch_whatsapp_templates(after: next_cursor) if next_cursor.present?

    response['data']
  end

  private

  def sync_fields_level
    @sync_fields_level ||= 'full'
  end

  def lower_fields_level(response)
    @sync_fields_level = NEXT_LEVEL.fetch(sync_fields_level)
    message = "[whatsapp][templates] sync_fields_refused fields_level=#{@sync_fields_level} " \
              "account_id=#{whatsapp_channel.account_id} inbox_id=#{whatsapp_channel.inbox&.id} http=#{response.code}"
    @sync_fields_level == 'none' ? Rails.logger.error(message) : Rails.logger.warn(message)
  end

  def fields_refused?(response)
    return false unless response.code.to_i == 400

    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    error.is_a?(Hash) && error['code'].to_i == INVALID_PARAMETER
  end

  def failed_sync(response)
    Rails.logger.warn "[WHATSAPP] Template sync failed for account #{whatsapp_channel.account_id} " \
                      "inbox #{whatsapp_channel.inbox&.id}: #{response.code} #{error_message(response)}"
    []
  end
end
