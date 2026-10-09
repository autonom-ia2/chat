class Api::V1::Accounts::Autonomia::Agents::ToolsController < Api::V1::Accounts::Autonomia::BaseController
  before_action :ensure_super_admin
  before_action :fetch_agent
  before_action :fetch_tool, only: %i[show update destroy test]

  def index
    @tools = tools_scope.order(created_at: :desc)
  end

  def show; end

  def create
    @tool = tools_scope.new(merged_tool_params)
    @tool.account = Current.account
    @tool.save!
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable(e.record.errors.full_messages.to_sentence)
  end

  def update
    @tool.assign_attributes(merged_tool_params)
    @tool.save!
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render_unprocessable(e.record.errors.full_messages.to_sentence)
  end

  def destroy
    @tool.destroy!
    head :no_content
  end

  def test
    result = Autonomia::Agents::Tools::HttpExecutor.new(tool: @tool, params: test_params).call
    render json: { status: 'ok', body: result.to_s.truncate(2_000) }
  rescue Autonomia::Agents::Tools::HttpExecutor::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_super_admin
    raise Pundit::NotAuthorizedError unless Current.user.is_a?(SuperAdmin)
  end

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  def fetch_tool
    @tool = tools_scope.find(params[:id])
  end

  def tools_scope
    @agent.tools.where(account: Current.account)
  end

  def tool_params
    params.require(:tool).permit(
      :name, :slug, :description, :enabled, :http_method, :endpoint_url, :request_body_template,
      headers_config: %i[key value secret],
      param_schema: %i[name type description required],
      response_mapping: {}
    )
  end

  def merged_tool_params
    attrs = tool_params.to_h
    return attrs if attrs['headers_config'].blank?

    attrs.merge('headers_config' => normalized_headers(attrs['headers_config']))
  end

  def normalized_headers(headers)
    existing_headers = Array(@tool&.headers_config)
    headers.map { |header| normalized_header(header, existing_headers) }
  end

  def normalized_header(header, existing_headers)
    existing = existing_headers.find { |item| item['key'] == header['key'] }
    return preserve_existing_header(header, existing) if existing && masked_or_missing_value?(header)
    return header.merge('value' => '') if masked_header?(header)

    header
  end

  def preserve_existing_header(header, existing)
    existing_secret = ActiveModel::Type::Boolean.new.cast(existing['secret'])
    incoming_secret = ActiveModel::Type::Boolean.new.cast(header['secret'])
    header.merge('value' => existing['value'], 'secret' => existing_secret || incoming_secret)
  end

  def masked_or_missing_value?(header)
    !header.key?('value') || masked_header?(header)
  end

  def masked_header?(header)
    header['value'] == Autonomia::Agents::Tool.masked_header_value
  end

  def test_params
    raw = params[:params] || {}
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end
end
