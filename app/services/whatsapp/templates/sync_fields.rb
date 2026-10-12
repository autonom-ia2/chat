# Sync dos modelos com a lista de campos explícita (#1330). Sem `fields=` a Graph não manda o motivo de recusa nem a
# qualidade; com `fields=` ela manda SÓ o que foi pedido. Por isso a lista cobre tudo o que alguém já lê de
# `channel_whatsapp.message_templates`: envio (`TemplateProcessorService`: name, language, status, components), guard de
# autenticação (category), pedido de contato (components[].buttons), agendamento (name, language, status, category,
# components com type/text/format/buttons[].url, rejected_reason), CRM, relatório de anúncios e o painel
# (`TemplateNormalizer`: parameter_format; prévia: sub_category). Mais o que a tela nova de Modelos usa: id,
# quality_score, correct_category e previous_category.
#
# Prependido em `Whatsapp::Providers::WhatsappCloudService` por `config/initializers/whatsapp_templates.rb`. A
# paginação segue a do Chatwoot (cursor `paging.cursors.after`) e toda página pede os mesmos campos.
#
# Se a Graph recusar um campo (400, código 100), o sync desce de nível em vez de parar de atualizar a lista:
# `full` (FIELDS) → `minimal` (MINIMAL_FIELDS, o que o envio e o agendamento leem) → `none` (sem `fields=`, como o
# Chatwoot; aí o motivo de recusa some, por isso `error` no log). O nível escolhido vale para as páginas seguintes.
#
# Sync atômico e com resultado (#1382): uma página que falha (5xx/429, token vencido, rede) derruba o sync inteiro, que
# não grava nada: a lista anterior fica como estava, em vez de virar só as páginas que chegaram. `sync_templates`
# devolve um `Result` (`ok?`, `code`, `count`) para quem pediu "Atualizar" dizer a verdade na tela. O carimbo
# `message_templates_last_updated` antes da busca continua (é o que espaça as tentativas no agendador do Chatwoot) e é
# renovado depois de gravar. A gravação passa por `ChannelList.replace!`, com trava na linha do canal.
module Whatsapp::Templates::SyncFields
  FIELDS = %w[id name language status category sub_category previous_category correct_category parameter_format
              components rejected_reason quality_score].join(',').freeze
  MINIMAL_FIELDS = %w[id name language status category components rejected_reason].join(',').freeze
  LEVELS = { 'full' => FIELDS, 'minimal' => MINIMAL_FIELDS }.freeze
  NEXT_LEVEL = { 'full' => 'minimal', 'minimal' => 'none' }.freeze
  # A Graph responde 400 com o código 100 quando não reconhece um parâmetro (um campo, por exemplo).
  INVALID_PARAMETER = 100
  NETWORK_ERRORS = (Crm::Ai::ResponsesClient::NETWORK_ERRORS + [HTTParty::Error, Timeout::Error]).freeze

  # code: 'ok' | 'meta_unreachable' (5xx/429/rede) | 'permission_denied' (token ou permissão) | 'meta_refused' (outro 4xx)
  #       | 'unexpected_body' (2xx sem a lista)
  Result = Data.define(:code, :count) do
    def ok?
      code == 'ok'
    end
  end

  # Uma página não veio: o sync para sem gravar.
  class Failed < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super
    end
  end

  def sync_templates
    whatsapp_channel.mark_message_templates_updated
    base = Channel::Whatsapp.where(id: whatsapp_channel.id).pick(:message_templates)
    templates = fetch_whatsapp_templates
    Whatsapp::Templates::ChannelList.replace!(whatsapp_channel, templates, base: base)
    Result.new(code: 'ok', count: templates.size)
  rescue Failed => e
    Result.new(code: e.code, count: 0)
  rescue *NETWORK_ERRORS => e
    log_sync_failure('meta_unreachable', "error=#{e.class.name}")
    Result.new(code: 'meta_unreachable', count: 0)
  end

  # Todas as páginas ou `Failed`; nunca uma lista parcial.
  def fetch_whatsapp_templates(after: nil)
    templates = []
    loop do
      data, after = fetch_templates_page(after)
      templates.concat(data)
      return templates if after.blank?
    end
  end

  private

  def fetch_templates_page(after)
    query = sync_fields_level == 'none' ? {} : { fields: LEVELS.fetch(sync_fields_level) }
    query[:after] = after if after.present?
    response = HTTParty.get("#{business_account_path}/message_templates",
                            headers: { 'Authorization' => "Bearer #{whatsapp_channel.template_access_token}" }, query: query)
    if sync_fields_level != 'none' && fields_refused?(response)
      lower_fields_level(response)
      return fetch_templates_page(after)
    end
    page_data(response)
  end

  def page_data(response)
    failed_sync(response) unless response.success?

    data = response.parsed_response.is_a?(Hash) ? response.parsed_response['data'] : nil
    unless data.is_a?(Array)
      log_sync_failure('unexpected_body', "http=#{response.code}")
      raise Failed, 'unexpected_body'
    end

    [data, response.parsed_response.dig('paging', 'cursors', 'after')]
  end

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

    graph_error(response)['code'].to_i == INVALID_PARAMETER
  end

  def graph_error(response)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    error.is_a?(Hash) ? error : {}
  end

  def failed_sync(response)
    error = graph_error(response)
    code = sync_failure_code(response.code.to_i, error['code'].to_i)
    log_sync_failure(code, "http=#{response.code} meta_code=#{error['code']} subcode=#{error['error_subcode']}")
    raise Failed, code
  end

  def sync_failure_code(http, meta_code)
    return 'meta_unreachable' if http >= 500 || http == 429
    return 'permission_denied' if http == 401 || permission_code?(meta_code)

    'meta_refused'
  end

  def permission_code?(meta_code)
    Whatsapp::Templates::GraphErrors::PERMISSION_CODES.include?(meta_code) ||
      Whatsapp::Templates::GraphErrors::PERMISSION_RANGE.cover?(meta_code)
  end

  # Só números e códigos no log: nada do texto da Meta, nada do token.
  def log_sync_failure(code, detail)
    Rails.logger.error "[whatsapp][templates] sync_failed code=#{code} account_id=#{whatsapp_channel.account_id} " \
                       "inbox_id=#{whatsapp_channel.inbox&.id} #{detail} kept_previous_list=true"
  end
end
