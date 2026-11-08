# Fuso da conta de anúncios (#2198): as datas da tela ("começa hoje", "termina em 30/11") valem nele. A conexão guarda o
# fuso quando a primeira leitura de resultados acontece; antes disso, lê na Meta e guarda. Sem fuso, não cria nem muda
# data: um dia errado no início ou no fim é dinheiro gasto fora do combinado.
class Crm::MetaAds::Creation::AccountZone
  def initialize(connection, client)
    @connection = connection
    @client = client
  end

  def zone
    ActiveSupport::TimeZone[@connection.ad_account_timezone.to_s] || read_and_save
  end

  private

  def read_and_save
    result = @client.ad_account(@connection.ad_account_id)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok

    found = ActiveSupport::TimeZone[result.data['timezone_name'].to_s]
    raise Crm::MetaAds::Creation::Error, 'meta_refused' if found.nil?

    # Só esta coluna: um problema antigo em outro campo da conexão não pode impedir de criar ou mudar o orçamento.
    @connection.update_column(:ad_account_timezone, result.data['timezone_name']) # rubocop:disable Rails/SkipsModelValidations
    found
  end
end
