# O CSV ABERTO DE DENTRO DE UM ZIP, CONTADO (#2858, F5): passou de `teto` bytes abertos, `arquivo_grande_demais`.
# Contra bomba de zip cujo cabeçalho mente o tamanho aberto: o rubyzip não confere o declarado ao descomprimir. O `pos`
# do stream do rubyzip é quanto ele já abriu.
#
# As linhas saem daqui, de um buffer próprio lido em pedaços de `PEDACO` (o `gets` do rubyzip 2.4 quebra quando o
# limite chega antes do fim da linha). A linha também tem teto: `gets` sem limite (o cabeçalho) lê no máximo
# `MAX_LINHA` bytes, e chegar a ele sem o fim da linha é `formato_mudou` (um arquivo numa linha só encheria a memória
# antes do teto do aberto). Com limite (o CSV lê assim, em pedaços), devolve até o limite, como o `IO#gets`.
class Autonomia::FerramentasProntas::Bases::LeituraComTeto < SimpleDelegator
  MAX_LINHA = 1.megabyte
  PEDACO = 64.kilobytes
  FIM_DA_LINHA = "\n".freeze

  def initialize(io, teto)
    super(io)
    @teto = teto
    @buffer = ''.b
  end

  def gets(*args)
    separador = (args.first.is_a?(String) ? args.first : FIM_DA_LINHA).b
    limite = args.find { |argumento| argumento.is_a?(Integer) }
    linha = proxima_linha(separador, limite || MAX_LINHA)
    raise Autonomia::FerramentasProntas::Bases::Falha, 'formato_mudou' if limite.nil? && linha_cortada?(linha, separador)

    linha
  end

  def read(tamanho = nil, *)
    encher { |buffer| tamanho && buffer.bytesize >= tamanho }
    return nil if @buffer.empty? && tamanho

    @buffer.slice!(0, tamanho || @buffer.bytesize)
  end

  def eof?
    @buffer.empty? && __getobj__.eof?
  end
  alias eof eof?

  private

  def proxima_linha(separador, limite)
    encher { |buffer| buffer.include?(separador) || buffer.bytesize >= limite }
    return nil if @buffer.empty?

    fim = @buffer.index(separador)
    @buffer.slice!(0, fim ? [fim + separador.bytesize, limite].min : limite)
  end

  def linha_cortada?(linha, separador)
    linha && linha.bytesize >= MAX_LINHA && !linha.end_with?(separador)
  end

  # Lê pedaços do ZIP até o bloco dizer que basta (ou o arquivo acabar), conferindo o teto do aberto a cada um.
  def encher
    until yield(@buffer) || __getobj__.eof?
      pedaco = __getobj__.read(PEDACO)
      break if pedaco.nil?

      @buffer << pedaco
      raise Autonomia::FerramentasProntas::Bases::Falha, 'arquivo_grande_demais' if __getobj__.pos > @teto
    end
  end
end
