# CPF e CNPJ em tabela própria (épico #1240, decisão R1): o que os specs do documento repetem. Os números são sempre
# inventados (sequências), válidos só na conta do dígito verificador.
module DocumentoHelpers
  ARQUIVO_DO_MODEL = Rails.root.join('app/models/relacionamentos/documento.rb').to_s
  VARIAVEIS_DA_CIFRA = {
    'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY' => :primary_key,
    'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY' => :deterministic_key,
    'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT' => :key_derivation_salt
  }.freeze

  # O model decide se cifra quando o arquivo dele carrega (`encrypts ... if Chatwoot.encryption_configured?`), lendo as
  # três variáveis da instalação. Para ver os dois modos no mesmo processo, o arquivo é carregado de novo com as
  # variáveis postas ou tiradas. As chaves são as de teste do InsuranceEncryptionHelper. Use dentro do contexto
  # 'with o model do documento recarregado', que devolve a classe original no fim do exemplo.
  def carregar_o_documento(com_cifra:)
    chaves = InsuranceEncryptionHelper::TEST_KEYS
    ActiveRecord::Encryption.configure(**chaves, support_unencrypted_data: true) if com_cifra
    with_modified_env(VARIAVEIS_DA_CIFRA.transform_values { |chave| chaves.fetch(chave) if com_cifra }) { trocar_o_documento }
  end

  # Tira a classe do model e põe outra no lugar: a que o arquivo define ao carregar de novo, ou a `original` de volta.
  # O stub_const não serve aqui, porque quem cria a classe nova é o próprio arquivo do model.
  # rubocop:disable RSpec/RemoveConst -- sempre desfeito no fim do exemplo pelo contexto 'with o model do documento recarregado'
  def trocar_o_documento(original = nil)
    Relacionamentos.send(:remove_const, :Documento)
    original ? Relacionamentos.const_set(:Documento, original) : load(ARQUIVO_DO_MODEL)
  end
  # rubocop:enable RSpec/RemoveConst

  # O que está gravado na coluna, sem passar pelo model.
  def valor_no_banco(documento)
    ActiveRecord::Base.connection.select_value("SELECT valor FROM relacionamentos_documentos WHERE id = #{Integer(documento.id)}")
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

RSpec.shared_context 'with o model do documento recarregado' do
  around do |exemplo|
    original = Relacionamentos::Documento
    exemplo.run
  ensure
    trocar_o_documento(original)
  end
end

RSpec.configure do |config|
  config.include DocumentoHelpers
end
