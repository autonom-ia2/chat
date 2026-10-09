class Api::V1::Accounts::Autonomia::Agents::QuoteChoicesController < Api::V1::Accounts::Autonomia::BaseController
  before_action :fetch_agent
  wrap_parameters false

  ALLOWED_KEYS = %w[name behavior horario].freeze

  def update
    return render_invalid_choice(nil) unless @agent.instrucao_mantida?

    escolhas = raw_choices
    invalid_key = invalid_choice(escolhas)
    return render_invalid_choice(invalid_key) if invalid_key
    return render_invalid_choice(nil) if escolhas.blank?

    Autonomia::Insurance::QuoteAgent::Builder.atualizar_escolhas!(@agent, choice_params)
    @agent.reload
    render_agent_show
  rescue Autonomia::Insurance::QuoteAgent::Builder::NomeInvalido => e
    render_invalid_choice(e.message.include?('corretora') ? 'broker_name' : 'name')
  rescue Autonomia::Insurance::QuoteAgent::Builder::HorarioInvalido
    render_invalid_choice('horario')
  rescue Autonomia::Insurance::QuoteAgent::Builder::ComportamentoInvalido
    render_invalid_choice('behavior')
  end

  private

  def fetch_agent
    @agent = agents_scope.find(params[:id])
  end

  def raw_choices
    params.to_unsafe_h.except('controller', 'action', 'account_id', 'agent_id', 'id', 'format')
  end

  def choice_params
    params.permit(:name, :behavior, :horario).to_h
  end

  def invalid_choice(escolhas)
    invalid_key = invalid_choice_key(escolhas)
    return invalid_key if invalid_key

    return if escolhas.blank?

    invalid_value = invalid_choice_value(escolhas)
    return invalid_value if invalid_value

    'behavior' unless valid_behavior?(escolhas['behavior'])
  end

  def invalid_choice_key(escolhas)
    escolhas.keys.find { |key| ALLOWED_KEYS.exclude?(key) }
  end

  def invalid_choice_value(escolhas)
    escolhas.keys.find { |key| !valid_choice_value?(escolhas[key]) }
  end

  def valid_choice_value?(value)
    value.is_a?(String) && value.strip.present?
  end

  def valid_behavior?(value)
    value.blank? || Autonomia::Insurance::QuoteAgent::Builder::COMPORTAMENTOS.include?(value)
  end

  def render_invalid_choice(key)
    render_unprocessable(
      I18n.t('autonomia.agents.errors.quote_choices_invalid', locale: current_account.locale),
      code: 'quote_choices_invalid', key: key
    )
  end

  def render_agent_show
    locals = agent_detail_locals(@agent)
    @list_row = locals.fetch(:list_row)
    render 'api/v1/accounts/autonomia/agents/show', locals: locals
  end
end
