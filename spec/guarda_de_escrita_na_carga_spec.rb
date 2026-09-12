require 'rails_helper'

# AUTOTESTE DA GUARDA (regra 3, como em `recusa_guarda_spec`): um subscriber quebrado devolveria
# lista vazia e a guarda passaria elogiando o silêncio. Aqui ela reprova.
#
# Alimentar `registrar` na mão prova só a classificação do SQL — com `vigiar!` trocado por um
# método vazio o arquivo inteiro continuaria verde, porque nenhum exemplo passaria pela inscrição.
# Por isso o bloco `a inscrição em sql.active_record` publica pelo `ActiveSupport::Notifications`
# de verdade (e uma vez por SQL de verdade, pelo ActiveRecord): é o caminho que roda em produção
# de teste, e é ele que reprova quando a inscrição não acontece.
RSpec.describe GuardaDeEscritaNaCarga do
  # A lista é acumulador de módulo e já foi lida pelo `before(:suite)`; ainda assim, devolvemos o
  # processo como estava — inclusive sem subscriber, que é como `conferir!` o deixou.
  around do |exemplo|
    anterior = described_class.escritas.dup
    described_class.escritas.clear
    exemplo.run
  ensure
    described_class.parar!
    described_class.escritas.replace(anterior)
  end

  # Emite a notificação pelo barramento real. O `caller` de quem registra passa por aqui, que é um
  # `_spec.rb`, então o filtro `ORIGEM` da guarda enxerga a origem como enxergaria num spec culpado.
  def publicar(sql)
    ActiveSupport::Notifications.instrument('sql.active_record', sql: sql) { nil }
  end

  describe 'a inscricao em sql.active_record' do
    it 'reprova a carga que escreveu, com o SQL chegando pelo ActiveSupport::Notifications' do
      described_class.vigiar!

      publicar('INSERT INTO active_storage_blobs (key) VALUES ($1)')

      expect { described_class.conferir! }
        .to raise_error(/durante a CARGA.*guarda_de_escrita_na_carga_spec\.rb:.*INSERT INTO active_storage_blobs/m)
    end

    # Sem dublê nenhum: SQL de verdade pelo ActiveRecord. `WHERE id = -1` não toca linha alguma —
    # o que importa é o comando chegar ao banco e a guarda vê-lo pela instrumentação do Rails.
    it 'enxerga UPDATE de verdade emitido pelo ActiveRecord' do
      described_class.vigiar!

      ActiveRecord::Base.connection.execute('UPDATE accounts SET name = name WHERE id = -1')

      expect(described_class.escritas.join).to include('spec/guarda_de_escrita_na_carga_spec.rb:', 'UPDATE accounts')
    end

    it 'nao anota mais nada depois de parar!, que e o que conferir! faz antes de julgar' do
      described_class.vigiar!
      described_class.parar!

      publicar('INSERT INTO active_storage_blobs (key) VALUES ($1)')

      expect(described_class.escritas).to be_empty
    end
  end

  describe '.registrar' do
    it 'anota INSERT, UPDATE e DELETE com o arquivo e a linha de quem escreveu' do
      described_class.registrar(sql: 'INSERT INTO active_storage_blobs (key) VALUES ($1)')
      described_class.registrar(sql: 'UPDATE accounts SET name = $1')
      described_class.registrar(sql: 'DELETE FROM accounts WHERE id = $1')

      expect(described_class.escritas.size).to eq(3)
      expect(described_class.escritas.first).to include('spec/guarda_de_escrita_na_carga_spec.rb:',
                                                        'INSERT INTO active_storage_blobs')
    end

    # Um comentário na frente do comando é escrita igual: `annotate`, fixture de banco e ferramenta
    # de APM prefixam SQL desse jeito, e o primeiro termo deixa de ser o verbo.
    it 'anota escrita escondida atras de comentario, de bloco ou de linha' do
      described_class.registrar(sql: '/* fixture */ INSERT INTO active_storage_blobs (key) VALUES ($1)')
      described_class.registrar(sql: "-- fixture\nUPDATE accounts SET name = $1")

      expect(described_class.escritas.size).to eq(2)
    end

    # CTE que grava: o comando começa com `WITH`, e a linha é COMMITADA do mesmo jeito.
    it 'anota escrita dentro de CTE, que comeca com WITH' do
      described_class.registrar(
        sql: 'WITH nova AS (INSERT INTO active_storage_blobs (key) VALUES ($1) RETURNING id) SELECT id FROM nova'
      )

      expect(described_class.escritas.size).to eq(1)
    end

    it 'ignora leitura e transacao, que a carga faz sem sujar nada' do
      ['SELECT COUNT(*) FROM accounts', 'BEGIN', 'COMMIT', 'SHOW search_path'].each do |sql|
        described_class.registrar(sql: sql)
      end

      expect(described_class.escritas).to be_empty
    end

    # O reconhecimento mais largo não pode acusar quem só LÊ: a palavra dentro de texto ou de nome
    # de coluna não é comando. Falso positivo aqui reprovaria um nó inteiro por nada.
    it 'nao acusa a palavra insert dentro de texto ou de nome de coluna' do
      [
        "SELECT id FROM accounts WHERE name = 'insert into accounts'",
        'SELECT inserted_at FROM accounts',
        "WITH recente AS (SELECT '(insert into x' AS rotulo, \"insert\" FROM accounts) SELECT * FROM recente"
      ].each { |sql| described_class.registrar(sql: sql) }

      expect(described_class.escritas).to be_empty
    end
  end

  describe '.conferir!' do
    it 'nao reprova quando a carga nao escreveu' do
      expect { described_class.conferir! }.not_to raise_error
    end

    it 'reprova com o endereco e o SQL quando a carga escreveu' do
      described_class.registrar(sql: 'INSERT INTO active_storage_blobs (key) VALUES ($1)')

      expect { described_class.conferir! }
        .to raise_error(/durante a CARGA.*guarda_de_escrita_na_carga_spec\.rb:.*INSERT INTO active_storage_blobs/m)
    end
  end
end
