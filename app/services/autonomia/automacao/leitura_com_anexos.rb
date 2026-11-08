# G20 (#2669): a leitura do passo de IA (o Estado do Decisor) com os anexos da conversa (AnexosDaConversa). Vazia só
# quando não há texto nem anexo, para o currículo que chega sozinho, sem uma palavra, ainda ir à IA.
class Autonomia::Automacao::LeituraComAnexos < SimpleDelegator
  attr_reader :anexos

  def initialize(estado, anexos)
    super(estado)
    @anexos = anexos
  end

  def vazio? = __getobj__.vazio? && !@anexos&.algum?
end
