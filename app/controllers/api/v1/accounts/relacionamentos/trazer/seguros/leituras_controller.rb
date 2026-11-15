# "Trazer por PDFs" (E6.3, #2899): enviar os PDFs (cada um é lido em segundo plano; a tela pergunta de novo até sair de
# "lendo"), o Conferir do lote, trazer, o andamento, os lotes já enviados e o desfazer com a prévia.
# Enviar pede a leitura liberada para a conta (422 `leitura_desligada`, decisão D4); o resumo da carteira
# (`leituraDePdf`) já diz isso à tela, que nem mostra o caminho. Ver e desfazer um lote enviado antes, não.
#
# A busca no Agger (E7, #2900) é uma leitura também, e usa as mesmas rotas: o Conferir (com o andamento de cada
# seguradora), trazer, o andamento, o desfazer com a prévia e `de_novo` (buscar de novo). O histórico dela é o mesmo
# índice com `origem=conector`. Começar a busca é o BuscasController.
class Api::V1::Accounts::Relacionamentos::Trazer::Seguros::LeiturasController < Api::V1::Accounts::Relacionamentos::Trazer::Seguros::BaseController
  ORIGEM_DO_AGGER = 'conector'.freeze

  before_action :sem_parametros, except: [:index, :create]
  before_action :achar_lote, except: [:index, :create]

  # GET trazer/seguros/leituras (os lotes de PDFs) · GET trazer/seguros/leituras?origem=conector (as buscas no Agger)
  def index
    return render json: ::Carteira::Conector::Historico.new(buscas).call if historico_do_agger?

    render json: ::Carteira::Trazer::Pdfs::Historico.new(lotes_de_pdf).call
  end

  # GET trazer/seguros/leituras/:id
  def show
    responder_conferir
  end

  # POST trazer/seguros/leituras (multipart `arquivos[]`)
  def create
    raise CustomExceptions::CarteiraRecusa, ::Carteira::Leitor::Resultado::DESLIGADA unless ::Carteira::Leitor::Liberado.para?(Current.account)

    lote = ::Carteira::Trazer::Pdfs::Receber.new(Current.account, user: Current.user).call(corpo(arquivos: [])['arquivos'])
    render json: { id: lote.id }, status: :created
  end

  # POST trazer/seguros/leituras/:id/trazer — o segundo clique responde o mesmo.
  def trazer
    agger? ? ::Carteira::Conector::Trazer.new(@lote).call : ::Carteira::Trazer::Pdfs::Trazer.new(@lote).call
    render json: ::Carteira::Trazer::Pdfs::Andamento.new(@lote.reload).call
  end

  # POST trazer/seguros/leituras/:id/de_novo — buscar de novo no Agger (a busca parada continua; a que terminou pede o
  # período de novo). Só a busca no Agger.
  def de_novo
    raise ActiveRecord::RecordNotFound unless agger?

    ::Carteira::Conector::Sincronizar.de_novo(@lote)
    responder_conferir
  end

  # GET trazer/seguros/leituras/:id/andamento
  def andamento
    response.headers['Cache-Control'] = 'private, no-store'
    render json: ::Carteira::Trazer::Pdfs::Andamento.new(@lote).call
  end

  # GET trazer/seguros/leituras/:id/previa_do_desfazer
  def previa_do_desfazer
    return render json: { error: 'nao_pode_desfazer' }, status: :unprocessable_entity unless ::Carteira::Trazer::Pdfs::Desfazer.pode?(@lote)

    render json: ::Carteira::Trazer::Pdfs::Desfazer.new(@lote).previa
  end

  # POST trazer/seguros/leituras/:id/desfazer
  def desfazer
    ::Carteira::Trazer::Pdfs::Desfazer.new(@lote, quem: Current.user).pedir
    render json: ::Carteira::Trazer::Pdfs::Andamento.new(@lote.reload).call
  end

  private

  # Além dos lotes de PDFs, as buscas no Agger.
  def lotes
    ::Carteira::Leitura.do_lote.where(account_id: Current.account.id)
  end

  def lotes_de_pdf
    ::Carteira::Leitura.do_trazer.where(account_id: Current.account.id)
  end

  def buscas
    ::Carteira::Leitura.do_conector.where(account_id: Current.account.id)
  end

  def agger?
    @lote.origem == ORIGEM_DO_AGGER
  end

  # O índice só conhece `origem=conector`; outro parâmetro é pedido que ele não conhece.
  def historico_do_agger?
    recebidos = request.query_parameters
    recusar("parâmetro desconhecido: #{recebidos.keys.first}") unless (recebidos.keys - ['origem']).empty?
    return false unless recebidos.key?('origem')

    recusar('origem em formato inválido') unless recebidos['origem'] == ORIGEM_DO_AGGER
    true
  end
end
