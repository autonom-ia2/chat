# Confere, no disparo de uma campanha com produtos do catálogo (#1418), que cada produto escolhido segue no catálogo da
# WABA da caixa e à venda. Tudo certo: devolve o catálogo, que entra em cada envio (`products.catalog_id`, nunca vindo
# da tela). Senão a campanha para inteira, com o motivo e o nome do produto (decisão do Rodrigo, 14/10/2026):
#   template_catalog_missing     — a WABA não tem mais catálogo, ou o token da caixa não consegue lê-lo (permissão,
#                                  ou o catálogo sumiu: 100/33 da Meta);
#   template_product_unavailable — produto esgotado, fora do catálogo ou não aprovado.
# A Meta fora do ar sobe para o `CampaignPauses::WhatsappDispatchGate`, que para pelo sistema (nunca envia às cegas).
class Whatsapp::Templates::DispatchProducts
  Result = Data.define(:catalog_id, :reason_code, :details) do
    def ok?
      reason_code.nil?
    end
  end

  CATALOG_GONE = %w[permission_denied not_found_or_no_access].freeze

  def initialize(inbox:, template:, processed:)
    @inbox = inbox
    @template = template
    @processed = processed
  end

  def call
    return Result.new(catalog_id: nil, reason_code: nil, details: {}) unless Whatsapp::Templates::ProductParams.kind(@template)

    catalog = client.catalog(fresh: true)
    return stop('template_catalog_missing', {}) unless catalog

    found = client.find(ids)
    # #1717: cada envio da campanha grava nome, preço e foto do que o disparo acabou de ler, sem consultar a Meta de novo.
    Whatsapp::Templates::Enviado::Produtos.lembrar(@inbox, found.values)
    missing = unavailable(found)
    return stop('template_product_unavailable', product_ids: missing, product_names: missing.map { |id| name_of(id) }) if missing.any?

    Result.new(catalog_id: catalog.id, reason_code: nil, details: {})
  rescue Whatsapp::Templates::MetaClient::MetaError => e
    raise unless CATALOG_GONE.include?(e.code)

    stop('template_catalog_missing', permission: e.code == 'permission_denied')
  end

  private

  def client
    @client ||= Whatsapp::Templates::CatalogClient.new(inbox: @inbox)
  end

  def ids
    Whatsapp::Templates::ProductParams.retailer_ids(@processed)
  end

  def unavailable(found)
    ids.reject { |id| found[id]&.available }
  end

  # O nome guardado na campanha (o que a pessoa viu ao escolher); sem ele, o código do produto.
  def name_of(id)
    names = @processed.dig('products', 'names')
    (names.is_a?(Hash) && names[id].presence) || id
  end

  def stop(reason_code, details)
    Result.new(catalog_id: nil, reason_code: reason_code, details: details)
  end
end
