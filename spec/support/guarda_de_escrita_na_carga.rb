# GUARDA: escrita no banco em TEMPO DE CARGA reprova a suíte deste nó.
#
# O corpo de um `describe`/`context` roda quando o RSpec CARREGA o arquivo — antes de existir
# exemplo, e portanto FORA da transação que `use_transactional_fixtures` abre por exemplo. A linha
# criada ali é COMMITADA e sobrevive ao processo inteiro, poluindo todos os exemplos de todos os
# outros arquivos do mesmo nó.
#
# Foi o defeito de `slack_uploads_controller_spec.rb` (corrigido no mesmo commit): um
# `ActiveStorage::Blob.create_and_upload!` no corpo do `context` deixava uma linha em
# `active_storage_blobs`, e as quatro asserções `expect(ActiveStorage::Blob.count).to eq(0)` de
# `entrega_de_arquivo_spec.rb` falhavam com `got: 1` — mas SÓ quando os dois arquivos caíam no
# mesmo nó. Como o CI fatia em round-robin sobre `find spec -name '*_spec.rb' | sort`
# (`.github/workflows/testes.yml`), UM arquivo novo em qualquer lugar da árvore remonta os blocos
# e o vermelho reaparece numa PR que não tem nada a ver com isso.
#
# POR QUE EM TEMPO DE EXECUÇÃO, e não por AST como `VarreduraDeRecusas`: uma varredura estática
# teria de enumerar as formas de escrever (`create!`, `create_and_upload!`, `insert_all`,
# `update!`, `FactoryBot.create`, um helper que faz isso lá dentro) e envelheceria na primeira
# forma nova. Aqui quem acusa é o próprio `INSERT`/`UPDATE`/`DELETE` chegando ao banco: fecha a
# CLASSE — qualquer forma, qualquer tabela, qualquer indireção — e ainda dá o `arquivo:linha`.
# O custo é um subscriber de `sql.active_record` vivo só durante a carga, onde não há consulta.
#
# A CONFERÊNCIA É DE SUÍTE, não um exemplo: um exemplo só roda no nó que sorteou o arquivo dele, e
# o vazamento pode estar em outro nó. Em `before(:suite)` ela roda em TODOS os nós, e reprova
# justamente o nó que carregou o arquivo culpado — que é o nó onde a poluição acontece.
#
# O QUE FICA DE FORA: `rspec --dry-run` não roda hook nenhum, então lá a guarda é silenciosa (para
# esse caso, conte as linhas no banco depois). A guarda vê o que foi CARREGADO: um arquivo fora da
# rodada não é conferido — no CI isso não é lacuna, porque os oito nós juntos carregam todos. E ela
# escuta `sql.active_record`: quem pegar o `raw_connection` e escrever por fora do ActiveRecord não
# emite a notificação, e escapa.
module GuardaDeEscritaNaCarga
  # Escrita na cabeça do comando — a forma que o ActiveRecord emite em quase todo caso.
  ESCRITA = /\A\s*(?:INSERT|UPDATE|DELETE)\b/i

  # Escrita dentro de CTE: `WITH nova AS (INSERT ... RETURNING id) SELECT id FROM nova`. O comando
  # começa com `WITH`, então `ESCRITA` não o vê — mas ele grava do mesmo jeito.
  ESCRITA_EM_CTE = /\A\s*WITH\b.*?\(\s*(?:INSERT|UPDATE|DELETE)\b/im

  # Texto entre aspas simples, identificador entre aspas duplas e comentário (de bloco ou de linha),
  # numa varredura só: quem começa primeiro vence, então `'--'` continua sendo texto e `/* it's */`
  # continua sendo comentário. Sem isso um comentário na frente esconde o `INSERT`
  # (`/* fixture */ INSERT INTO ...`) e a palavra `insert` dentro de uma string acusa quem não
  # escreveu nada.
  RUIDO = %r{'(?:[^']|'')*'|"(?:[^"]|"")*"|/\*.*?\*/|--[^\n]*}m

  # Só o que vem de um ARQUIVO DE SPEC. `spec/rails_helper.rb` e os helpers de `spec/support`
  # também estão sob `spec/`, e `maintain_test_schema!` escreve em `ar_internal_metadata` de
  # forma legítima; filtrar pelo arquivo de spec descreve o defeito e ignora o ruído do framework.
  ORIGEM = /_spec\.rb:\d+/

  class << self
    def escritas
      @escritas ||= []
    end

    # Chamada no fim de `rails_helper`: depois de `maintain_test_schema!` e antes de o RSpec
    # carregar o primeiro arquivo de spec.
    def vigiar!
      return if @assinatura

      @assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |_nome, _inicio, _fim, _id, dados|
        registrar(dados)
      end
    end

    def parar!
      ActiveSupport::Notifications.unsubscribe(@assinatura) if @assinatura
      @assinatura = nil
    end

    # Comentário vira espaço e texto vira string vazia, para que a decisão olhe só o comando.
    def limpar(sql)
      sql.gsub(RUIDO) { |trecho| trecho.start_with?("'", '"') ? "''" : ' ' }
    end

    def escrita?(sql)
      comando = limpar(sql)
      comando.match?(ESCRITA) || comando.match?(ESCRITA_EM_CTE)
    end

    def registrar(dados)
      return unless escrita?(dados[:sql].to_s)

      origem = caller.find { |linha| linha.match?(ORIGEM) }
      return if origem.nil?

      endereco = origem.delete_prefix(Rails.root.to_s).delete_prefix('/')
      escritas << "#{endereco}\n      #{dados[:sql].to_s.squish.truncate(140)}"
    end

    def conferir!
      parar!
      return if escritas.empty?

      raise <<~ERRO
        Escrita no banco durante a CARGA dos arquivos de spec — fora de `it`, `let` ou `before`.

        O corpo de `describe`/`context` roda antes de existir exemplo, logo fora da transação de
        `use_transactional_fixtures`: a linha é COMMITADA e polui todos os exemplos deste nó.
        Mova a criação para `let` / `let!` / `before`.

        #{escritas.join("\n    ")}
      ERRO
    end
  end
end
