# Apagar um seguro de outra corretora (E6.5, #2899): o "Desfazer" logo depois de guardar e o "Apagar este seguro" da
# gaveta. Só o seguro `de_fora` se apaga; o da carteira da corretora responde `nao_e_de_fora` e não muda (ele se cancela,
# não some). A história sai junto (cascata) e o PDF vai para a limpeza depois de a gravação fechar. O card de renovação
# que ele já tenha é arquivado na mesma operação (Crm::Cards::Archiver, o caminho da pessoa e do lote), para as
# mensagens da Automação não saírem sobre um seguro que não existe mais; o card some do quadro, mas não é apagado. Nada
# daqui vai para log além do id.
class Carteira::DeFora::Apagar
  def initialize(apolice, user: nil)
    @apolice = apolice
    @user = user
  end

  def call
    raise CustomExceptions::CarteiraRecusa, 'nao_e_de_fora' unless @apolice.de_fora

    @apolice.with_lock(requires_new: true) do
      arquivar_o_card
      @apolice.destroy!
    end
    Rails.logger.info("[carteira][de_fora] apagado apolice=#{@apolice.id}")
    @apolice
  end

  private

  def arquivar_o_card
    card = @apolice.crm_card
    Crm::Cards::Archiver.new(card: card, actor: @user).perform if card
  end
end
