# #2889: o pedido que o Guia está fazendo AGORA pela porta da frente (Acoes#requisitar, pela ChamadaInterna).
#
# Só serve de rótulo: a automação criada pelo Guia nasce com origem 'guia', e não 'manual'. Não autoriza nada. Vive
# na thread, fora do `Current` (o pedido de dentro mexe no `Current`), e só o código do servidor o liga: um cliente de
# fora não tem como mandar este sinal, nem por cabeçalho. O passo "ação" da Automação livre (AcoesDoMotor) não passa
# por aqui: lá quem age é a automação (Autonomia::Automacao::Ato).
class Autonomia::Guide::PeloGuia
  thread_mattr_accessor :ativo, instance_accessor: false

  class << self
    def agora? = ativo == true

    def durante
      anterior = ativo
      self.ativo = true
      yield
    ensure
      self.ativo = anterior
    end
  end
end
