# O material só de um post ou anúncio (#2487, PR 3b do #2436): o arquivo que o dono anexa para o agente ler ao responder
# os comentários daquele cuidado, e só eles. É do cuidado (Source#care_id), não do agente: não entra no painel de
# materiais do agente, nas conferências, no placar nem no turno normal (Retriever). Guarda `autonomia_agent_id` = o agente
# da porta da rede no momento do anexo (a leitura e a revisão rodam como as do agente); a resposta lê pelo cuidado, de
# qualquer porta.
#
# GET    agentes_do_post/:id/materiais              → { materiais: [{ id, reference, source_type, status, agente,
#        review: { status, reviewed_at } }] }, só do banco (a mesma forma da linha de material do agente).
# POST   agentes_do_post/:id/materiais  file        → o material novo (201), lido em segundo plano (IngestJob).
# DELETE agentes_do_post/:id/materiais/:material_id → 204: sai com os trechos e o arquivo.
#
# As guardas são as do cartão (AgentesDoPostController): ver para a lista; a chave de mudar do alvo para anexar e tirar.
# No anúncio, também ver a caixa de cada rede (403 `not_inbox_member`), como o detalhe. Anexar lê a Meta (no anúncio, a
# caixa de cada rede só sai de lá) para achar o agente da porta; sem agente que leia, 422 `no_agent`. A Lia
# (`insurance_quote`) e o agente de outra conta nunca leem o material: não escrevem comentário (Porta).
class Api::V1::Accounts::AgentesDoPostMateriaisController < Api::V1::Accounts::AgentesDoPostController
  TIPOS = (Autonomia::Agents::Source::SOURCE_TYPES - ['link', Autonomia::Agents::Source::FOTO]).freeze

  # As guardas do cartão em todas as ações (a lista do pai, `index`, não tem cuidado); ler a Meta só ao anexar.
  skip_before_action :load_care, :ensure_manage, :load_alvo
  before_action :load_care
  before_action :ensure_manage, only: [:create, :destroy]
  before_action :guardas_do_anuncio, only: [:index, :destroy]

  def index
    render json: { materiais: @care.sources.includes(:agent).order(:id).map { |fonte| material(fonte) } }
  end

  def create
    arquivo = params[:file]
    raise Recusa, 'invalid_file' unless arquivo.is_a?(ActionDispatch::Http::UploadedFile) && TIPOS.include?(tipo(arquivo))

    load_alvo
    fonte = nova_fonte(arquivo)
    Autonomia::Agents::Knowledge::IngestJob.perform_later(fonte.id)
    render json: material(fonte), status: :created
  end

  def destroy
    @care.sources.find(params[:material_id]).destroy!
    head :no_content
  end

  private

  def nova_fonte(arquivo)
    fonte = @care.sources.new(account: Current.account, agent: agente_da_porta, kind: 'knowledge', source_type: tipo(arquivo),
                              reference: arquivo.original_filename)
    fonte.file.attach(arquivo)
    fonte.byte_size = arquivo.size
    fonte.mime = arquivo.content_type
    raise Recusa, 'invalid_file' unless fonte.save

    fonte
  end

  # A caixa de cada rede do anúncio só sai da Meta. O detalhe desta pessoa guardado pelo cartão prova que as guardas do
  # anúncio passaram (o pai só guarda depois delas, numa chave por pessoa e por cuidado); sem ele, as guardas do pai. A
  # lista se relê a cada 5 s enquanto lê: assim não volta à Meta a cada vez.
  def guardas_do_anuncio
    return if @care.target_kind == 'post' || Rails.cache.exist?(chave_do_detalhe)

    load_alvo
  end

  # O agente da primeira porta que pode ler (no anúncio nas duas redes, a ordem das redes do criativo).
  def agente_da_porta
    agente = @fonte.redes.each_value.lazy.filter_map do |rede|
      agente_que_le(Crm::MetaAds::ComentariosIa::Porta.new(care: @care, inbox: Inbox.find_by(id: rede[:inbox_id], account_id: Current.account.id)))
    end.first
    agente || raise(Recusa, 'no_agent')
  end

  # O agente da porta, se ele pode ler o material: da conta do cuidado e não a Lia. Parado ou em piloto, lê (volta a
  # escrever quando a porta voltar).
  def agente_que_le(porta)
    agente = porta.agente
    agente if agente && agente.account_id == @care.account_id && agente.agent_type != Crm::MetaAds::ComentariosIa::Porta::LIA
  end

  def tipo(arquivo)
    File.extname(arquivo.original_filename.to_s).delete_prefix('.').downcase
  end

  def material(fonte)
    { id: fonte.id, reference: fonte.reference, source_type: fonte.source_type, status: fonte.status, agente: fonte.agent.name,
      review: { status: fonte.review_status, reviewed_at: fonte.reviewed_at } }
  end
end
