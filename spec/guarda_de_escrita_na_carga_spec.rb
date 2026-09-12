require 'rails_helper'

# AUTOTESTE DA GUARDA (regra 3, como em `recusa_guarda_spec`): uma medição quebrada devolveria
# "nada cresceu" e a guarda passaria elogiando o silêncio. Aqui ela reprova.
#
# TUDO COM ESCRITA DE VERDADE NO BANCO. Notificação sintética prova classificação de texto — que é
# exatamente o que esta versão parou de fazer. O que precisa ficar provado é outra coisa: que quem
# decide é a contagem do PostgreSQL. Por isso cada exemplo abre a janela, executa SQL de verdade e
# pergunta o veredito.
#
# SEM A TRANSAÇÃO DO EXEMPLO: a estatística do PostgreSQL só é descarregada no FIM de uma
# transação, então dentro da transação de `use_transactional_fixtures` a medição fica cega —
# medido: delta 0 para um `INSERT` real, delta 2 para o mesmo `INSERT` fora dela. As escritas vão
# para uma tabela de rascunho, criada e derrubada no próprio exemplo, para que nenhuma tabela de
# aplicação seja tocada.
RSpec.describe GuardaDeEscritaNaCarga do
  self.use_transactional_tests = false

  # A guarda é acumulador de módulo e já foi lida pelo `before(:suite)`; ainda assim devolvemos o
  # processo como estava — inclusive sem subscriber, que é como `conferir!` o deixou. Deixar o
  # subscriber vivo custaria um `caller` por consulta no resto da suíte.
  around do |exemplo|
    suspeitos_anteriores = described_class.suspeitos.dup
    linha_base_anterior = described_class.instance_variable_get(:@linha_base)
    exemplo.run
  ensure
    described_class.parar!
    described_class.suspeitos.replace(suspeitos_anteriores)
    described_class.instance_variable_set(:@linha_base, linha_base_anterior)
  end

  before { conexao.execute("CREATE TABLE IF NOT EXISTS #{rascunho} (id serial primary key, nome text)") }

  after { conexao.execute("DROP TABLE IF EXISTS #{rascunho}") }

  def conexao
    ActiveRecord::Base.connection
  end

  # Método, e não constante: constante dentro de bloco é `Lint/ConstantDefinitionInBlock`, e este
  # nome só interessa a este arquivo.
  def rascunho
    'guarda_de_escrita_na_carga_rascunho'
  end

  # A guarda se abstém quando o banco não dá o sinal, e abstenção silenciosa é guarda desligada.
  # Quem cobra a existência do sinal é este exemplo: se o PostgreSQL do CI perder a função, ele
  # fica vermelho em vez de a guarda emudecer.
  describe 'o sinal que decide' do
    it 'existe neste PostgreSQL, e a medicao volta sem motivo de abstencao' do
      expect(conexao.select_value("SELECT count(*) FROM pg_proc WHERE proname = 'pg_stat_force_next_flush'")).to eq(1)
      expect(described_class.medir).to be_a(Hash)
      expect(described_class.motivo_da_abstencao).to be_nil
    end
  end

  # Os três SQLs que derrubaram a versão por expressão regular, agora executados de verdade. Os
  # dois primeiros só leem e não podem reprovar; o terceiro grava e tem de reprovar.
  describe 'os tres SQLs que derrubaram a versao por texto' do
    it 'nao reprova string delimitada por cifroes, que so le' do
      described_class.abrir!

      conexao.execute('SELECT $$ (INSERT INTO accounts) $$')

      expect { described_class.conferir! }.not_to raise_error
    end

    it 'nao reprova comentario aninhado, que so le' do
      described_class.abrir!

      conexao.execute('SELECT 1 /* externo /* interno */ resto */')

      expect { described_class.conferir! }.not_to raise_error
    end

    it 'reprova a CTE que escreve, que a versao por texto deixava passar' do
      conexao.execute("INSERT INTO #{rascunho} (nome) VALUES ('a'), ('b')")
      described_class.abrir!

      conexao.execute("WITH a AS (SELECT 1) UPDATE #{rascunho} SET nome = nome")

      expect { described_class.conferir! }.to raise_error(/durante a CARGA.*#{rascunho}\s+\+2/m)
    end
  end

  describe 'o veredito e da medicao, nao do subscriber' do
    it 'reprova escrita por raw_connection, que nao emite sql.active_record, dizendo que nao achou a origem' do
      described_class.abrir!

      conexao.raw_connection.exec("INSERT INTO #{rascunho} (nome) VALUES ('sem notificacao')")

      expect(described_class.suspeitos).to be_empty
      expect { described_class.conferir! }.to raise_error(/#{rascunho}\s+\+1.*SUSPEITOS: nenhum/m)
    end

    # Mutação embutida: com o diagnóstico desligado no meio da janela, a reprovação continua
    # acontecendo — só perde o endereço.
    it 'reprova sem o subscriber, perdendo o endereco e nao o veredito' do
      described_class.abrir!
      described_class.parar!

      conexao.execute("INSERT INTO #{rascunho} (nome) VALUES ('sem diagnostico')")

      expect(described_class.suspeitos).to be_empty
      expect { described_class.conferir! }.to raise_error(/#{rascunho}\s+\+1.*SUSPEITOS: nenhum/m)
    end

    it 'aponta arquivo, linha e SQL bruto quando o ActiveRecord anunciou, como indicio' do
      described_class.abrir!

      conexao.execute("INSERT INTO #{rascunho} (nome) VALUES ('com notificacao')")

      expect { described_class.conferir! }.to raise_error(
        /#{rascunho}\s+\+1.*indício, não veredito.*guarda_de_escrita_na_carga_spec\.rb:\d+.*INSERT INTO #{rascunho}/m
      )
    end
  end

  describe 'carga que nao escreveu' do
    it 'nao reprova, mesmo com consulta saindo de um arquivo de spec' do
      described_class.abrir!

      conexao.execute("SELECT count(*) FROM #{rascunho}")

      expect(described_class.suspeitos).not_to be_empty
      expect { described_class.conferir! }.not_to raise_error
    end

    it 'para de anotar depois de conferir!, que e o que fecha a janela' do
      described_class.abrir!
      described_class.conferir!

      conexao.execute("SELECT count(*) FROM #{rascunho}")

      expect(described_class.suspeitos).to be_empty
    end
  end

  # O pior desfecho de uma guarda não é reprovar à toa: é passar em silêncio. Dentro de transação
  # aberta o PostgreSQL não descarrega a estatística, e a leitura devolveria o número velho.
  describe 'medicao pedida dentro de transacao aberta' do
    it 'se abstem em vez de devolver numero velho' do
      described_class.abrir!

      conexao.transaction do
        conexao.execute("INSERT INTO #{rascunho} (nome) VALUES ('dentro da transacao')")
        expect(described_class.medir).to be_nil
      end

      expect(described_class.motivo_da_abstencao).to include('transação aberta')
    end
  end

  # Sem sinal do banco a guarda não adivinha: ela avisa e não julga.
  describe 'quando o banco nao da o sinal' do
    before do
      allow(described_class).to receive(:descarregar_estatistica)
        .and_raise(ActiveRecord::StatementInvalid, 'permission denied for function pg_stat_force_next_flush')
    end

    it 'se abstem, anuncia o motivo e nao reprova ninguem' do
      described_class.abrir!

      conexao.execute("INSERT INTO #{rascunho} (nome) VALUES ('escrita nao medida')")

      expect(described_class.motivo_da_abstencao).to include('permission denied')
      expect { described_class.conferir! }.to output(/ABSTENÇÃO/).to_stderr
    end
  end
end
