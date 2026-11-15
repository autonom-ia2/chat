# "Buscar novos seguros todo dia" (E7, #2900): o interruptor da conta, guardado em `carteira_renovacao_configs.busca_diaria`
# (uma linha por conta, que nasce aqui quando a conta ainda não tem). Desligado por padrão; liga sozinho quando a conta
# traz a primeira busca do Agger (Carteira::Conector::Gravar), porque a promessa é "a carteira se mantém sozinha", e a
# pessoa desliga quando quiser.
#
# `contas`: as contas com o interruptor ligado e uma conexão do Agger. A rotina (Carteira::Conector::BuscaDiariaJob)
# confere em cada uma se a carteira e a conexão estão prontas.
class Carteira::Conector::BuscaDiaria
  def self.contas
    ligadas = Carteira::RenovacaoConfig.where(busca_diaria: true).select(:account_id)
    com_agger = Autonomia::Insurance::Connection.where(provider: Carteira::Conector::PROVIDER).select(:account_id)
    Account.where(id: ligadas).where(id: com_agger)
  end

  def initialize(account)
    @account = account
  end

  def ligada?
    Carteira::RenovacaoConfig.find_by(account_id: @account.id)&.busca_diaria || false
  end

  def mudar!(ligado)
    config = Carteira::RenovacaoConfig.find_by(account_id: @account.id) || Carteira::RenovacaoConfig.create_or_find_by!(account_id: @account.id)
    config.update!(busca_diaria: ligado)
    ligado
  end

  # Liga na primeira vez que a conta traz uma busca do Agger: só se nenhuma busca dela tinha sido trazida antes.
  def ligar_na_primeira!(leitura)
    mudar!(true) unless trazidas.where.not(id: leitura.id).exists?
  end

  # A conta já trouxe uma busca do Agger: só então a tela mostra o interruptor.
  def ja_trouxe?
    trazidas.exists?
  end

  private

  def trazidas
    Carteira::Leitura.do_conector.where(account_id: @account.id).where.not(confirmada_em: nil)
  end
end
