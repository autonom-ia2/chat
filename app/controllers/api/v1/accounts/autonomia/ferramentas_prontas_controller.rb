# A VITRINE DE FERRAMENTAS PRONTAS (#2858, F2): o catálogo liberado para a conta, as prontas já incluídas em cada agente,
# o "Experimente", o "Incluir", liga/desliga, "Tirar" e as buscas sem resultado. Na F3, o cartão "pode ganhar" do agente
# que já existe (`sugestoes`, `dispensar`), só com a flag do Construtor. No #2881, a frase "Use quando" de uma pronta
# já incluída pode ser alterada (`update`).
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
    @fontes = Autonomia::FerramentasProntas.da_vitrine(Current.account)
    @incluidas = prontas_scope.order(:id)
    # F7: nos cards Premium, quantas grátis restam à conta e os preços depois delas.
    @premium = Autonomia::FerramentasProntas::Premium.para_tela(Current.account, @fontes)
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

  # `confirmou_preco` (F7): o clique no botão com o preço, quando as grátis do card Premium acabaram. Só `true` (ou
  # "true") paga; qualquer outro valor ("sim", lista, objeto) é "não confirmou".
  VALORES_DE_CONFIRMACAO = [true, 'true'].freeze

  # O card Premium responde 202 ("consultando", com o id do pedido): a consulta paga roda em segundo plano.
  def experimentar
    resultado = Autonomia::FerramentasProntas::Experimente.new(
      account: Current.account, fonte: params.require(:fonte).to_s, valor: params[:valor],
      confirmou_preco: VALORES_DE_CONFIRMACAO.include?(params[:confirmou_preco])
    ).call
    consultando = resultado['situacao'] == Autonomia::FerramentasProntas::Experimente::Pedido::CONSULTANDO
    render json: resultado, status: consultando ? :accepted : :ok
  end

  # F7 (revisor, 12/11): o estado de um pedido do Experimente Premium ("consultando" ou o resultado). Preso à conta: o
  # pedido de outra conta, ou o que já venceu, é 404. A mesma porta do `experimentar`.
  def acompanhar
    pedido = Autonomia::FerramentasProntas::Experimente::Pedido.para_tela(params[:pedido], account: Current.account)
    return head :not_found if pedido.nil?

    render json: pedido
  end

  # Só verdadeiro ou falso (`true`/`false`, também como texto, que é como o Guia manda): qualquer outro valor (lista,
  # objeto, "abc") é recusado e nunca vira "ligada".
  VALORES_DE_LIGADA = [true, false, 'true', 'false'].freeze

  # Muda o liga/desliga, a frase "Use quando" (#2881), ou os dois. `ligada` só pode faltar quando a frase vem: sem
  # nenhum dos dois, o pedido é recusado como antes. A frase passa pela limpeza do "Incluir" (`Incluir.frase`). Frase
  # vazia ("") tira a frase: o agente passa a receber só a descrição da ferramenta. `null` conta como "não veio", para
  # um pedido sem a frase nunca apagar a que existe.
  def update
    return render json: { motivo: 'ligada_invalida' }, status: :unprocessable_entity unless ligada_valida?
    return render json: { motivo: 'usar_quando_invalido' }, status: :unprocessable_entity unless usar_quando_valido?

    @pronta.update!(mudancas_da_pronta)
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

  def muda_a_frase?
    !params[:usar_quando].nil?
  end

  def ligada_valida?
    return true if muda_a_frase? && !params.key?(:ligada)

    VALORES_DE_LIGADA.include?(params[:ligada])
  end

  # A frase é texto: lista, objeto, número e verdadeiro/falso são recusados e nunca viram frase.
  def usar_quando_valido?
    !muda_a_frase? || params[:usar_quando].is_a?(String)
  end

  # O `to_s` da frase também diz ao Guia que o campo é texto (os formatos das ações são lidos do código).
  def mudancas_da_pronta
    ligada = params.key?(:ligada) ? { enabled: ActiveModel::Type::Boolean.new.cast(params[:ligada]) } : {}
    frase = muda_a_frase? ? { description: Autonomia::FerramentasProntas::Incluir.frase(params[:usar_quando].to_s) } : {}
    ligada.merge(frase)
  end

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
