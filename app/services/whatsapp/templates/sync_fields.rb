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
module Whatsapp::Templates::SyncFields
  FIELDS = %w[id name language status category sub_category previous_category correct_category parameter_format
              components rejected_reason quality_score].join(',').freeze
  # A Graph responde 400 com o código 100 quando não reconhece um parâmetro (um campo, por exemplo).
  INVALID_PARAMETER = 100

  def fetch_whatsapp_templates(after: nil)
    return super if @sync_without_fields

    query = { fields: FIELDS }
    query[:after] = after if after.present?
    response = HTTParty.get("#{business_account_path}/message_templates",
                            headers: { 'Authorization' => "Bearer #{whatsapp_channel.template_access_token}" }, query: query)
    if fields_refused?(response)
      refused_fields(response)
      return super
    end
    return failed_sync(response) unless response.success?

    next_cursor = response.dig('paging', 'cursors', 'after')
    return response['data'] + fetch_whatsapp_templates(after: next_cursor) if next_cursor.present?

    response['data']
  end

  private

  # Se a versão da Graph recusar algum campo, o resto deste sync segue como antes (sem `fields=`) em vez de parar de
  # atualizar a lista. Fica no log para corrigir a lista de campos.
  def refused_fields(response)
    @sync_without_fields = true
    Rails.logger.warn("[whatsapp][templates] sync_fields_refused account_id=#{whatsapp_channel.account_id} " \
                      "inbox_id=#{whatsapp_channel.inbox&.id} http=#{response.code}")
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
