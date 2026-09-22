require 'rails_helper'

# TUDO O QUE O FORMULÁRIO DO RAMO DECLARA É ENVIADO (chat#591, critério 1 da issue). É o
# `quote_input_travessia_spec` de auto feito para um ramo: cada folha do formulário de residencial,
# gerado do schema do adapter, recebe um valor, e a entrada montada tem de carregar todas, no
# caminho em que o adapter as lê (`segurado.*`, `configuracoes.*`).
#
# O mesmo defeito que auto teve até 10/09/2026, e que um ramo novo repetiria sem guarda: campo
# declarado ao modelo e descartado na montagem da entrada.
RSpec.describe Autonomia::Insurance::QuoteInput do
  let(:schema) { Autonomia::Insurance::Connector::Mock::SCHEMA_RESIDENCIAL }
  let(:parametros) { Autonomia::Insurance::Parametros.new(schema, ramo: true) }

  def amostra(folha)
    return folha['enum'].first if folha['enum']

    { 'string' => 'x', 'number' => 7, 'boolean' => false }.fetch(folha['type'])
  end

  # O formulário inteiro preenchido. `false` de propósito nos booleanos: é resposta, e tem de chegar.
  def params_completos
    Autonomia::Insurance::Parametros.do_ramo(schema).to_h do |grupo|
      [grupo['name'], grupo['properties'].to_h { |p| [p['name'], amostra(p)] }]
    end
  end

  def entrada(params, dados: {})
    described_class.new(produto: 'residencial', params: params, dados: dados, commission_percent: 10.0,
                        grupos_do_ramo: parametros.nomes_dos_grupos).to_h
  end

  it 'toda folha do formulário chega à entrada, no caminho em que o adapter a lê' do
    montada = entrada(params_completos)

    expect(parametros.caminhos.size).to eq(17)
    parametros.caminhos.each do |caminho|
      expect(montada.dig(*caminho.split('.'))).not_to be_nil, "#{caminho} declarado e não enviado"
    end
    expect(montada['commissionPercent']).to eq(10.0)
  end

  it 'o campo vence o dados quando os dois trazem o mesmo, e o dados completa o resto' do
    montada = entrada({ 'configuracoes' => { 'imovelUso' => 2, 'imovelNumero' => nil } },
                      dados: { 'configuracoes' => { 'imovelUso' => 1, 'imovelNumero' => '10' } })

    expect(montada['configuracoes']).to eq('imovelUso' => 2, 'imovelNumero' => '10')
  end

  it 'os atalhos comuns continuam valendo, e o bloco do segurado vence o atalho' do
    montada = entrada({ 'cpf' => '111', 'cep' => '01310-100',
                        'segurado' => { 'cpfCnpj' => '22233344455', 'nome' => 'Fulana' } })

    expect(montada['segurado']).to eq('cpfCnpj' => '22233344455', 'nome' => 'Fulana', 'cep' => '01310100')
  end

  it 'sem formulário, só o dados conta, como antes: grupo escrito fora dele não entra' do
    montada = described_class.new(produto: 'residencial', params: { 'configuracoes' => { 'imovelUso' => 2 } },
                                  dados: { 'configuracoes' => { 'imovelUso' => 1 } }, commission_percent: 10.0).to_h

    expect(montada['configuracoes']).to eq('imovelUso' => 1)
  end

  # A PONTA DA FERRAMENTA: os grupos vêm do schema que a conexão guarda, sem chamada ao adapter.
  describe 'na ferramenta de cotação' do
    let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
    let(:agent) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                       status: :active, enabled: true, instruction: 'Atenda.')
    end

    before do
      enable_test_encryption!
      Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                      .update!(status: 'ready', metadata: { 'quote_schemas' => { 'residencial' => schema } })
    end

    it 'leva à entrada toda folha do formulário que o modelo preencheu' do
      allow(Autonomia::Insurance::Connector).to receive(:client).and_raise('não deveria chamar o adapter')
      tool = Autonomia::Agents::Tools::Native::InsuranceQuote.new(agent: agent,
                                                                  params: params_completos.merge('produto' => 'residencial'))

      montada = tool.send(:quote_input).to_h

      parametros.caminhos.each do |caminho|
        expect(montada.dig(*caminho.split('.'))).not_to be_nil, "#{caminho} declarado e não enviado pela ferramenta"
      end
    end
  end
end
