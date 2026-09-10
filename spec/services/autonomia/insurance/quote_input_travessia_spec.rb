require 'rails_helper'

# TUDO O QUE É DECLARADO É ENVIADO — entrega 2 do Agente de Cotação, termo 4.
#
# Este é o defeito de hoje, e o mais fácil de repetir: declarar um campo que a montagem da entrada
# não monta. Até 10/09/2026 o `dados` era declarado e ignorado em auto. Aqui cada folha do
# formulário gerado recebe um valor, e a entrada montada tem de carregar todas.
#
# PROVA POR MUTAÇÃO: tirar `coverage` de `GRUPOS_DE_AUTO` reprova "toda folha chega à entrada";
# trocar a ordem do merge (atalho vencendo o bloco) reprova "o bloco vence o atalho".
RSpec.describe Autonomia::Insurance::QuoteInput do
  let(:schema) { Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO }
  let(:parametros) { Autonomia::Insurance::Parametros.new(schema) }

  def amostra(tipo)
    { 'string' => 'x', 'number' => 1, 'boolean' => true, 'array' => ['x'] }.fetch(tipo)
  end

  # O formulário inteiro preenchido: cada folha com um valor do tipo dela.
  def params_completos
    parametros.grupos.to_h do |grupo|
      [grupo['name'], grupo['properties'].to_h { |p| [p['name'], amostra(p['type'])] }]
    end
  end

  def entrada(params)
    described_class.new(produto: 'auto', params: params, dados: {}, commission_percent: 10.0).to_h
  end

  it 'toda folha do formulário chega à entrada, no caminho em que o adapter a lê' do
    montada = entrada(params_completos)

    parametros.caminhos.each do |caminho|
      expect(montada.dig(*caminho.split('.'))).not_to be_nil, "#{caminho} declarado e não enviado"
    end
    expect(montada['commissionPercent']).to eq(10.0)
  end

  it 'nil e vazio saem; false e zero ficam, porque são resposta' do
    montada = entrada('vehicle' => { 'plate' => 'ABC1D23', 'youngDriver' => false, 'gasKitValue' => 0,
                                     'chassis' => nil, 'fipeCode' => '' })

    expect(montada['vehicle']).to eq('plate' => 'ABC1D23', 'youngDriver' => false, 'gasKitValue' => 0)
  end

  it 'os atalhos comuns (cpf, nome, cep, numero) alimentam segurado e endereço' do
    montada = entrada('cpf' => '042.979.126-78', 'nome' => 'Fulano', 'cep' => '31110-210', 'numero' => '10',
                      'vehicle' => { 'plate' => 'ABC1D23' })

    expect(montada['insured']).to eq('document' => '04297912678', 'name' => 'Fulano')
    expect(montada['address']).to eq('zipCode' => '31110210', 'number' => '10')
  end

  it 'o bloco vence o atalho quando os dois vêm' do
    montada = entrada('cpf' => '111', 'insured' => { 'document' => '22233344455' }, 'vehicle' => { 'plate' => 'ABC1D23' })

    expect(montada['insured']['document']).to eq('22233344455')
  end

  it 'grupo que não veio não aparece: o adapter usa os padrões dele' do
    montada = entrada('vehicle' => { 'plate' => 'ABC1D23' })

    expect(montada.keys).to match_array(%w[vehicle commissionPercent])
  end
end
