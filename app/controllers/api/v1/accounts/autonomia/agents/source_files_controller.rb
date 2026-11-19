class Api::V1::Accounts::Autonomia::Agents::SourceFilesController < Api::V1::Accounts::Autonomia::BaseController
  def show
    agent = agents_scope.find(params[:agent_id])
    source = agent.sources.da_agente.find(params[:source_id])
    blob = source.file.blob
    return head :not_found unless blob && blob.service.exist?(blob.key)

    ActiveStorage::Current.url_options = { host: request.base_url }
    response.headers['Cache-Control'] = 'private, no-store'
    render json: { url: ::Autonomia::Agents::SourceFile.new(blob).url }
  end
end
