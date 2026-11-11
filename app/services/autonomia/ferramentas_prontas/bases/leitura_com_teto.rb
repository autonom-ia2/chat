# O CSV ABERTO DE DENTRO DE UM ZIP, CONTADO (#2858, F5): passou de `teto` bytes entregues, `arquivo_grande_demais`.
# Contra bomba de zip cujo cabeçalho mente o tamanho aberto: o rubyzip não confere o declarado ao descomprimir. O `pos`
# do stream do rubyzip é quanto ele já entregou, aberto; o CSV lê por `gets` (e `read`, por garantia).
class Autonomia::FerramentasProntas::Bases::LeituraComTeto < SimpleDelegator
  def initialize(io, teto)
    super(io)
    @teto = teto
  end

  def gets(*)
    conferir(__getobj__.gets(*))
  end

  def read(*)
    conferir(__getobj__.read(*))
  end

  private

  def conferir(lido)
    raise Autonomia::FerramentasProntas::Bases::Falha, 'arquivo_grande_demais' if __getobj__.pos > @teto

    lido
  end
end
