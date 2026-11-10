# A VITRINE DE FERRAMENTAS PRONTAS (#2858, F2): o catálogo liberado para a conta, as prontas já incluídas em cada agente,
# o "Experimente", o "Incluir", liga/desliga, "Tirar" e as buscas sem resultado. Na F3, o cartão "pode ganhar" do agente
# que já existe (`sugestoes`, `dispensar`), só com a flag do Construtor.
#
# Quem pode, em tudo: a equipe da plataforma, o administrador e quem tem a chave "Ferramentas dos agentes"
# (`autonomia_tools_manage`). É a condição da Funções: a porta do "Incluir" confere a pessoa antes e passa a pessoa
# real ao serviço. Sem a flag da vitrine (ou a das prontas), 404. A Lia fica de fora (o serviço recusa) e uma conta
# nunca vê nem mexe nas prontas de outra (tudo preso a `Current.account`). Não há nada técnico na resposta: nem link,
# nem host, nem a chave interna da conta.
class Api::V1::Accounts::Autonomia::FerramentasProntasController < Api::V1::Accounts::Autonomia::BaseController
  skip_before_action :check_autonomia_permission
  before_action :ensure_vitrine
  before_action :check_tools_permission
  before_action :fetch_pronta, only: %i[update destroy]
  before_action :ensure_construtor, :fetch_agente, only: %i[sugestoes dispensar]

  def index
    @fontes = Autonomia::FerramentasProntas::Catalogo.todas.select do |fonte|
      Autonomia::FerramentasProntas.disponivel?(Current.account, fonte)
    end
    @incluidas = prontas_scope.order(:id)
  end

  def incluir
    agente = agents_scope.find(params.require(:agent_id))
    resultado = Autonomia::FerramentasProntas::Incluir.new(
      account: Current.account, agent: agente, fonte: params.require(:fonte).to_s,
      usar_quando: params[:usar_quando], user: Current.user
    ).call
    @pronta = resultado.ferramenta
    render :pronta, status: :created
  rescue Autonomia::FerramentasProntas::Incluir::Recusado => e
    render json: { motivo: e.motivo }, status: :unprocessable_entity
  end

  def experimentar
    render json: Autonomia::FerramentasProntas::Experimente.new(
      account: Current.account, fonte: params.require(:fonte).to_s, valor: params[:valor]
    ).call
  end

  # Só verdadeiro ou falso (`true`/`false`, também como texto, que é como o Guia manda): qualquer outro valor (lista,
  # objeto, "abc") é recusado e nunca vira "ligada".
  VALORES_DE_LIGADA = [true, false, 'true', 'false'].freeze

  def update
    return render json: { motivo: 'ligada_invalida' }, status: :unprocessable_entity unless VALORES_DE_LIGADA.include?(params[:ligada])

    @pronta.update!(enabled: ActiveModel::Type::Boolean.new.cast(params[:ligada]))
    render :pronta
  end

  def destroy
    @pronta.destroy!
    head :no_content
  end

  # #2858 F3: as prontas que combinam com o agente e ele ainda não tem. A sugestão é calculada em segundo plano: a
  # resposta traz a que já existe (ou nenhuma) e, se ela está velha ou falta, pede a nova para a próxima abertura.
  def sugestoes
    Autonomia::FerramentasProntas::SugestaoJob.enfileirar(@agente) if Autonomia::FerramentasProntas::SugestaoParaAgente.ligada?(@agente)
    render json: { ferramentas: Autonomia::FerramentasProntas::SugestaoParaAgente.para_tela(@agente) }
  end

  # "Agora não": aquela sugestão não volta para aquele agente.
  def dispensar
    fonte = Autonomia::FerramentasProntas::Catalogo.buscar(params.require(:fonte).to_s)
    return render json: { motivo: 'fonte_invalida' }, status: :unprocessable_entity if fonte.nil?
    return head :not_found unless Autonomia::FerramentasProntas::SugestaoParaAgente.ligada?(@agente)

    Autonomia::FerramentasProntas::SugestaoParaAgente.dispensar!(@agente, fonte.chave)
    head :no_content
  end

  def buscas_sem_resultado
    Autonomia::FerramentasProntas::BuscasSemResultado.registrar(Current.account, params[:termo])
    head :no_content
  end

  private

  def ensure_vitrine
    # Com o motivo: a tela separa "a vitrine saiu da conta" de "este agente ou esta ferramenta não existe mais".
    render json: { motivo: 'desligada' }, status: :not_found unless Autonomia::FerramentasProntas.vitrine?(Current.account)
  end

  def ensure_construtor
    render json: { motivo: 'desligada' }, status: :not_found unless Autonomia::FerramentasProntas.construtor?(Current.account)
  end

  def fetch_agente
    @agente = agents_scope.find(params.require(:agent_id))
  end

  def check_tools_permission
    return if Current.user.is_a?(SuperAdmin)

    check_permission_granted!('autonomia_tools_manage')
  end

  # As prontas dos agentes da conta, fora a Lia e os agentes de sistema (`agents_scope`).
  def prontas_scope
    agentes = agents_scope.where.not(agent_type: Autonomia::FerramentasProntas::AGENTE_DE_COTACAO)
    Autonomia::Agents::Tool.where(account: Current.account, autonomia_agent_id: agentes.select(:id)).where.not(fonte_pronta: nil)
  end

  def fetch_pronta
    @pronta = prontas_scope.find(params[:id])
  end
end
