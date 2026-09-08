# A porta do Agente de Cotação (PRD §18-19).
#
# Herda o gate do módulo: feature ligada + conta marcada + administrador. Um agente que fala com
# cliente e carrega credencial de portal não se cria por acidente.
class Api::V1::Accounts::Autonomia::Insurance::QuoteAgentController <
  Api::V1::Accounts::Autonomia::Insurance::BaseController
  # GET — existe? A tela decide entre oferecer "criar" e oferecer "abrir".
  def show
    @agent = agente_existente
    render :show
  end

  # POST — cria pronto: principal, especialista de auto e as instruções com nome, horário e
  # comportamento já substituídos.
  def create
    @agent = builder.call
    render :show, status: :created
  rescue ::Autonomia::Insurance::QuoteAgent::Builder::JaExiste
    # Não é erro do usuário nem falha: alguém clicou duas vezes, ou já havia um. A tela mostra o que
    # existe em vez de uma mensagem de erro sobre algo que ela mesma pediu.
    @agent = agente_existente
    render :show, status: :conflict
  rescue ::Autonomia::Insurance::QuoteAgent::Builder::NomeInvalido,
         ::Autonomia::Insurance::QuoteAgent::Builder::ComportamentoInvalido => e
    render json: { error: e.class.name.demodulize.underscore, detail: e.message },
           status: :unprocessable_entity
  end

  private

  def agente_existente
    ::Autonomia::Agents::Agent.find_by(account: Current.account, agent_type: 'insurance_quote')
  end

  def builder
    ::Autonomia::Insurance::QuoteAgent::Builder.new(
      account: Current.account,
      nome_agente: params.dig(:quote_agent, :name),
      nome_corretora: params.dig(:quote_agent, :broker_name),
      horario: params.dig(:quote_agent, :business_hours),
      comportamento: params.dig(:quote_agent, :behavior)
    )
  end
end
