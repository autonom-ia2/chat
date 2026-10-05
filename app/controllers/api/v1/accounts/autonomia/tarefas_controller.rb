# As tarefas longas do Guia (#936): ver o andamento e mandar começar, seguir, pausar, retomar,
# cancelar e desfazer tudo.
#
# A tarefa é de quem a pediu: de outra pessoa responde 404, igual a uma que não existe. Começar e
# seguir soltam lotes em centenas de registros, então estão em `Acoes::SEM_DESFAZER`: o Guia não
# chama direto, quem clica é a pessoa. Os lotes e o desfazer rodam em job (teto de 15 s do servidor).
class Api::V1::Accounts::Autonomia::TarefasController < Api::V1::Accounts::BaseController
  TAREFA = ::Autonomia::Guide::Tarefa
  LIMITE = 20

  before_action :ensure_guide_enabled
  before_action :carregar_tarefa, except: [:index]

  def index
    render json: { tarefas: TAREFA.de(Current.account, Current.user).order(created_at: :desc).limit(LIMITE).map(&:para_tela) }
  end

  def show
    render json: @tarefa.para_tela
  end

  def comecar
    mudar('comecar', receita_digest: TAREFA.digest_de(@tarefa.receita), batimento_em: Time.current) { andar }
  end

  def seguir
    mudar('seguir', batimento_em: Time.current) { andar }
  end

  def pausar
    mudar('pausar', motivo_pausa: 'pessoa') { sair_do_semaforo }
  end

  def retomar
    mudar('retomar', motivo_pausa: nil, mensagens_conferidas_ate: Time.current, batimento_em: Time.current) { andar }
  end

  def cancelar
    mudar('cancelar') { sair_do_semaforo }
  end

  def desfazer
    mudar('desfazer') { ::Autonomia::Guide::DesfazerTarefaJob.perform_later(@tarefa.id) }
  end

  private

  def mudar(comando, **extra)
    return render(json: { error: I18n.t("autonomia.guide.tarefa.nao_da.#{comando}") }, status: :unprocessable_entity) unless pode?(comando)
    return render(json: { error: I18n.t('autonomia.guide.tarefa.nao_da.estado') }, status: :conflict) unless @tarefa.mudar!(comando, **extra)

    yield
    render json: @tarefa.para_tela
  end

  # Desfazer só existe com algum lote ainda dentro dos 5 dias.
  def pode?(comando)
    comando != 'desfazer' || @tarefa.desfazivel?
  end

  def andar
    ::Autonomia::Guide::TarefaJob.perform_later(@tarefa.id)
  end

  def sair_do_semaforo
    ::Autonomia::Guide::Tarefas::Semaforo.sair(@tarefa)
  end

  def carregar_tarefa
    @tarefa = TAREFA.de(Current.account, Current.user).find_by(id: params[:id])
    head :not_found if @tarefa.nil?
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end
end
