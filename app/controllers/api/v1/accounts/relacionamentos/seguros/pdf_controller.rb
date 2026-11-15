# O PDF da apólice na gaveta do seguro (E4, #2897): o link para abrir, guardar um arquivo e tirar. Ver o PDF pede o
# mesmo que ver o seguro, e o link só é emitido depois dessa conferência; ele é assinado, vale um minuto e não pode ficar
# em cache. Guardar e tirar pedem poder editar a pessoa e devolvem o seguro como ficou.
# Guardar aceita, no lugar do arquivo, o PDF já lido pelo anexar (E6.2, #2899): `leituraId` e `usar` (os campos que a
# pessoa escolheu trocar pelo que o PDF diz; vazio guarda só o PDF). Ver seguros/pdf_leituras_controller.rb.
class Api::V1::Accounts::Relacionamentos::Seguros::PdfController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :sem_parametros, only: :show
  before_action :achar_seguro
  before_action :poder_ver, only: :show
  before_action :poder_editar, except: :show

  def show
    ActiveStorage::Current.url_options = { host: request.base_url }
    response.headers['Cache-Control'] = 'private, no-store'
    render json: { url: pdf.link }
  end

  def create
    return responder_seguro(pdf.guardar(corpo(:arquivo)['arquivo'])) unless params.key?(:leituraId)

    pedido = corpo(:leituraId, usar: [])
    responder_seguro(pdf.guardar_lido(pedido['leituraId'], pedido['usar']))
  end

  def destroy
    corpo
    responder_seguro(pdf.tirar)
  end

  private

  def pdf
    ::Carteira::Pdf.new(@seguro, user: Current.user)
  end
end
