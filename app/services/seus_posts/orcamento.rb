# Seus posts (#2304): teto de tempo para ler um perfil na Meta. A leitura de um perfil faz várias chamadas, em
# sequência; o cliente (Meta::AdsGraphClient, `prazo:`) dá a cada uma só o tempo que falta do teto, inclusive a cada
# página de posts. Passado o teto, a chamada volta com o erro TEMPO, que `ler` transforma em Indisponivel ('tempo'), e
# SeusPosts::Leitura serve a última leitura boa guardada.
module SeusPosts::Orcamento
  SEGUNDOS = 20

  def perform
    @limite = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SEGUNDOS
    super
  end

  private

  def client(**)
    super(prazo: @limite, **)
  end
end
