class Api::V1::Accounts::Autonomia::Agents::ToolsController < Api::V1::Accounts::Autonomia::BaseController
  # #1430: o Testar roda dentro da requisição, e o `rack-timeout` de produção corta em 15 s. Espera no máximo isto; a
  # resposta diz quanto o agente espera no atendimento (`timeout_seconds`).
  SEGUNDOS_DO_TESTE = 12

  # #1430: ferramenta não segue o ver/editar de Agentes. Quem a cria escolhe para onde vão os dados das conversas.
  skip_before_action :check_autonomia_permission
  before_action :check_tools_permission
  before_action :fetch_agent
  before_action :refuse_quote_agent
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
    render_recusa(e.record)
  end

  def update
    @tool.assign_attributes(merged_tool_params)
    @tool.save!
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render_recusa(e.record)
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

  # A equipe da plataforma sempre. Com a flag `agente_ferramentas_delegadas` na conta: o administrador e quem tem a chave
  # `autonomia_tools_manage`, em tudo, inclusive listar (a lista mostra endereços). Sem ela, só a contagem no agente.
  def check_tools_permission
    return if Current.user.is_a?(SuperAdmin)
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('agente_ferramentas_delegadas')

    check_permission_granted!('autonomia_tools_manage')
  end

  # #1430: os campos recusados vão junto, para a tela apontar o passo sem ler o texto traduzido.
  def render_recusa(tool)
    render json: { error: tool.errors.full_messages.to_sentence, campos: tool.errors.attribute_names.map(&:to_s) },
           status: :unprocessable_entity
  end

  # A Lia (Agente de Cotação) fica com a lista fixa de ferramentas dela nesta fase (#1430): para a conta, em toda ação
  # (trocar o endereço de uma ferramenta dela levaria a conversa de cotação para outro sistema). A equipe da plataforma
  # continua cuidando dela.
  def refuse_quote_agent
    return if Current.user.is_a?(SuperAdmin)

    render_unprocessable(I18n.t('autonomia.agents.ferramenta_na_cotacao')) if @agent.agent_type == 'insurance_quote'
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
      param_schema: %i[name label type description required],
      response_mapping: {}
    )
  end

  def merged_tool_params
    attrs = tool_params.to_h
    return attrs if attrs['headers_config'].blank?

    attrs['headers_config'] = attrs['headers_config'].map { |header| segredo_guardado(header) }
    attrs
  end

  # O segredo volta mascarado para a tela; mascarado de novo no envio quer dizer "não mudou".
  def segredo_guardado(header)
    return header unless ActiveModel::Type::Boolean.new.cast(header['secret'])
    return header unless header['value'] == Autonomia::Agents::Tool.masked_header_value

    existing = @tool.headers_config.find { |item| item['key'] == header['key'] }
    existing ? header.merge('value' => existing['value']) : header
  end

  def test_params
    raw = params[:params] || {}
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end
end
