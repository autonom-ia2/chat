class Api::V1::Accounts::Autonomia::Agents::ToolsController < Api::V1::Accounts::Autonomia::BaseController
  # #1430: o Testar roda dentro da requisição, e o `rack-timeout` de produção corta em 15 s. Espera no máximo isto; a
  # resposta diz quanto o agente espera no atendimento (`timeout_seconds`).
  SEGUNDOS_DO_TESTE = 12

  before_action :ensure_super_admin
  before_action :fetch_agent
  before_action :fetch_tool, only: %i[show update destroy test]

  def index
    @tools = tools_scope.order(created_at: :desc)
  end

  def show; end

  def create
    @tool = tools_scope.new(tool_params)
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

  # #1425: o teste mostra EXATAMENTE o que o agente lê no atendimento — o mesmo corte (`Bound#cabendo`)
  # e, na falha, o mesmo texto de recusa (`Bound#texto_da_recusa_http`, sem registrar: teste não é
  # recusa de atendimento). `error` continua com a mensagem do executor, que a tela traduz.
  def test
    bound = Autonomia::Agents::Tools::Bound.new(agent: @agent, record: @tool)
    segundos = [@tool.timeout_seconds, SEGUNDOS_DO_TESTE].min
    result = Autonomia::Agents::Tools::HttpExecutor.new(tool: @tool, params: test_params, segundos: segundos).call.to_s
    render json: { status: 'ok', body: bound.cabendo(result), segundos_do_teste: segundos,
                   cortada: result.length > Autonomia::Agents::Tools::Bound::MAX_OUTPUT_CHARS }
  rescue Autonomia::Agents::Tools::HttpExecutor::Error => e
    render json: { error: e.message, agente_recebe: bound.texto_da_recusa_http(e), segundos_do_teste: segundos },
           status: :unprocessable_entity
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
      :name, :slug, :description, :enabled, :http_method, :endpoint_url, :request_body_template, :timeout_seconds,
      headers_config: %i[key value secret],
      param_schema: %i[name type description required],
      response_mapping: {}
    )
  end

  def merged_tool_params
    attrs = tool_params.to_h
    return attrs unless attrs['headers_config'].present?

    attrs['headers_config'] = attrs['headers_config'].map do |header|
      next header unless header['secret'] == true || header['secret'] == 'true'
      next header unless header['value'] == Autonomia::Agents::Tool.masked_header_value

      existing = @tool.headers_config.find { |item| item['key'] == header['key'] }
      existing ? header.merge('value' => existing['value']) : header
    end
    attrs
  end

  def test_params
    raw = params[:params] || {}
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end
end
