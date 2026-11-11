# A IMPORTAÇÃO DE UMA BASE (#2858, F5), igual para todas. A ordem:
#   1. a trava (Redis, uma rodada por base de cada vez); ocupada, nada acontece;
#   2. sobra de uma rodada que morreu no meio (geração diferente da que vale) é apagada;
#   3. o importador baixa os arquivos (streaming, com teto) e cada linha vai para a tabela pelo COPY do Postgres, com a
#      geração NOVA, ao lado da que vale: a busca continua lendo a antiga;
#   4. a conferência: ao menos `MINIMO` linhas e ao menos metade da rodada anterior (arquivo cortado na fonte não troca);
#   5. a troca: uma linha no `Estado` (a geração que vale, `atualizado_em`, `linhas`), atômica. A busca lê a geração numa
#      subconsulta do mesmo comando (`Vigente`), então nunca vê a tabela vazia;
#   6. a geração antiga é apagada, em lotes.
# A segunda rodada não duplica: cada rodada é uma geração inteira, e a anterior sai depois da troca.
#
# FALHOU (download, formato, conferência ou defeito nosso): a geração nova é apagada, a que vale fica, o `Estado` guarda
# a falha e a equipe recebe o alerta (`Alerta`). Nunca levanta: o job não repete sozinho um download de 160 MB.
class Autonomia::FerramentasProntas::Bases::Importacao
  Falha = Autonomia::FerramentasProntas::Bases::Falha
  Estado = Autonomia::FerramentasProntas::Bases::Estado

  TRAVA = 'autonomia:prontas:base'.freeze
  VALIDADE_DA_TRAVA = 4.hours
  LOTE = 50_000
  PREFIXO = '[autonomia][pronta][base]'.freeze

  def initialize(importador, agora: Time.current)
    @importador = importador
    @agora = agora
  end

  # -> :atualizada, :falhou ou :ocupada.
  def call
    return :ocupada unless travar

    @estado = Estado.de(@importador.chave)
    @estado.update!(tentado_em: @agora)
    importar
  ensure
    destravar
  end

  private

  def importar
    limpar_sobras
    @nova = (@estado.geracao_ativa || 0) + 1
    linhas = gravar
    conferir!(linhas)
    trocar(linhas)
    apagar_antigas
    :atualizada
  rescue Falha => e
    falhou(e.motivo)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    falhou('defeito')
  end

  def gravar
    arquivos = @importador.baixar(@importador.download)
    copiar(@importador.linhas(arquivos))
  ensure
    Array(arquivos&.values).compact.each(&:close!)
  end

  # O COPY da geração nova: rápido para um milhão de linhas, e nada fica visível antes da troca (a busca filtra pela
  # geração que vale).
  def copiar(linhas)
    conexao = modelo.connection.raw_connection
    colunas = ['geracao', *@importador::COLUNAS].map { |coluna| modelo.connection.quote_column_name(coluna) }.join(', ')
    total = 0
    conexao.copy_data("COPY #{modelo.quoted_table_name} (#{colunas}) FROM STDIN", PG::TextEncoder::CopyRow.new) do
      linhas.each do |linha|
        next if linha.nil?

        conexao.put_copy_data([@nova, *linha])
        total += 1
      end
    end
    total
  end

  def conferir!(linhas)
    raise Falha, 'base_pequena_demais' if linhas < @importador::MINIMO
    raise Falha, 'base_encolheu' if @estado.linhas.positive? && linhas < @estado.linhas * @importador::FRACAO_MINIMA
  end

  def trocar(linhas)
    @estado.update!(geracao_ativa: @nova, atualizado_em: @agora, linhas: linhas, falhou_em: nil, motivo_da_falha: nil)
    Rails.logger.info("#{PREFIXO} base=#{@importador.chave} atualizada geracao=#{@nova} linhas=#{linhas}")
  end

  def apagar_antigas
    apagar(modelo.where.not(geracao: @nova))
  end

  def limpar_sobras
    sobras = @estado.geracao_ativa ? modelo.where.not(geracao: @estado.geracao_ativa) : modelo.all
    apagar(sobras)
  end

  def apagar(escopo)
    escopo.in_batches(of: LOTE).delete_all
  end

  def falhou(motivo)
    apagar(modelo.where(geracao: @nova)) if @nova
    @estado.update!(falhou_em: @agora, motivo_da_falha: motivo)
    Autonomia::FerramentasProntas::Bases::Alerta.falhou!(@importador.chave, motivo, @estado)
    :falhou
  end

  def modelo
    @importador::MODELO
  end

  def travar
    @token = SecureRandom.hex(8)
    Redis::Alfred.set(chave_da_trava, @token, nx: true, ex: VALIDADE_DA_TRAVA.to_i) ? true : false
  end

  def destravar
    Redis::Alfred.delete(chave_da_trava) if @token && Redis::Alfred.get(chave_da_trava) == @token
  end

  def chave_da_trava
    "#{TRAVA}:#{@importador.chave}"
  end
end
