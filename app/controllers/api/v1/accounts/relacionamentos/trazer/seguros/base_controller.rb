# Base de "Trazer por PDFs" (E6.3, #2899). Como toda rota da carteira, pede a chave de Relacionamentos e a carteira de
# seguros da conta (404 sem elas: Relacionamentos::CarteiraController). A permissão é a de importar contatos de hoje
# (ContactPolicy#import?: administrador ou função com contact_manage), como "Trazer minha lista": o lote cria pessoas.
# Só entram os lotes da conta (Carteira::Leitura.do_trazer); o do anexar e o de outra conta respondem 404.
class Api::V1::Accounts::Relacionamentos::Trazer::Seguros::BaseController < Api::V1::Accounts::Relacionamentos::CarteiraController
  private

  def conferir_permissao
    authorize(Contact, :import?)
  end

  def lotes
    ::Carteira::Leitura.do_trazer.where(account_id: Current.account.id)
  end

  def achar_lote
    @lote = lotes.find(params[:leitura_id] || params[:id])
  end

  def responder_conferir
    response.headers['Cache-Control'] = 'private, no-store'
    render json: ::Carteira::Trazer::Pdfs::Conferir.new(@lote).call
  end
end
