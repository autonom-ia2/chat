# Decisor (#858): a pergunta que a automação faz sobre a conversa antes de seguir.
#
# Mesmas chaves das automações (automation_view / automation_manage), pela policy própria. Não herda a
# porta dos Agentes Autonom.ia: o Decisor é parte das automações, não da área de agentes.
class Api::V1::Accounts::Autonomia::DecisoresController < Api::V1::Accounts::BaseController
  wrap_parameters false

  before_action :autorizar
  before_action :carregar_decisor, except: [:index, :create]

  def index
    decisores = escopo.order(:nome).to_a
    esperando = Autonomia::DecisorDecisao.esperando_pessoa.where(account_id: Current.account.id).group(:decisor_id).count
    render json: { decisores: decisores.map { |decisor| resumo(decisor, esperando[decisor.id].to_i) } }
  end

  def show
    render json: completo(@decisor)
  end

  def create
    decisor = escopo.create!(decisor_params)
    render json: completo(decisor), status: :created
  end

  def update
    @decisor.update!(decisor_params)
    render json: completo(@decisor)
  end

  def destroy
    @decisor.destroy!
    head :ok
  end

  # Não grava nada: responde em conversas reais e mostra os campos que extrairia.
  def teste
    render json: Autonomia::Decisores::Teste.new(decisor: @decisor, conversations: conversas_do_teste).perform
  end

  # O "Confirmar" do teste: a resposta certa para aquela conversa vira exemplo.
  def exemplos
    resposta = params.require(:resposta).to_s
    return render_could_not_create_error("resposta must be one of: #{@decisor.chaves.join(', ')}") unless @decisor.resposta?(resposta)

    estado = estado_da_conversa(conversas_visiveis.find(params.require(:conversation_id)))
    return render_could_not_create_error('conversation has no incoming message') if estado.blank?

    @decisor.guardar_exemplo!(texto: estado.texto_do_exemplo, resposta: resposta, origem: 'pessoa')
    render json: completo(@decisor)
  end

  def decisoes
    lista = @decisor.decisoes.includes(conversation: :contact).order(created_at: :desc).limit(50)
    lista = lista.where(status: params[:status].to_s) if params[:status].present?
    render json: { decisoes: lista.map { |decisao| decisao_json(decisao) } }
  end

  private

  def autorizar
    authorize(Autonomia::Decisor, "#{action_name}?")
  end

  def escopo
    Autonomia::Decisor.where(account_id: Current.account.id)
  end

  def carregar_decisor
    @decisor = escopo.find(params[:id])
  end

  def decisor_params
    params.permit(:nome, :pergunta, :instrucoes, :certeza_minima, respostas: [:chave, :descricao],
                                                                  exemplos: [:texto, :resposta, :origem], campos: [:chave, :descricao, :destino])
  end

  # Conversas que a pessoa enxerga: o teste mostra trechos, e quem não vê a caixa não lê a conversa.
  def conversas_visiveis
    Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account).perform
  end

  def conversas_do_teste
    quantidade = params.fetch(:quantidade, Autonomia::Decisores::Teste::QUANTIDADE_PADRAO).to_i
                       .clamp(1, Autonomia::Decisores::Teste::MAX_QUANTIDADE)
    conversas = conversas_visiveis.includes(:contact, :inbox)
    conversas = conversas.where(id: Array(params[:conversation_ids])) if params[:conversation_ids].present?
    conversas = conversas.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    conversas.reorder(last_activity_at: :desc).limit(quantidade).to_a
  end

  def estado_da_conversa(conversation)
    message = conversation.messages.incoming.reorder(id: :desc).first
    message && Autonomia::Decisores::Estado.new(conversation: conversation, message: message)
  end

  def resumo(decisor, esperando)
    { id: decisor.id, nome: decisor.nome, pergunta: decisor.pergunta, respostas: decisor.respostas,
      certeza_minima: decisor.certeza_minima.to_f, contadores: decisor.contadores, esperando_pessoa: esperando }
  end

  def completo(decisor)
    esperando = decisor.decisoes.esperando_pessoa.count
    resumo(decisor, esperando).merge(instrucoes: decisor.instrucoes, exemplos: decisor.exemplos, campos: decisor.campos)
  end

  def decisao_json(decisao)
    { id: decisao.id, status: decisao.status, resposta: decisao.resposta, certeza: decisao.certeza&.to_f,
      motivo: decisao.motivo, campos_extraidos: decisao.campos_extraidos, automation_rule_id: decisao.automation_rule_id,
      conversation_id: decisao.conversation_id, display_id: decisao.conversation.display_id,
      contato: decisao.conversation.contact&.name, criada_em: decisao.created_at, vence_em: vence_em(decisao) }
  end

  def vence_em(decisao)
    decisao.created_at + Autonomia::DecisorDecisao::PRAZO_PESSOA if decisao.status == 'esperando_pessoa'
  end
end
