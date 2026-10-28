# Seus posts (#2304): teto de tempo para ler um perfil na Meta. Cada chamada tem o próprio limite (8 s,
# Meta::AdsGraphClient), mas a leitura de um perfil faz várias, em sequência. Passado o teto, a próxima resposta lida
# vira Indisponivel ('tempo'), e SeusPosts::Leitura serve a última leitura boa guardada.
module SeusPosts::Orcamento
  SEGUNDOS = 20

  def perform
    @limite = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SEGUNDOS
    super
  end

  private

  def ler(result)
    raise Crm::MetaAds::Organico::Indisponivel.new('passou do tempo', codigo: 'tempo') if passou_do_tempo?

    super
  end

  def passou_do_tempo?
    @limite && Process.clock_gettime(Process::CLOCK_MONOTONIC) > @limite
  end
end
