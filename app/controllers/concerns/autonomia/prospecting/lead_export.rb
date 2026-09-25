# Exportar leads de uma busca ou de uma lista (#682, frente A). Os dois controllers passam os leads que a tela mostra, já
# restritos à conta; aqui ficam a validação do pedido e o arquivo.
#
# lead_ids é opcional: a tela manda os selecionados, ou os que sobraram do filtro, na ordem em que aparecem. Id fora dos
# leads recebidos (outra conta, outra busca) não entra.
module Autonomia::Prospecting::LeadExport
  extend ActiveSupport::Concern

  private

  def send_leads_export(leads, scoring:, filename:)
    # Da query string: params[:format] é sempre 'json', o padrão que as rotas da API fixam.
    format = request.query_parameters['format'].to_s
    return render_export_error('invalid_format') unless Autonomia::Prospecting::Export.formats.include?(format)

    ids = export_lead_ids
    return render_export_error('invalid_lead_ids') if ids == :invalid

    rows = Autonomia::Prospecting::Export::Table.new(account: Current.account, scoring: scoring).rows(pick_leads(leads, ids))
    send_data Autonomia::Prospecting::Export.generate(format, rows),
              type: Autonomia::Prospecting::Export.content_type(format),
              filename: "prospeccao-#{filename}-#{Time.zone.today.iso8601}.#{format}", disposition: 'attachment'
  end

  def pick_leads(leads, ids)
    return leads if ids.nil?

    by_id = leads.index_by(&:id)
    ids.filter_map { |id| by_id[id] }
  end

  # nil sem o parâmetro; :invalid se não for lista de inteiros.
  def export_lead_ids
    return if params[:lead_ids].nil?
    return :invalid unless params[:lead_ids].is_a?(Array)

    ids = params[:lead_ids].map { |id| Integer(id.to_s, 10, exception: false) }
    ids.all? ? ids.uniq : :invalid
  end

  def render_export_error(key)
    render json: { error: I18n.t("autonomia.prospecting.export.errors.#{key}") }, status: :unprocessable_entity
  end
end
