# O que a IA sabe de um pedido e do cliente dele (#1601, W8): os fatos vivos com a procedência (de onde veio, quando,
# alegado ou confirmado), as sugestões e os divergentes; e a correção da pessoa (corrigir, não vale mais, aceitar a
# sugestão, destravar). Quem vê o card vê; quem pode editar o card corrige. Sem a flag, 404. A tela usa só a linha de
# origem embaixo de cada campo em "Campos do card" (decisão do Rodrigo, 17/10): quem corrigiu (nome) e a mensagem de
# prova (conversa e mensagem, para o "ver mensagem").
class Api::V1::Accounts::Crm::MemoriaFatosController < Api::V1::Accounts::Crm::BaseController
  GRUPOS = %w[contato pedido conversa decisao].freeze

  before_action :ensure_memoria
  before_action :carregar_card
  before_action :carregar_fato, only: %i[nao_vale_mais aceitar destravar]

  def index
    authorize @card, :show?
    fatos = escopo_do_card.vivos.order(registrado_em: :desc).limit(200).to_a
    carregar_procedencia(fatos)
    render json: { payload: fatos.map { |fato| payload(fato) } }
  end

  def create
    authorize @card, :update?
    grupo = params.require(:grupo).to_s
    return render_unprocessable('crm.memoria.grupo_invalido') unless GRUPOS.include?(grupo)
    return render_unprocessable('crm.memoria.chave_fora_do_catalogo') unless chave_do_catalogo?(grupo, params.require(:chave))

    chave = grupo == 'decisao' ? ::Crm::Memoria::Catalogo::DECISAO : params.require(:chave)
    fato = ::Crm::Memoria::Correcao.corrigir!(card: @card, grupo: grupo, chave: chave, valor: params.require(:valor),
                                              item_ref: params[:item_ref], user: Current.user)
    render json: { payload: fato && payload(fato) }
  end

  def nao_vale_mais
    authorize @card, :update?
    ::Crm::Memoria::Correcao.nao_vale_mais!(@fato)
    render json: { payload: payload(@fato.reload) }
  end

  def aceitar
    authorize @card, :update?
    return render_unprocessable('crm.memoria.nao_e_sugestao') unless @fato.situacao == 'sugestao' || @fato.situacao == 'divergente'

    novo = ::Crm::Memoria::Correcao.aceitar!(@fato, user: Current.user)
    render json: { payload: novo && payload(novo) }
  end

  def destravar
    authorize @card, :update?
    ::Crm::Memoria::Correcao.destravar!(@fato)
    render json: { payload: payload(@fato.reload) }
  end

  private

  def ensure_memoria
    render json: { error: 'crm.memoria.disabled' }, status: :not_found unless ::Crm::Memoria.ligada?(Current.account)
  end

  def carregar_card
    @card = policy_scope(::Crm::Card).find(params[:card_id])
    render json: { error: 'crm.memoria.card_sem_contato' }, status: :unprocessable_entity if @card.contact_id.nil?
  end

  # Só fatos deste card ou do cliente dele (escopo contato), da conta.
  def carregar_fato
    @fato = escopo_do_card.find(params[:id])
  end

  def escopo_do_card
    fatos = ::Crm::MemoriaFato.where(account_id: Current.account.id, contact_id: @card.contact_id)
    conversas = [@card.conversation_id, *@card.card_conversations.pluck(:conversation_id)].compact
    fatos.where(escopo: 'card', card_id: @card.id).or(fatos.where(escopo: 'contato'))
         .or(fatos.where(escopo: 'conversa', conversation_id: conversas))
  end

  # A chave precisa estar no catálogo da conta (a IA e a pessoa não criam chave). Decisão usa a chave do sistema.
  def chave_do_catalogo?(grupo, chave)
    modelo = ::Crm::Memoria::Escritor::GRUPOS.fetch(grupo).first
    chave = ::Crm::Memoria::Catalogo::DECISAO if grupo == 'decisao'
    ::Crm::Memoria::Catalogo.da_conta(Current.account).key?([modelo, chave.to_s])
  end

  def payload(fato)
    carregar_procedencia([fato]) if @nomes.nil?
    prova = fato.prova_message_ids.last
    fato.slice(:id, :escopo, :tipo, :chave, :item_ref, :valor, :valor_json, :fonte, :status, :situacao, :divergente_de_id,
               :prova_message_ids, :prova_trecho, :valido_desde, :vence_em, :registrado_em, :expirado_em, :versao, :travado,
               :travado_por_user_id)
        .merge(vencido: fato.vencido?, corrigido_por_nome: @nomes[fato.travado_por_user_id], prova_message_id: prova,
               prova_conversation_display_id: @conversas[prova])
  end

  # Numa consulta cada: o nome de quem corrigiu (o do cadastro) e a conversa (display_id) da mensagem de prova, da conta.
  def carregar_procedencia(fatos)
    @nomes = User.where(id: fatos.filter_map(&:travado_por_user_id)).pluck(:id, :name).to_h
    provas = fatos.filter_map { |fato| fato.prova_message_ids.last }
    @conversas = Message.where(id: provas, account_id: Current.account.id).joins(:conversation)
                        .pluck('messages.id', 'conversations.display_id').to_h
  end
end
