# Seus posts (#2304): teto de tempo para ler um perfil na Meta. A leitura de um perfil (números e posts) faz várias
# chamadas, em sequência, e todas dividem o mesmo prazo, que SeusPosts::Leitura marca uma vez por perfil. O cliente
# (Meta::AdsGraphClient::Prazo) dá a cada chamada só o tempo que falta, inclusive a cada página de posts. Passado o
# teto, a chamada volta com o erro TEMPO, que `ler` transforma em Indisponivel ('tempo'), e SeusPosts::Leitura serve a
# última leitura boa guardada.
module SeusPosts::Orcamento
  SEGUNDOS = 20

  def self.prazo
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + SEGUNDOS
  end

  # prazo: o do perfil; sem ele (quem lê só uma parte), o teto conta de quando a leitura começa.
  def initialize(prazo: nil, **)
    @prazo = prazo
    super(**)
  end

  private

  def client(**)
    super(prazo: @prazo ||= SeusPosts::Orcamento.prazo, **)
  end
end
