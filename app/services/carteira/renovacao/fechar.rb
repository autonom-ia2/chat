# "Renovou", "Não renovou" e "Desfazer" da gaveta do seguro (E5, #2898). A gaveta não escreve o desfecho no seguro: ela
# fecha ou reabre o CARD de renovação, como o quadro faz (Crm::Cards::Closer), e quem escreve no seguro é o ouvinte do
# card (Carteira::RenovacaoListener, no mesmo pedido). Um caminho só, venha do quadro ou da gaveta.
#
# - renovou: fecha o card como ganho. Pedir de novo no seguro já renovado não muda nada.
# - nao_renovou: fecha o card como perdido e guarda o motivo, quando veio. No seguro que já está como "não renovou" (o
#   card foi fechado no quadro, sem motivo), só guarda o motivo.
# - desfazer: reabre o card; o seguro volta a "em renovação".
#
# Recusas (CustomExceptions::CarteiraRecusa): `sem_renovacao` (o seguro não tem card de renovação, ou ele foi tirado do
# quadro), `ja_tem_desfecho` (pedir "renovou" no que não renovou, ou o contrário: desfaça antes), `sem_desfecho` (não
# há o que desfazer), `motivo_desconhecido`, `falta_texto` (motivo "outro" sem dizer qual) e `texto_longo`.
#
# Quem confere se a pessoa pode fechar o card é quem chama (Crm::CardPolicy#close?).
class Carteira::Renovacao::Fechar
  GANHO = 'won'.freeze
  PERDIDO = 'lost'.freeze
  REABRIR = 'reopen'.freeze

  def initialize(apolice, user:)
    @apolice = apolice
    @user = user
  end

  def renovou
    recusar('ja_tem_desfecho') if @apolice.nao_renovou_em
    return @apolice if @apolice.renovado_em

    fechar(GANHO)
  end

  def nao_renovou(motivo: nil, texto: nil)
    motivo, escrito = ler_motivo(motivo, texto)
    recusar('ja_tem_desfecho') if @apolice.renovado_em
    fechar(PERDIDO) unless @apolice.nao_renovou_em
    motivo ? Carteira::Renovacao::Desfecho.new(@apolice).dizer_motivo(motivo, escrito) : @apolice
  end

  def desfazer
    recusar('sem_desfecho') unless @apolice.renovado_em || @apolice.nao_renovou_em

    fechar(REABRIR)
  end

  private

  def fechar(resultado)
    card = card_no_quadro
    Crm::Cards::Closer.new(card: card, actor: @user, result: resultado).perform
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)
    @apolice.reload
  end

  def card_no_quadro
    card = @apolice.crm_card
    recusar('sem_renovacao') if card.nil? || card.archived? || @apolice.renovacao_card_removido_em
    card
  end

  # [motivo, o que a pessoa escreveu]. Sem motivo, os dois nulos: o card fecha como no quadro, e o motivo fica para depois.
  def ler_motivo(motivo, texto)
    return [nil, nil] if motivo.blank?

    recusar('motivo_desconhecido') unless Carteira::Apolice::MOTIVOS_DE_NAO_RENOVAR.include?(motivo)
    return [motivo, nil] unless motivo == Carteira::Apolice::MOTIVO_ESCRITO

    escrito = texto.to_s.strip
    recusar('falta_texto') if escrito.empty?
    recusar('texto_longo') if escrito.length > Carteira::Apolice::MOTIVO_ESCRITO_MAXIMO
    [motivo, escrito]
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
