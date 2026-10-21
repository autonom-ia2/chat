require 'rails_helper'
require 'open3'

RSpec.describe MigrationsSeguras::SchemaRb do
  def schema(corpo)
    <<~RUBY
      ActiveRecord::Schema[7.2].define(version: 2026_11_08_230000) do
        enable_extension "pg_trgm"
      #{corpo}
      end
    RUBY
  end

  let(:contatos) do
    <<~RUBY
      create_table "contacts", id: :serial, force: :cascade do |t|
        t.string "name", default: ""
        t.string "email", limit: 50
        t.integer "account_id", null: false
        t.string "apelido", default: nil
        t.index ["account_id"], name: "index_contacts_on_account_id"
        t.check_constraint "account_id > 0", name: "conta_positiva"
      end
    RUBY
  end
  let(:notas) do
    <<~RUBY
      create_table "notas", id: false, force: :cascade do |t|
        t.bigint "contact_id"
      end

      add_foreign_key "notas", "contacts"
    RUBY
  end
  let(:base) { schema(contatos + notas) }

  it 'lê as colunas com tipo, limite, nulo e default, sem banco' do
    colunas = described_class.ler(base).dig('tabelas', 'contacts', 'colunas')

    expect(colunas['id']).to include('tipo' => 'integer limit=4', 'tipo_base' => 'integer', 'limite' => 4, 'nulo' => false)
    expect(colunas['email']).to include('tipo' => 'string limit=50', 'tipo_base' => 'string', 'limite' => 50)
    expect(colunas['account_id']['nulo']).to be(false)
    expect(colunas['name']['default']).to eq('')
    expect(colunas['apelido']['default']).to be_nil
  end

  it 'lê extensões, chave primária, índices, restrições e chaves estrangeiras' do
    estrutura = described_class.ler(base)

    expect(estrutura['extensoes']).to eq(['pg_trgm'])
    expect(estrutura.dig('tabelas', 'contacts')).to include('chave_primaria' => ['id'], 'restricoes' => { 'conta_positiva' => 'account_id > 0' })
    expect(estrutura.dig('tabelas', 'contacts', 'indices').keys).to eq(['index_contacts_on_account_id'])
    expect(estrutura.dig('tabelas', 'notas')).to include('chave_primaria' => [], 'chaves_estrangeiras' => { 'contacts.' => { 'para' => 'contacts' } })
  end

  it 'lê o db/schema.rb do repositório inteiro' do
    estrutura = described_class.ler(Rails.root.join('db/schema.rb').read)

    expect(estrutura['tabelas'].size).to eq(ActiveRecord::Base.connection.tables.size - 2)
    expect(estrutura.dig('tabelas', 'contacts', 'colunas').keys).to include('email', 'account_id')
  end

  describe 'contra a blue, com a Compatibilidade' do
    def comparar(depois, retiradas = {})
      MigrationsSeguras::Compatibilidade.new(antes: described_class.ler(base), depois: described_class.ler(depois), retiradas: retiradas)
    end

    it 'bloqueia coluna que a blue grava e que o commit novo removeu, a não ser que a blue a tenha anunciado' do
      sem_apelido = base.sub('t.string "apelido", default: nil', '')
      expect(sem_apelido).not_to eq(base)

      expect(comparar(sem_apelido).bloqueios.map(&:onde)).to eq(['contacts.apelido'])
      expect(comparar(sem_apelido, 'colunas' => ['contacts.apelido'])).to be_compativel
    end

    it 'só avisa quando o limite do mesmo tipo aumentou, inclusive integer para bigint' do
      verificacao = comparar(base.sub('limit: 50', 'limit: 100').sub('t.integer "account_id"', 't.bigint "account_id"'))

      expect(verificacao).to be_compativel
      expect(verificacao.avisos.map(&:onde)).to contain_exactly('contacts.email', 'contacts.account_id')
    end

    it 'avisa índice com a definição mudada e SQL do schema.rb (gatilho) que sumiu ou mudou' do
      com_gatilho = schema(%(#{contatos}#{notas}  execute("CREATE TRIGGER trava BEFORE DELETE ON notas")\n))
      mudado = schema(contatos.sub('name: "index_contacts_on_account_id"', 'name: "index_contacts_on_account_id", where: "account_id > 0"') + notas)

      verificacao = MigrationsSeguras::Compatibilidade.new(antes: described_class.ler(com_gatilho), depois: described_class.ler(mudado))

      expect(verificacao).to be_compativel
      expect(verificacao.avisos.map(&:onde)).to contain_exactly('contacts.index_contacts_on_account_id',
                                                                'CREATE TRIGGER trava BEFORE DELETE ON notas')
    end
  end

  it 'lê função em heredoc e create_trigger encadeado (hairtrigger), com o md5 do corpo' do
    funcao = <<~RUBY
        execute(<<-SQL)
      CREATE OR REPLACE FUNCTION public.trava()
       RETURNS trigger
      AS $function$ BEGIN RAISE EXCEPTION 'não'; END; $function$
        SQL
        create_trigger("notas_tr", generated: true, compatibility: 1).
            on("notas").
            before(:delete) do
          "RAISE EXCEPTION 'não';"
        end
    RUBY
    antes = described_class.ler(schema(contatos + notas + funcao))
    depois = described_class.ler(schema(contatos + notas + funcao.sub("RAISE EXCEPTION 'não'; END", 'RETURN OLD; END')))

    expect(antes['funcoes'].keys).to eq(['CREATE OR REPLACE FUNCTION public.trava()'])
    expect(antes['gatilhos'].keys).to eq(['create_trigger notas_tr'])
    avisos = MigrationsSeguras::Compatibilidade.new(antes: antes, depois: depois).avisos.map(&:to_s)
    expect(avisos).to eq(['`CREATE OR REPLACE FUNCTION public.trava()`: função com o corpo mudado'])
  end

  describe 'scripts/deploy/compatibilidade_com_a_blue.rb' do
    def rodar(schema_novo, retiradas: nil)
      Dir.mktmpdir do |pasta|
        File.write("#{pasta}/blue.rb", base)
        File.write("#{pasta}/novo.rb", schema_novo)
        argumentos = ["#{pasta}/blue.rb", "#{pasta}/novo.rb"]
        if retiradas
          File.write("#{pasta}/retiradas.yml", retiradas)
          argumentos << "#{pasta}/retiradas.yml"
        end
        # Ruby puro, como no runner do deploy: sem o Rails nem o bundle.
        Open3.capture2e({ 'RUBYOPT' => nil, 'BUNDLE_GEMFILE' => nil }, RbConfig.ruby, '--disable-gems',
                        Rails.root.join('scripts/deploy/compatibilidade_com_a_blue.rb').to_s, *argumentos)
      end
    end

    it 'sai 0 quando a blue aguenta e 1 com o motivo quando não aguenta' do
      saida, status = rodar(base)
      expect(status.exitstatus).to eq(0), saida

      sem_tabela = schema(contatos)
      saida, status = rodar(sem_tabela)
      expect(status.exitstatus).to eq(1)
      expect(saida).to include('::error::A blue não aguenta o schema novo: `notas`')

      _saida, status = rodar(sem_tabela, retiradas: "tabelas:\n  - notas\n")
      expect(status.exitstatus).to eq(0)
    end
  end
end
