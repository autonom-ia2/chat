class Api::V1::Accounts::Autonomia::AgentsController < Api::V1::Accounts::Autonomia::BaseController
  before_action :fetch_agent, only: [:show, :update, :destroy, :avatar, :publish]
  before_action :validate_public_config_contract, only: [:create, :update]
  before_action :validate_actuation_type, only: [:create, :update]
  before_action :validate_copilot_actuation, only: [:create, :update]
  before_action :validate_voice, only: [:create, :update]
  before_action :validate_manual_instruction, only: [:create, :update]
  before_action :validate_activation_instruction, only: [:create, :update]
  include ::Autonomia::Agents::RequestValidation
  include ::Autonomia::Agents::ActivationContract
  include ::Autonomia::Agents::PublishContract
  include ::Autonomia::Agents::InstructionContract

  def index
    projection = ::Autonomia::Agents::ListProjection.new(agents: agents_scope.order(created_at: :desc),
                                                         account: current_account, locale: current_account.locale)
    @list_projection = projection.call
    @copilot_availability = projection.copilot_availability
    @agents = projection.agents
  end

  def show
    render_agent_show
  end

  # O agente de instrução mantida nasce só pela aba Cotação (`Insurance::QuoteAgentController#create`),
  # que guarda as escolhas da corretora; por aqui nasceria sem elas, lendo uma coluna que ninguém mantém.
  def create
    raise ::Autonomia::Agents::Agent::InstrucaoMantida if instrucao_mantida_pelo_tipo?(params.dig(:agent, :agent_type))

    attrs = agent_params
    voice_supplied = attrs.key?(:voice)
    voice = attrs.delete(:voice)
    @agent = agents_scope.new(attrs)
    @agent.created_by = Current.user
    apply_manual_scaffold
    apply_voice_config(voice) if voice_supplied
    @agent.save!
    render_agent_show(status: :created)
  end

  # BE-03/04 — a publicação é a única porta do fluxo novo que ativa o agente. O Publisher mantém
  # pré-condições, atributos e vínculo da caixa na mesma transação; o controller só resolve recursos
  # na conta atual e traduz a recusa tipada para o contrato HTTP.
  def publish
    reject_publish_fields!

    result = ::Autonomia::Agents::Publisher.new(agent: @agent, inboxes: publish_inboxes, config: publish_config).perform
    @agent = result.agent
    render_agent_show
  rescue ::Autonomia::Agents::Errors::PublishRejected => e
    render_unprocessable(
      I18n.t("autonomia.agents.errors.#{e.code}", locale: current_account.locale, default: e.code.humanize),
      code: e.code,
      key: e.key
    )
  end

  # Onda 6 (P2) — chaves COMPUTADAS do jsonb `config` que o usuário NÃO define pela API: são geradas
  # pelo Revisor/Construtor. `assign_attributes(config:)` substituía o blob inteiro e as apagava (perda
  # silenciosa de topic_map/knowledge_* num save do PanelTune). O update agora MESCLA (preserva o resto).
  # `agente_de_cotacao` (#380): as escolhas da corretora que o Agente de Cotação lê a cada turno
  # (`QuoteAgent::Builder::ESCOLHAS_DA_CORRETORA`) — só o Builder as escreve, sempre as quatro; uma
  # escrita parcial por aqui pararia o agente com `EscolhasIncompletas`.
  PROTECTED_CONFIG_KEYS = (%w[
    topic_map knowledge_confidence knowledge_summary knowledge_refresh_token
    with_knowledge system_key builder_active_thread_id
  ] + [::Autonomia::Insurance::QuoteAgent::Builder::ESCOLHAS_DA_CORRETORA]).freeze

  def update
    instruction_before = update_locked_agent
    return if instruction_before == :rejected

    record_manual_instruction_version(instruction_before)
    render_agent_show
  rescue ::Autonomia::Insurance::QuoteAgent::Builder::NomeInvalido => e
    render_quote_choices_invalid(e.message.include?('corretora') ? 'broker_name' : 'name')
  rescue ::Autonomia::Insurance::QuoteAgent::Builder::ComportamentoInvalido
    render_quote_choices_invalid('behavior')
  rescue ::Autonomia::Insurance::QuoteAgent::Builder::HorarioInvalido
    render_quote_choices_invalid('horario')
  end

  def destroy
    ::Autonomia::Agents::SoftDelete.new(agent: @agent, actor: Current.user, request_id: request.request_id).perform
    head :no_content
  end

  def avatar
    if request.delete?
      # touch after purge so `updated_at` advances — the FE staleness guard on
      # UPSERT relies on every agent write bumping the timestamp (upload already
      # does via save!); without it a late `show` could restore the old avatar.
      if @agent.avatar.attached?
        @agent.avatar.purge
        @agent.touch # rubocop:disable Rails/SkipsModelValidations
      end
    else
      return render_unprocessable('avatar_required') if params[:avatar].blank?

      @agent.avatar.attach(params[:avatar])
      @agent.save!
    end

    ::Autonomia::Agents::MirrorIdentitySync.new(agent: @agent).perform
    render_agent_show
  end

  private

  def update_locked_agent
    instruction_before = nil
    rejected = false
    @agent.with_lock do
      rejected = reject_internal_with_channels

      unless rejected
        rejeitar_edicao_da_instrucao_mantida
        restore_guided_mode_if_requested!
        record_guided_version_before_manual_switch
        discard_generated_instruction_on_manual_switch
        instruction_before = @agent.instruction
        update_agent_attributes
        apply_manual_scaffold
        @agent.save!
      end
    end
    rejected ? :rejected : instruction_before
  end

  def fetch_agent
    @agent = agents_scope.find(params[:id])
  end

  def validate_voice
    raw = params[:agent]
    return unless raw.respond_to?(:key?) && (raw.key?(:voice) || raw.key?('voice'))

    value = raw.key?(:voice) ? raw[:voice] : raw['voice']
    return if value.is_a?(String) && ::Autonomia::Agents::Agent::VOICE_VALUES.include?(value)

    render_unprocessable(I18n.t('autonomia.agents.errors.invalid_enum', locale: current_account.locale),
                         code: 'invalid_enum', key: 'voice')
  end

  def render_agent_show(status: :ok)
    locals = agent_detail_locals(@agent)
    @list_row = locals.fetch(:list_row)
    render :show, status: status, locals: locals
  end

  def apply_voice_config(value)
    @agent.config = @agent.config.to_h.merge('voice' => value)
  end

  def update_quote_name!(value)
    ::Autonomia::Insurance::QuoteAgent::Builder.atualizar_escolhas!(@agent, 'name' => value)
    @agent.reload
  end

  def render_quote_choices_invalid(key)
    render_unprocessable(
      I18n.t('autonomia.agents.errors.quote_choices_invalid', locale: current_account.locale),
      code: 'quote_choices_invalid', key: key
    )
  end

  # Campos visíveis permitidos. `instruction` só é aceita em modo manual (texto do próprio
  # usuário, visível). `scaffold` JAMAIS vem do params. Em guiado, instruction também é ignorada.
  # Chaves de SISTEMA que o usuário NUNCA pode setar via API: forjar `system_key` tornaria um agente
  # invisível/imutável (agents_scope o esconde) e permitiria se passar pelo Guia da Plataforma.
  RESERVED_CONFIG_KEYS = %w[system_key hidden_from_hub].freeze

  def agent_params
    permitted = %i[name agent_type mode tone greeting fallback_message handoff_rule human_card voice
                   enabled status actuation]
    permitted << :instruction if manual_mode?
    attrs = params.require(:agent).permit(*permitted, starter_questions: [], config: {})
    attrs[:config] = sanitized_config(attrs[:config]) if attrs[:config].present?
    permit_audience_config(attrs)
    attrs
  end

  # #284 (Entrega 2a) — o público-alvo é uma árvore recursiva (grupos com arrays de hashes) que o
  # `permit(config: {})` não enxerga por forma; passa cru (mesmo desenho do Captain) e a validade fica
  # a cargo de Autonomia::Agents::AudienceValidator no model. `null` limpa (= todo mundo).
  # As chaves ESCALARES da porta (`response_window`, `audience_unknown_contact`) não precisam disto:
  # `permit(config: {})` já as aceita e merge_config! as mescla; a inclusão é validada no model.
  def permit_audience_config(attrs)
    config = params[:agent][:config]
    return unless config.respond_to?(:key?) && config.key?(:audience)

    audience = config[:audience]
    attrs[:config] = (attrs[:config] || {}).merge('audience' => (audience.respond_to?(:permit!) ? audience.permit!.to_h : audience))
  end

  # Strip every system-managed config key the user must never set: the reserved keys AND any
  # `guide_*` key (e.g. guide_kb_version) — otherwise a forged row could fake the Guia's freshness
  # marker and skip the self-healing canonicalize/purge.
  def sanitized_config(config)
    parameter_hash(config).reject { |key, _| RESERVED_CONFIG_KEYS.include?(key.to_s) || key.to_s.start_with?('guide_') }
  end

  # Onda 6 (P2) — MESCLA o config recebido (já sanitizado de system/guide_) sobre o salvo, removendo
  # ainda as chaves COMPUTADAS (topic_map/knowledge_*/with_knowledge) que o usuário não define pela API.
  # Antes o update SUBSTITUÍA o jsonb inteiro e apagava o que o Revisor/Construtor gerou.
  def merge_config!(incoming)
    safe = parameter_hash(incoming).except(*PROTECTED_CONFIG_KEYS)
    @agent.config = @agent.config.to_h.merge(safe)
  end

  def parameter_hash(value)
    return {} if value.blank?
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

    value.to_h
  end

  def manual_mode?
    requested = params.dig(:agent, :mode).to_s
    return requested == 'manual' if requested.present?

    @agent&.manual? || false
  end

  # V2.1 — não deixa um agente ficar INTERNO enquanto tem canais conectados (deixaria um vínculo
  # órfão; um interno não atende cliente). A guarda vem antes de qualquer restauração, snapshot ou
  # assign para que um PATCH 422 não deixe efeito lateral no histórico. A validação anterior já
  # fechou o enum na borda; external/both e qualquer update sem canais seguem livres.
  def reject_internal_with_channels
    return false unless requested_internal_actuation? && @agent.agent_inboxes.exists?

    render_unprocessable(
      I18n.t(
        'autonomia.agents.errors.internal_with_channels',
        locale: current_account.locale,
        default: 'Disconnect all channels before making this agent internal.'
      ),
      code: 'internal_with_channels'
    )
    true
  end
end
