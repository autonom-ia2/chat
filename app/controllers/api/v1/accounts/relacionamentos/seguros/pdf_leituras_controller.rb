# Anexar o PDF de um seguro e ver o que mudou (E6.2, #2899): enviar o arquivo para ler (202, com o id da leitura) e
# perguntar pela leitura até ela sair de "lendo". Guardar, com os campos escolhidos, é o `POST seguros/:id/pdf` de
# sempre, com `leituraId` e `usar` (seguros/pdf_controller.rb). As duas pedem poder editar a pessoa: ver o que o PDF diz
# só serve a quem vai guardá-lo.
#
# Conta sem a leitura liberada: as duas respondem 422 `leitura_desligada` (decisão D4), sem ler nada. O resumo da
# carteira (`leituraDePdf`) já diz isso à tela, que nem chama.
class Api::V1::Accounts::Relacionamentos::Seguros::PdfLeiturasController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :sem_parametros, only: :show
  before_action :achar_seguro
  before_action :poder_editar
  before_action :exigir_leitura

  # GET seguros/:id/pdf/leitura/:leitura_id
  def show
    response.headers['Cache-Control'] = 'private, no-store'
    render json: ::Carteira::Pdf::Andamento.new(@seguro, params[:leitura_id]).call
  end

  # POST seguros/:id/pdf/leitura (multipart `arquivo`)
  def create
    leitura = ::Carteira::Pdf::Ler.new(@seguro, user: Current.user).call(corpo(:arquivo)['arquivo'])
    render json: { leituraId: leitura.id }, status: :accepted
  end

  private

  def exigir_leitura
    recusar_com(::Carteira::Leitor::Resultado::DESLIGADA) unless ::Carteira::Leitor::Liberado.para?(Current.account)
  end

  def recusar_com(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
