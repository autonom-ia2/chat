# A IMPORTAÇÃO DE UMA BASE (#2858, F5), igual para todas. A ordem:
#   1. as travas: a do Redis e a do banco (`pg_try_advisory_lock`), uma rodada por base de cada vez, mesmo com o Redis
#      fora ou limpo; ocupada, nada acontece;
#   2. sobra de uma rodada que morreu no meio (geração diferente da que vale) é apagada;
#   3. o importador baixa os arquivos (streaming, com teto) e cada linha vai para a tabela pelo COPY do Postgres, com a
#      geração NOVA, ao lado da que vale: a busca continua lendo a antiga. O COPY roda numa transação própria, com
#      `statement_timeout` longo (`TEMPO_DO_COPY`): o teto da busca (POSTGRES_STATEMENT_TIMEOUT) derrubaria a ANTT;
#   4. a conferência: ao menos `MINIMO` linhas e ao menos `FRACAO_MINIMA` da rodada anterior (arquivo cortado na fonte
#      não troca; os focos de queimada não têm fração);
#   5. a troca: uma linha no `Estado` (a geração que vale, `atualizado_em`, `linhas`), atômica. A busca fixa a geração
#      no começo da consulta e confere no fim (`Bases::Provedor`), então nunca vê a tabela vazia nem duas gerações;
#   6. a geração antiga é apagada, em lotes.
# A segunda rodada não duplica: cada rodada é uma geração inteira, e a anterior sai depois da troca.
#
# FALHOU (download, formato, conferência ou defeito nosso): a geração nova é apagada, a que vale fica, o `Estado` guarda
# a falha e a equipe recebe o alerta (`Alerta`). Nunca levanta: o job não repete sozinho um download de 160 MB.
# Falha DEPOIS da troca (ao apagar a antiga): a nova já vale e fica; o `Estado` guarda `limpeza_pendente`, sai o alerta
# e a próxima rodada termina a limpeza (passo 2).
class Autonomia::FerramentasProntas::Bases::Importacao
  Falha = Autonomia::FerramentasProntas::Bases::Falha
  Estado = Autonomia::FerramentasProntas::Bases::Estado

  TRAVA = 'autonomia:prontas:base'.freeze
  VALIDADE_DA_TRAVA = 4.hours
  LOTE = 50_000
  PREFIXO = '[autonomia][pronta][base]'.freeze
  TEMPO_DO_COPY = '2h'.freeze
  LIMPEZA_PENDENTE = 'limpeza_pendente'.freeze

  # A chave da trava do banco de cada base (um inteiro estável, o que o `pg_try_advisory_lock` pede).
  def self.trava_no_banco(chave)
    Zlib.crc32("#{TRAVA}:#{chave}")
  end

  def initialize(importador, agora: Time.current)
    @importador = importador
    @agora = agora
  end

  # -> :atualizada, :falhou ou :ocupada.
  def call
    return :ocupada unless travar && travar_no_banco

    @estado = Estado.de(@importador.chave)
    @estado.update!(tentado_em: @agora)
    importar
  ensure
    destravar_no_banco
    destravar
  end

  private

  def importar
    limpar_sobras
    @nova = (@estado.geracao_ativa || 0) + 1
    linhas = gravar
    conferir!(linhas)
    trocar(linhas)
    @trocada = true
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
    com_tempo_do_copy do
      conexao.copy_data("COPY #{modelo.quoted_table_name} (#{colunas}) FROM STDIN", PG::TextEncoder::CopyRow.new) do
        linhas.each do |linha|
          next if linha.nil?

          conexao.put_copy_data([@nova, *linha])
          total += 1
        end
      end
    end
    total
  end

  # O COPY na sua transação, com o teto de tempo dele (como `SearchService::BuscaDaLista#com_tempo_maximo`). Dentro de
  # outra transação (savepoint), o SET LOCAL duraria até o fim dela: o teto anterior volta no fim do COPY.
  def com_tempo_do_copy
    conexao = modelo.connection
    anterior = conexao.select_value('SHOW statement_timeout')
    modelo.transaction(requires_new: true) do
      conexao.execute("SET LOCAL statement_timeout = '#{TEMPO_DO_COPY}'")
      yield
      conexao.execute("SET LOCAL statement_timeout = #{conexao.quote(anterior)}")
    end
  end

  def conferir!(linhas)
    raise Falha, 'base_pequena_demais' if linhas < @importador::MINIMO

    fracao = @importador::FRACAO_MINIMA
    raise Falha, 'base_encolheu' if fracao && @estado.linhas.positive? && linhas < @estado.linhas * fracao
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

  # Antes da troca: a geração nova sai e a que vale fica. Depois da troca: a nova JÁ vale e fica (a limpeza da antiga
  # fica para a próxima rodada).
  def falhou(motivo)
    return limpeza_pendente if @trocada

    apagar(modelo.where(geracao: @nova)) if @nova
    registrar_falha(motivo)
    :falhou
  end

  def limpeza_pendente
    registrar_falha(LIMPEZA_PENDENTE)
    :atualizada
  end

  def registrar_falha(motivo)
    @estado.update!(falhou_em: @agora, motivo_da_falha: motivo)
    Autonomia::FerramentasProntas::Bases::Alerta.falhou!(@importador.chave, motivo, @estado)
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

  # A trava do banco é da sessão (da conexão deste job), e sai no `ensure` ou quando a conexão cai.
  def travar_no_banco
    @no_banco = modelo.connection.select_value("SELECT pg_try_advisory_lock(#{self.class.trava_no_banco(@importador.chave)})")
  end

  def destravar_no_banco
    modelo.connection.select_value("SELECT pg_advisory_unlock(#{self.class.trava_no_banco(@importador.chave)})") if @no_banco
  end
end
