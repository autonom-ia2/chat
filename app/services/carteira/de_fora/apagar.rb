# Apagar um seguro de outra corretora (E6.5, #2899): o "Desfazer" logo depois de guardar e o "Apagar este seguro" da
# gaveta. Só o seguro `de_fora` se apaga; o da carteira da corretora responde `nao_e_de_fora` e não muda (ele se cancela,
# não some). A história sai junto (cascata) e o PDF vai para a limpeza depois de a gravação fechar. O card de renovação
# que ele já tenha continua no quadro: quem decide sobre o card é o CRM. Nada daqui vai para log além do id.
class Carteira::DeFora::Apagar
  def initialize(apolice)
    @apolice = apolice
  end

  def call
    raise CustomExceptions::CarteiraRecusa, 'nao_e_de_fora' unless @apolice.de_fora

    @apolice.with_lock(requires_new: true) { @apolice.destroy! }
    Rails.logger.info("[carteira][de_fora] apagado apolice=#{@apolice.id}")
    @apolice
  end
end
