# CPF e CNPJ em tabela própria (épico #1240, decisão R1): o que os specs do documento repetem. Os números são sempre
# inventados (sequências), válidos só na conta do dígito verificador.
module DocumentoHelpers
  ARQUIVO_DO_MODEL = Rails.root.join('app/models/relacionamentos/documento.rb').to_s
  VARIAVEIS_DA_CIFRA = {
    'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY' => :primary_key,
    'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY' => :deterministic_key,
    'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT' => :key_derivation_salt
  }.freeze
  # O que o `ActiveRecord::Encryption.configure` muda na configuração da cifra, que é uma só para o processo inteiro.
  CONFIG_DA_CIFRA = %i[primary_key deterministic_key key_derivation_salt support_unencrypted_data extend_queries previous_schemes].freeze

  # O model decide se cifra quando o arquivo dele carrega (`encrypts ... if Chatwoot.encryption_configured?`), lendo as
  # três variáveis da instalação. Para ver os dois modos no mesmo processo, o arquivo é carregado de novo com as
  # variáveis postas ou tiradas. As chaves são as de teste do InsuranceEncryptionHelper, e a configuração fica como a
  # do `config/application.rb` quando as chaves existem (lê texto puro e a busca acha as duas formas). Use dentro do
  # contexto 'with o model do documento recarregado', que desfaz tudo no fim do exemplo.
  def carregar_o_documento(com_cifra:)
    chaves = InsuranceEncryptionHelper::TEST_KEYS
    ActiveRecord::Encryption.configure(**chaves, support_unencrypted_data: true, extend_queries: true) if com_cifra
    with_modified_env(VARIAVEIS_DA_CIFRA.transform_values { |chave| chaves.fetch(chave) if com_cifra }) { trocar_o_documento }
    ligar_a_busca_estendida(Relacionamentos::Documento) if com_cifra
  end

  # Tira a classe do model e põe outra no lugar: a que o arquivo define ao carregar de novo, ou a `original` de volta.
  # O stub_const não serve aqui, porque quem cria a classe nova é o próprio arquivo do model.
  # rubocop:disable RSpec/RemoveConst -- sempre desfeito no fim do exemplo pelo contexto 'with o model do documento recarregado'
  def trocar_o_documento(original = nil)
    Relacionamentos.send(:remove_const, :Documento)
    original ? Relacionamentos.const_set(:Documento, original) : load(ARQUIVO_DO_MODEL)
  end
  # rubocop:enable RSpec/RemoveConst

  # O `extend_queries` do Rails, que faz a busca por valor achar também a linha gravada em texto puro. Na instalação ele
  # é ligado na subida (`ExtendedDeterministicQueries.install_support`), mexendo em toda relação do Active Record, e não
  # tem como desligar. Aqui as mesmas três peças entram só na classe recarregada, que some no fim do exemplo.
  def ligar_a_busca_estendida(model)
    busca = ActiveRecord::Encryption::ExtendedDeterministicQueries
    model.relation_delegate_class(ActiveRecord::Relation).prepend(busca::RelationQueries)
    model.include(busca::CoreQueries)
    model.type_for_attribute('valor').singleton_class.prepend(busca::ExtendedEncryptableType)
  end

  # A configuração da cifra como está agora, para devolver depois.
  def config_da_cifra
    config = ActiveRecord::Encryption.config
    chaves = VARIAVEIS_DA_CIFRA.values
    guardada = CONFIG_DA_CIFRA.without(*chaves).index_with { |nome| config.public_send(nome).dup }
    # A leitura de uma chave ausente levanta erro; `has_...?` devolve a chave ou nil.
    guardada.merge(chaves.index_with { |nome| config.public_send(:"has_#{nome}?") })
  end

  def devolver_a_config_da_cifra(guardada)
    guardada.each { |nome, valor| ActiveRecord::Encryption.config.public_send(:"#{nome}=", valor) }
    ActiveRecord::Encryption.reset_default_context
  end

  # O que está gravado na coluna, sem passar pelo model.
  def valor_no_banco(documento)
    ActiveRecord::Base.connection.select_value("SELECT valor FROM relacionamentos_documentos WHERE id = #{Integer(documento.id)}")
  end

  # Grava o número em texto puro na linha, como ficou quem guardou antes de a instalação ter as chaves.
  def gravar_em_texto_puro(documento, valor)
    conexao = ActiveRecord::Base.connection
    conexao.execute("UPDATE relacionamentos_documentos SET valor = #{conexao.quote(valor)} WHERE id = #{Integer(documento.id)}")
  end

  # Tudo o que o Rails e o Active Record escrevem no log enquanto o bloco roda, a partir do nível pedido.
  def log_de(nivel)
    anteriores = [Rails.logger, ActiveRecord::Base.logger]
    saida = StringIO.new
    registro = ActiveSupport::Logger.new(saida, level: nivel)
    Rails.logger = registro
    ActiveRecord::Base.logger = registro
    yield
    saida.string
  ensure
    Rails.logger, ActiveRecord::Base.logger = anteriores
  end
end

# O exemplo troca a classe do model e a configuração da cifra, que valem para o processo inteiro. As duas voltam ao que
# eram antes do exemplo, para os specs seguintes não herdarem chave nem modo de cifra daqui.
RSpec.shared_context 'with o model do documento recarregado' do
  around do |exemplo|
    original = Relacionamentos::Documento
    cifra = config_da_cifra
    exemplo.run
  ensure
    trocar_o_documento(original)
    devolver_a_config_da_cifra(cifra)
  end
end

RSpec.configure do |config|
  config.include DocumentoHelpers
end
