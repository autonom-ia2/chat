# Configuração da memória das IAs da conta (#1601): só o administrador. Os robôs de fora que usam login de pessoa e as
# caixas que ficam fora da memória. Sem a flag `memoria_ia`, 404. A tela vem depois do mockup.
class Api::V1::Accounts::Crm::MemoriaConfigController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_memoria
  before_action :ensure_administrator

  def show
    render json: payload(::Crm::Memoria.config(Current.account))
  end

  CHAVES = %i[usuarios_robo_ids caixas_excluidas].freeze

  def update
    return render_unprocessable('crm.memoria.ids_must_be_lists') if CHAVES.any? { |chave| params.key?(chave) && !params[chave].is_a?(Array) }

    config = gravar_config
    return render_unprocessable(config.errors.full_messages.to_sentence) if config.errors.any?

    render json: payload(config)
  end

  private

  def ensure_memoria
    render json: { error: 'crm.memoria.disabled' }, status: :not_found unless ::Crm::Memoria.ligada?(Current.account)
  end

  def ensure_administrator
    render json: { error: 'crm.memoria.forbidden' }, status: :forbidden unless administrator?
  end

  # A primeira gravação de dois administradores ao mesmo tempo: a segunda relê a linha da primeira e grava por cima.
  def gravar_config(tentativa: 1)
    config = ::Crm::MemoriaConfig.find_or_initialize_by(account_id: Current.account.id)
    config.assign_attributes(usuarios_robo_ids: ids(:usuarios_robo_ids, config.usuarios_robo_ids),
                             caixas_excluidas: ids(:caixas_excluidas, config.caixas_excluidas))
    config.save
    config
  rescue ActiveRecord::RecordNotUnique
    raise if tentativa > 1

    gravar_config(tentativa: tentativa + 1)
  end

  def ids(chave, atual)
    permitidos = params.permit(usuarios_robo_ids: [], caixas_excluidas: [])
    return atual unless permitidos.key?(chave)

    Array(permitidos[chave]).compact_blank.map(&:to_i).uniq
  end

  def payload(config)
    { usuarios_robo_ids: config.usuarios_robo_ids, caixas_excluidas: config.caixas_excluidas }
  end
end
