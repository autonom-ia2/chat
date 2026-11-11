# O IMPORTADOR DE UMA BASE (#2858, F5): o que é próprio de cada base. Cada subclasse define:
#   - `CHAVE` (a do `Estado` e da fonte do catálogo), `MODELO` (a tabela), `COLUNAS` (as da tabela, sem `geracao`, na
#     ordem de cada linha), `HOSTS` (os únicos que o download chama), `FREQUENCIA` (`:diaria` ou `:mensal`), `MINIMO`
#     (menos linhas que isso é arquivo quebrado, não base menor) e, quando difere do padrão, `FRACAO_MINIMA` (nil: a
#     rodada nova pode vir bem menor que a anterior, como os focos de queimada);
#   - `baixar(download)`: os arquivos da rodada, já baixados (Tempfile), num Hash por nome;
#   - `linhas(arquivos)`: um Enumerator com cada linha da tabela (um Array na ordem de `COLUNAS`). Cabeçalho sem a coluna
#     esperada levanta `Falha('formato_mudou')`. Linha que não serve (sem a chave) vem nil e é pulada.
# Nenhuma linha leva CPF ou nome de pessoa física (ver cada importador).
class Autonomia::FerramentasProntas::Bases::Importador
  Falha = Autonomia::FerramentasProntas::Bases::Falha

  # A rodada nova que vier com menos que esta fração das linhas da anterior é recusada (arquivo cortado na fonte).
  FRACAO_MINIMA = 0.5
  DIAS_DO_MES = 28
  # Nenhum campo das fontes passa disso: um campo maior é arquivo que não é o esperado (e não ocupa a memória).
  MAX_CAMPO = 64.kilobytes
  DIGITOS_DO_CPF = 11
  SINAIS_DO_DOCUMENTO = './-'.freeze

  class << self
    def chave
      self::CHAVE
    end

    # A base já passou da hora? Pela DATA (UTC), não pela hora: a rodada das 10:47:00 pega a cópia que entrou às
    # 10:47:30. Diária: não foi atualizada hoje. Mensal: do 28º dia em diante. Nunca baixada: sim.
    def vencida?(estado, agora: Time.current)
      return true if estado.atualizado_em.nil?

      hoje = agora.utc.to_date
      copia = estado.atualizado_em.utc.to_date
      self::FREQUENCIA == :mensal ? copia <= hoje - DIAS_DO_MES : copia < hoje
    end

    def download
      Autonomia::FerramentasProntas::Bases::Download.new(hosts: self::HOSTS)
    end

    # O CSV de um arquivo baixado, linha a linha (`CSV::Row`, pelo nome da coluna), com o cabeçalho conferido.
    # `arquivo`: o baixado (Tempfile, aberto aqui na codificação da fonte) ou um IO já aberto (o CSV dentro do ZIP).
    # `preambulo`: o começo da linha que a fonte põe antes do cabeçalho (o RAB abre com "Atualizado em: …"), pulada.
    def csv(arquivo, colunas:, separador: ';', codificacao: 'bom|utf-8', preambulo: nil)
      io, proprio = abrir(arquivo, codificacao)
      cabecalho = cabecalho!(io, separador, colunas, preambulo)
      leitor = CSV.new(io, col_sep: separador, headers: cabecalho, liberal_parsing: true, max_field_size: MAX_CAMPO)
      Enumerator.new do |saida|
        leitor.each { |linha| saida << linha }
      rescue CSV::MalformedCSVError, ArgumentError, EncodingError
        raise Falha, 'formato_mudou'
      ensure
        io.close if proprio
      end
    rescue CSV::MalformedCSVError, ArgumentError, EncodingError
      io&.close if proprio
      raise Falha, 'formato_mudou'
    end

    # "2026-11-10" ou "10/11/2026" -> Date; o resto, nil.
    def data(valor)
      texto = valor.to_s.strip
      return nil if texto.empty?
      return Date.strptime(texto, '%d/%m/%Y') if texto.include?('/')

      Date.iso8601(texto)
    rescue Date::Error
      nil
    end

    def texto(valor)
      valor.to_s.squish.presence
    end

    def digitos(valor)
      valor.to_s.delete('^0-9').presence
    end

    # O nome de empresa sem nenhum CPF: o MEI leva o CPF do dono no fim da razão social ("FULANO 12345678909"). Sai cada
    # pedaço que, sem pontos e traço, tem 11 dígitos e é um CPF válido (dígitos verificadores conferidos).
    def sem_cpf(nome)
      texto(nome.to_s.split.reject { |pedaco| cpf?(pedaco.delete(SINAIS_DO_DOCUMENTO)) }.join(' '))
    end

    def cpf?(pedaco)
      pedaco.length == DIGITOS_DO_CPF && pedaco.delete('0-9').empty? && Autonomia::FerramentasProntas::Fontes::Cpf.valido?(pedaco)
    end

    private

    # -> [o IO, se fomos nós que abrimos (e fechamos)].
    def abrir(arquivo, codificacao)
      return [arquivo, false] unless arquivo.is_a?(Tempfile) || arquivo.is_a?(File)

      [File.open(arquivo.path, "rb:#{codificacao}"), true]
    end

    def cabecalho!(io, separador, colunas, preambulo)
      linha = utf8(io.gets).delete_prefix("\uFEFF")
      linha = utf8(io.gets) if preambulo && linha.start_with?(preambulo)
      cabecalho = Array(CSV.parse_line(linha, col_sep: separador)).map { |coluna| coluna.to_s.strip }
      raise Falha, 'formato_mudou' unless (colunas - cabecalho).empty?

      cabecalho
    end

    # A linha de um IO binário (o CSV dentro do ZIP) passa a ser lida como UTF-8; a do arquivo já vem convertida.
    def utf8(linha)
      texto = linha.to_s
      texto.encoding == Encoding::BINARY ? texto.dup.force_encoding(Encoding::UTF_8) : texto
    end
  end
end
