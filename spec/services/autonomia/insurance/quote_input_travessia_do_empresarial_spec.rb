require 'rails_helper'

# TUDO O QUE O FORMULÁRIO DO EMPRESARIAL DECLARA É ENVIADO (R7 da auditoria de paridade, 25/09/2026). É o
# `quote_input_travessia_do_ramo_spec` de residencial feito para o ramo 18: cada folha do formulário, gerado do schema
# do adapter, recebe um valor, e a entrada montada tem de carregar todas, no caminho em que o adapter as lê
# (`segurado.*`, `configuracoes.*`, `renovacao.*`).
#
# O empresarial tem uma folha a mais que o residencial não tem: a atividade escolhida em cada seguradora. Ela não
# vem do schema do adapter (vive fora de `configuracoes`), entra no formulário pela ferramenta
# (`Declaracao::ATIVIDADES`) e vai no topo da entrada. Sem ela a seguradora não calcula, então ela também é
# conferida aqui.
RSpec.describe Autonomia::Insurance::QuoteInput do
  let(:schema) { Autonomia::Insurance::Connector::Mock::SCHEMA_EMPRESARIAL }
  let(:parametros) { Autonomia::Insurance::Parametros.new(schema, ramo: true) }
  let(:atividades) { [{ 'seguradora' => '8', 'key' => '484', 'value' => 'ESCRITORIOS DEMAIS-TERREO' }] }

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

  def entrada(params)
    described_class.new(produto: 'empresarial', params: params, dados: {}, commission_percent: 10.0,
                        grupos_do_ramo: parametros.nomes_dos_grupos).to_h
  end

  it 'toda folha do formulário chega à entrada, no caminho em que o adapter a lê' do
    montada = entrada(params_completos.merge('atividades' => atividades))

    # O CPF ou CNPJ do segurado (o nome vem do documento), os 6 do imóvel (com a construção ou reforma, 25/09/2026), as
    # 10 coberturas do cliente e os 5 da renovação.
    expect(parametros.caminhos.size).to eq(22)
    expect(parametros.caminhos).to include('configuracoes.imovelConstrucaoReforma')
    parametros.caminhos.each do |caminho|
      expect(montada.dig(*caminho.split('.'))).not_to be_nil, "#{caminho} declarado e não enviado"
    end
    expect(montada['atividades']).to eq(atividades)
    expect(montada['commissionPercent']).to eq(10.0)
  end

  it 'a construção ou reforma que o cliente diz chega como ele disse, sim ou não' do
    [true, false].each do |valor|
      montada = entrada({ 'configuracoes' => { 'imovelConstrucaoReforma' => valor } })

      expect(montada.dig('configuracoes', 'imovelConstrucaoReforma')).to be(valor)
    end
  end

  it 'a construção ou reforma nula não vai: vale o padrão do adapter' do
    montada = entrada({ 'configuracoes' => { 'imovelConstrucaoReforma' => nil, 'imovelNumero' => '1540' } })

    expect(montada['configuracoes']).to eq('imovelNumero' => '1540')
  end

  # A PONTA DA FERRAMENTA: os grupos vêm do schema que a conexão guarda, sem chamada ao adapter, e a atividade vem da
  # lista que a ferramenta soma ao formulário do empresarial.
  describe 'na ferramenta de cotação' do
    let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
    let(:agent) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                       status: :active, enabled: true, instruction: 'Atenda.')
    end

    before do
      enable_test_encryption!
      Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                      .update!(status: 'ready',
                                               metadata: { 'quote_schemas' => { 'empresarial' => schema } })
    end

    # Que o formulário do especialista declara a lista de atividades é o `insurance_quote_formulario_empresarial_spec`.
    it 'leva à entrada toda folha do formulário que o modelo preencheu, e a atividade' do
      allow(Autonomia::Insurance::Connector).to receive(:client).and_raise('não deveria chamar o adapter')
      params = params_completos.merge('produto' => 'empresarial', 'atividades' => atividades)
      tool = Autonomia::Agents::Tools::Native::InsuranceQuote.new(agent: agent, params: params)

      montada = tool.send(:quote_input).to_h

      parametros.caminhos.each do |caminho|
        expect(montada.dig(*caminho.split('.'))).not_to be_nil, "#{caminho} declarado e não enviado pela ferramenta"
      end
      expect(montada['atividades']).to eq(atividades)
    end
  end
end
