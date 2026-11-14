# Um PDF do lote no Conferir de "Trazer por PDFs" (E6.3, #2899): escrever o que faltou, confirmar ou recusar o contato e
# o valor achados sem certeza, deixar de fora ou trazer de volta (Carteira::Trazer::Pdfs::MudarItem). Responde o
# Conferir inteiro, já com os números novos.
class Api::V1::Accounts::Relacionamentos::Trazer::Seguros::ItensController < Api::V1::Accounts::Relacionamentos::Trazer::Seguros::BaseController
  before_action :achar_lote

  # PATCH trazer/seguros/leituras/:leitura_id/itens/:id  { campos: { tipo:, seguradora:, termina:, nome: }, confirmar: [], recusar: [], fora: }
  def update
    pedido = corpo(:fora, campos: %i[tipo seguradora termina nome], confirmar: [], recusar: [])
    ::Carteira::Trazer::Pdfs::MudarItem.new(@lote.itens.find(params[:id])).call(pedido)
    responder_conferir
  end
end
