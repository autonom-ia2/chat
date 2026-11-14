# "Trazer por PDFs" (E6.3, #2899): enviar os PDFs (cada um é lido em segundo plano; a tela pergunta de novo até sair de
# "lendo"), o Conferir do lote, trazer, o andamento, os lotes já enviados e o desfazer com a prévia.
# Enviar pede a leitura liberada para a conta (422 `leitura_desligada`, decisão D4); o resumo da carteira
# (`leituraDePdf`) já diz isso à tela, que nem mostra o caminho. Ver e desfazer um lote enviado antes, não.
class Api::V1::Accounts::Relacionamentos::Trazer::Seguros::LeiturasController < Api::V1::Accounts::Relacionamentos::Trazer::Seguros::BaseController
  before_action :sem_parametros, except: :create
  before_action :achar_lote, except: [:index, :create]

  # GET trazer/seguros/leituras
  def index
    render json: ::Carteira::Trazer::Pdfs::Historico.new(lotes).call
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
    ::Carteira::Trazer::Pdfs::Trazer.new(@lote).call
    render json: ::Carteira::Trazer::Pdfs::Andamento.new(@lote.reload).call
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
end
