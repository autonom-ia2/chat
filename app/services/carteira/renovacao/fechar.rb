# "Renovou", "Não renovou" e "Desfazer" da gaveta do seguro (E5, #2898). A gaveta fecha ou reabre o CARD de renovação,
# como o quadro faz (Crm::Cards::Closer), e na mesma transação acerta o seguro pelo card (Carteira::Renovacao::Desfecho,
# o mesmo que escreve quando o card é fechado no quadro): o card e o seguro entram juntos ou não entram. O ouvinte do
# card, que roda depois do commit, encontra tudo no lugar.
#
# - renovou: fecha o card como ganho. Pedir de novo no seguro já renovado não muda nada.
# - nao_renovou: fecha o card como perdido e guarda o motivo, quando veio. No seguro que já está como "não renovou" (o
#   card foi fechado no quadro, sem motivo), só guarda o motivo.
# - desfazer: reabre o card; o seguro volta a "em renovação". O seguro cancelado não reabre: volte a ativo antes.
# - por_cancelamento: o seguro foi marcado como cancelado com a renovação aberta. O card fecha como perdido, com o
#   motivo "cancelou": card de seguro cancelado não fica aberto para sempre.
#
# A gaveta e o quadro ao mesmo tempo: o seguro é travado primeiro e o card depois (a mesma ordem do cancelamento, da
# apólice nova e da rotina que cria o card), e os dois são relidos sob a trava. Antes de decidir, o seguro é acertado
# pelo card como ele está agora: se alguém fechou o card no quadro enquanto a gaveta estava aberta, a gaveta decide com
# o desfecho de lá (e recusa "Renovou" no que acabou de ser perdido), em vez de fechar por cima com o que leu antes. É
# também o que conserta o seguro quando o aviso do quadro falhou.
#
# Recusas (CustomExceptions::CarteiraRecusa): `sem_renovacao` (o seguro não tem card de renovação, ou ele foi tirado do
# quadro), `ja_tem_desfecho` (pedir "renovou" no que não renovou, ou o contrário: desfaça antes), `sem_desfecho` (não
# há o que desfazer), `ja_cancelado` (desfazer no seguro cancelado), `motivo_desconhecido`, `falta_texto` (motivo
# "outro" sem dizer qual) e `texto_longo`.
#
# Quem confere se a pessoa pode fechar o card é quem chama (Crm::CardPolicy#close?).
class Carteira::Renovacao::Fechar
  GANHO = 'won'.freeze
  PERDIDO = 'lost'.freeze
  REABRIR = 'reopen'.freeze

  # O card fecha (ou reabre) e o seguro é acertado por ele, na transação de quem chama, que já travou os dois. O quadro
  # é avisado depois do commit.
  def self.pelo_card(apolice, card, resultado, user:)
    Crm::Cards::Closer.new(card: card, actor: user, result: resultado).perform
    ActiveRecord.after_all_transactions_commit { Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED) }
    Carteira::Renovacao::Desfecho.new(apolice, user: user).acertar
  end

  def initialize(apolice, user:)
    @apolice = apolice
    @user = user
  end

  def renovou
    sob_trava do
      recusar('ja_tem_desfecho') if @apolice.nao_renovou_em
      fechar(GANHO) unless @apolice.renovado_em
    end
  end

  def nao_renovou(motivo: nil, texto: nil)
    motivo, escrito = ler_motivo(motivo, texto)
    sob_trava do
      recusar('ja_tem_desfecho') if @apolice.renovado_em
      fechar(PERDIDO) unless @apolice.nao_renovou_em
      Carteira::Renovacao::Desfecho.new(@apolice).dizer_motivo(motivo, escrito) if motivo
    end
  end

  def desfazer
    sob_trava do
      recusar('sem_desfecho') unless @apolice.renovado_em || @apolice.nao_renovou_em
      recusar('ja_cancelado') if @apolice.cancelado_em

      fechar(REABRIR)
    end
  end

  # Roda dentro da transação de quem cancela (Carteira::Cancelamento), que já travou o seguro: o cancelamento, o card
  # fechado, o desfecho e o motivo entram juntos ou não entram. Sem renovação aberta, nada acontece.
  def por_cancelamento
    card = @apolice.crm_card
    return if card.nil? || @apolice.renovacao_card_removido_em

    card.with_lock do
      next unless card.open?

      self.class.pelo_card(@apolice, card, PERDIDO, user: @user)
      Carteira::Renovacao::Desfecho.new(@apolice).dizer_motivo(Carteira::Apolice::MOTIVO_CANCELOU, nil)
    end
  end

  private

  # O seguro travado e relido; com card, o card travado e relido, e o seguro acertado por ele (sem autor: se havia o
  # que acertar, quem fechou foi o quadro). Devolve o seguro como ficou.
  def sob_trava
    @apolice.with_lock do
      @card = @apolice.crm_card
      next yield unless @card

      @card.with_lock do
        Carteira::Renovacao::Desfecho.new(@apolice).acertar
        yield
      end
    end
    @apolice
  end

  def fechar(resultado)
    recusar('sem_renovacao') if @card.nil? || @card.archived? || @apolice.renovacao_card_removido_em

    self.class.pelo_card(@apolice, @card, resultado, user: @user)
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
