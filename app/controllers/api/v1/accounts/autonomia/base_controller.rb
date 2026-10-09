class Api::V1::Accounts::Autonomia::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :check_autonomia_permission

  # Onda 6 (P2) — valor de enum inválido (agent_type/actuation/status fora do conjunto) levanta
  # ArgumentError no assign → virava 500. Devolve 422 (erro do cliente). SÓ o erro de enum é tratado
  # aqui; qualquer outro ArgumentError re-sobe (continua 500 — não mascara bug real).
  rescue_from ArgumentError, with: :handle_argument_error
  # #380 — a instrução do Agente de Cotação é mantida pela Autonom.ia. O model levanta em cada escritor
  # da coluna (rollback, refresh, Construtor) e os controllers na porta; a resposta é uma só.
  rescue_from ::Autonomia::Agents::Agent::InstrucaoMantida, with: :render_instrucao_mantida
  # #380 (rodada 4) — a chave `agente_de_cotacao` do config presente e incompleta (só escrita fora do
  # Builder produz isso) para a montagem do prompt com `EscolhasIncompletas`. O Responder registra o
  # evento; aqui, o Testar e o Copilot (os outros chamadores do mesmo `Answerer`) respondiam 500 sem o
  # nome do campo. A recusa é fechada nos dois lugares; agora também é explícita: 422 com código estável
  # e o campo que falta — a mensagem do erro é só o nome do campo (`Builder.conferir_escolhas!`), nunca um valor.
  rescue_from ::Autonomia::Insurance::QuoteAgent::Builder::EscolhasIncompletas, with: :render_escolhas_incompletas

  rescue_from ::Autonomia::Agents::Errors::ManualMode, with: :render_manual_mode
  rescue_from ::Autonomia::Agents::Errors::NoGuidedVersion, with: :render_no_guided_version
  rescue_from ::Autonomia::Agents::Errors::UnrestorableVersion, with: :render_unrestorable_version

  private

  def render_manual_mode
    render_unprocessable(I18n.t('autonomia.agents.errors.manual_mode', locale: current_account.locale), code: 'manual_mode')
  end

  def render_no_guided_version
    render_unprocessable(I18n.t('autonomia.agents.errors.no_guided_version', locale: current_account.locale),
                         code: 'no_guided_version')
  end

  def render_unrestorable_version
    render_unprocessable(I18n.t('autonomia.agents.errors.unrestorable_version', locale: current_account.locale),
                         code: 'unrestorable_version')
  end

  def render_instrucao_mantida
    render_unprocessable(I18n.t('autonomia.agents.instrucao_mantida', locale: current_account.locale), code: 'instrucao_mantida')
  end

  # `current_account`, não `Current.account`: o `ensure` de `handle_with_exception` (around_action do
  # core) já fez `Current.reset` quando o `rescue_from` roda; o ivar memoizado continua lá.
  def render_escolhas_incompletas(error)
    Rails.logger.warn("[autonomia][api] escolhas_incompletas account=#{current_account.id} campo=#{error.message}")
    render json: { error: I18n.t('autonomia.agents.escolhas_incompletas', campo: error.message),
                   code: 'escolhas_incompletas', campo: error.message },
           status: :unprocessable_entity
  end

  def handle_argument_error(error)
    raise error unless error.message.include?('is not a valid')

    render_unprocessable(
      I18n.t('autonomia.agents.errors.invalid_enum', locale: current_account.locale),
      code: 'invalid_enum'
    )
  end

  # Toda a área de Agentes Autonom.ia some (404) quando a flag está desligada — porta única,
  # idêntica ao gate do CRM/EmailCampaigns.
  def ensure_feature_enabled
    head :not_found unless ::Autonomia::Agents::Config.enabled?(Current.account)
  end

  # Admin ou função personalizada: leitura exige autonomia_view; escrita (criar, treinar, publicar) exige
  # autonomia_manage. O construtor é IP e roda jobs de IA, então agente comum sem função segue sem acesso.
  def check_autonomia_permission
    check_module_permission!('autonomia')
  end

  # Escopos sempre presos à conta corrente (isolamento de conta) — nunca consulta global.
  # Agentes de SISTEMA (config['system_key'], ex.: o Guia da Plataforma) ficam FORA da API de
  # agentes: não são listados, lidos, editados nem deletados pelo usuário (instruction = IP nosso).
  def agents_scope
    ::Autonomia::Agents::Agent.kept.where(account: Current.account)
                              .where("config->>'system_key' IS NULL")
  end

  def build_threads_scope
    ::Autonomia::Agents::BuildThread.where(account: Current.account)
                                    .left_joins(:agent)
                                    .where(autonomia_agents: { deleted_at: nil })
                                    .where("autonomia_agents.config->>'system_key' IS NULL")
  end

  def render_unprocessable(message, code: nil, key: nil)
    payload = { error: message }
    payload[:code] = code if code
    payload[:key] = key if key
    render json: payload, status: :unprocessable_entity
  end

  # O detalhe do agente é usado por mais de uma action (show, create/update e rollback). Manter a
  # projeção nesta fronteira compartilhada evita que uma resposta renderizada por outra action perca
  # state/teste ou passe uma linha stale para o serializer.
  def agent_detail_locals(agent)
    projection = ::Autonomia::Agents::ListProjection.new(
      agents: agents_scope.where(id: agent.id), account: current_account, locale: current_account.locale
    )
    {
      list_row: projection.call.fetch(agent.id),
      writes_external: agent_detail_writes_external?(agent)
    }
  end

  def agent_detail_writes_external?(agent)
    return false unless Current.account_user&.permission_granted?('autonomia_manage')

    agent.tools.enabled.where(account_id: current_account.id).where.not(http_method: 'GET').exists?
  end
end
