# Ritmo de envio da conta (#3063, item 2): o limite de mensagens por cliente e o horário de envio, que valem para as
# campanhas e para as mensagens que a Automação livre inicia (Autonomia::RitmoDeEnvio). Quem define é o usuário da
# plataforma (decisão do Rodrigo, 19/11).
#
#   GET   …/ritmo_de_envio  { payload: { limite, horario, fuso } }           quem vê campanhas
#   PATCH …/ritmo_de_envio  { limite: {mensagens, dias} | null,
#                             horario: {inicio, fim, dias_da_semana} | null } quem cuida de campanhas
#
# Grava só a chave dela em accounts.settings, num UPDATE só (jsonb_set): não passa por cima de outra configuração que
# alguém mude ao mesmo tempo.
class Api::V1::Accounts::RitmoDeEnvioController < Api::V1::Accounts::BaseController
  def show
    authorize(Campaign, :show?)
    render json: { payload: payload }
  end

  def update
    authorize(Campaign, :update?)
    valor = ::Autonomia::RitmoDeEnvio::Config.normalizar(ritmo_params)
    gravar(valor)
    render json: { payload: payload }
  rescue ::Autonomia::RitmoDeEnvio::Config::Invalida => e
    render json: { error: 'ritmo_de_envio.invalido', parameter: e.message }, status: :unprocessable_entity
  end

  private

  # A chave que não veio no corpo fica como está: mandar só o limite não apaga o horário, e o contrário.
  def ritmo_params
    enviado = params.permit(limite: %i[mensagens dias], horario: [:inicio, :fim, { dias_da_semana: [] }]).to_h
    guardado = ::Autonomia::RitmoDeEnvio::Config.da(Current.account).to_h
    guardado.keys.index_with { |chave| params.key?(chave) ? enviado[chave] : guardado[chave] }
  end

  def gravar(valor)
    Account.where(id: Current.account.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["settings = jsonb_set(COALESCE(settings, '{}'::jsonb), ARRAY[?], ?::jsonb), updated_at = ?",
       ::Autonomia::RitmoDeEnvio::Config::CHAVE, valor.to_json, Time.current]
    )
    Current.account.reload
  end

  def payload
    config = ::Autonomia::RitmoDeEnvio::Config.da(Current.account)
    config.to_h.merge('fuso' => Current.account.reporting_timezone.presence || ::Crm::Timezone::Resolver.default_timezone)
  end
end
