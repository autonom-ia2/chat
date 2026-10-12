require 'rails_helper'
require Rails.root.join('db/migrate/20261018100000_recifrar_headers_das_ferramentas_dos_agentes.rb')

# #1301 — cabeçalho de Ferramenta gravado antes das chaves passa a ficar cifrado no banco, sem mudar o que se lê.
RSpec.describe RecifrarHeadersDasFerramentasDosAgentes do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true, instruction: 'Atenda.'
    )
  end
  let(:segredo) { 'Bearer segredo-de-teste' }
  let(:headers) { [{ 'key' => 'Authorization', 'value' => segredo, 'secret' => true }] }
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Consulta', slug: 'consulta',
      endpoint_url: 'https://exemplo.com.br/consulta'
    )
  end
  let(:ferramenta) { described_class::Ferramenta.find(tool.id) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  before do
    enable_test_encryption!
    gravar_legado(headers)
  end

  # A linha legada de produção, gravada por SQL: não depende de a classe do app ter carregado com ou sem `encrypts`.
  def gravar_legado(valor)
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql(['UPDATE autonomia_agent_tools SET headers_config = ?::jsonb WHERE id = ?', valor.to_json, tool.id])
    )
  end

  def valor_bruto
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql(['SELECT headers_config::text FROM autonomia_agent_tools WHERE id = ?', tool.id])
    )
  end

  # O critério da conferência por psql em produção: em claro é 'array' sem 'p'; cifrado é 'object' com 'p'.
  def formato_bruto
    ActiveRecord::Base.connection.select_rows(
      ActiveRecord::Base.sanitize_sql(
        ["SELECT jsonb_typeof(headers_config), headers_config ? 'p' FROM autonomia_agent_tools WHERE id = :id", { id: tool.id }]
      )
    ).first
  end

  def cifrado?(bruto)
    ActiveRecord::Encryption.encryptor.encrypted?(bruto)
  end

  # O model do app como fica em produção, com chaves: a mesma declaração `encrypts :headers_config`. Se a classe já
  # carregou com chaves neste processo, ela mesma serve; declarar de novo cifraria duas vezes.
  def model_do_app
    return Autonomia::Agents::Tool if Array(Autonomia::Agents::Tool.encrypted_attributes).include?(:headers_config)

    Class.new(Autonomia::Agents::Tool) do
      self.table_name = 'autonomia_agent_tools'
      encrypts :headers_config
    end
  end

  it 'cifra a linha em claro e o model do app lê o mesmo valor, com o segredo mascarado', :aggregate_failures do
    expect(cifrado?(valor_bruto)).to be(false)
    expect(formato_bruto).to eq(['array', false])

    described_class.new.up

    expect(cifrado?(valor_bruto)).to be(true)
    expect(formato_bruto).to eq(['object', true])
    expect(valor_bruto).not_to include('segredo-de-teste')
    lido = model_do_app.find(tool.id)
    expect(lido.headers_config).to eq(headers)
    expect(lido.masked_headers_config).to eq(
      [{ 'key' => 'Authorization', 'value' => Autonomia::Agents::Tool.masked_header_value, 'secret' => true }]
    )
  end

  it 'não toca a linha já cifrada' do
    ferramenta.encrypt
    bruto = valor_bruto
    expect(cifrado?(bruto)).to be(true)
    expect(formato_bruto).to eq(['object', true])

    expect { described_class.new.up }.not_to(change { valor_bruto })
    expect(valor_bruto).to eq(bruto)
    expect(formato_bruto).to eq(['object', true])
  end

  it 'sem chaves, não muda nada' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    bruto = valor_bruto

    expect { described_class.new.up }.not_to(change { valor_bruto })
    expect(cifrado?(bruto)).to be(false)
  end

  # `[]` não é vazio no banco: também é cifrado, e continua sendo lido como lista vazia.
  it 'cifra também a lista vazia', :aggregate_failures do
    gravar_legado([])
    expect(valor_bruto).to eq('[]')

    described_class.new.up

    expect(cifrado?(valor_bruto)).to be(true)
    expect(model_do_app.find(tool.id).headers_config).to eq([])
  end

  it 'registra só ids e contagem, nunca o valor do cabeçalho', :aggregate_failures do
    mensagens = []
    allow(Rails.logger).to receive(:info).and_wrap_original do |original, *args, &block|
      mensagens << (args.first || block&.call).to_s
      original.call(*args, &block)
    end

    described_class.new.up

    registro = mensagens.find { |mensagem| mensagem.start_with?('[recifrar_headers]') }
    expect(registro).to eq("[recifrar_headers] cifradas=1 ids=[#{tool.id}]")
    expect(mensagens.join("\n")).not_to include('segredo-de-teste')
    expect(mensagens.join("\n")).not_to include('Authorization')
  end
end
