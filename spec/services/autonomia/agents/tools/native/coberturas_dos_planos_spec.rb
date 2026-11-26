require 'rails_helper'

# #3249: a Bia responde o valor das coberturas antes da cotação, pelo catálogo da Universal. Fixtures reduzidas das
# respostas reais (sem dado pessoal).
RSpec.describe Autonomia::Agents::Tools::Native::CoberturasDosPlanos do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => { 'modelo' => 'seguro_viagem_universal' } })
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil) }
  let(:falhas) { Autonomia::Agents::Tools::Native::SeguroViagem::Falhas }

  before do
    enable_test_encryption!
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok')
  end

  def catalogo(nacional: false, status: 200, corpo: nil)
    arquivo = nacional ? 'beneficios_nacional.json' : 'beneficios_internacional.json'
    stub_request(:get, "#{base}/v1/beneficios")
      .with(query: { 'idioma' => 'portugues', 'tipoTarifa' => '1', 'nacional' => nacional.to_s })
      .to_return(status: status, body: corpo || file_fixture("../universal/#{arquivo}").read)
  end

  def consultar(argumentos, entrega: delivery)
    described_class.new(agent: contratado, params: argumentos, delivery: entrega).call
  end

  def planos(argumentos)
    JSON.parse(consultar(argumentos))['planos']
  end

  it 'só lê' do
    expect(described_class.escreve?).to be(false)
  end

  it '"Master" casa "Master USA +" e devolve as coberturas com o valor como veio, sem preço' do
    catalogo
    saida = JSON.parse(consultar({ 'planos' => ['Master'], 'nacional' => false }))
    expect(saida['catalogo']).to eq('internacional')
    expect(saida['planos']).to eq([{ 'plano' => 'Master USA +', 'coberturas' => [
                                    { 'nome' => 'Despesas Médicas e Hospitalares (por evento)', 'valor' => '$40.000' },
                                    { 'nome' => 'Perda de Bagagem', 'valor' => '$1.300' },
                                    { 'nome' => 'Cancelamento de viagem - plus reason', 'valor' => '$500' },
                                    { 'nome' => 'Concierge', 'valor' => 'SIM' }
                                  ] }])
    expect(saida['aviso']).to include('dólar', 'Master +')
    expect(saida.to_json).not_to include('preco', 'idProduto')
  end

  it '"Value +" e "Exclusive USA +" casam pelo nome normalizado; o TAB do catálogo sai do nome' do
    catalogo
    expect(planos('planos' => ['Value +', 'exclusive usa +'], 'nacional' => false).pluck('plano'))
      .to eq(['Value USA +', 'Exclusive USA +'])
  end

  it 'prefixo de palavra inteira quando nenhum nome é igual' do
    catalogo
    expect(planos('planos' => ['Anual Multiviagens'], 'nacional' => false).pluck('plano'))
      .to eq(['Anual Multiviagens UA 150(30 Dias)'])
  end

  it 'nacional: lê o catálogo nacional; igualdade vale antes do prefixo ("Nacional" não traz o Premium)' do
    catalogo(nacional: true)
    saida = JSON.parse(consultar({ 'planos' => ['Nacional'], 'nacional' => true }))
    expect(saida['catalogo']).to eq('nacional')
    expect(saida['planos'].pluck('plano')).to eq(['Nacional +'])
    expect(saida['planos'].first['coberturas'].first)
      .to eq('nome' => 'Despesas Médicas e Hospitalares (por evento)', 'valor' => 'R$ 100.000')
    expect(saida['aviso']).not_to include('dólar')
  end

  it 'nacional como o texto "true" também vale' do
    stub = catalogo(nacional: true)
    consultar({ 'planos' => ['Nacional Premium'], 'nacional' => 'true' })
    expect(stub).to have_been_requested
  end

  it 'lista vazia: todos os planos do catálogo' do
    catalogo
    expect(planos('planos' => [], 'nacional' => false).size).to eq(4)
  end

  it 'nome que o catálogo não tem: recusa com os nomes que existem, e registra' do
    catalogo
    allow(Autonomia::Agents::Tools::Recusa).to receive(:registrar).and_call_original
    texto = consultar({ 'planos' => %w[Master Platinum], 'nacional' => false })
    expect(texto).to include('Platinum', 'Master USA +', 'Value USA +', 'Exclusive USA +')
    expect(texto).not_to include("\t")
    expect(Autonomia::Agents::Tools::Recusa).to have_received(:registrar)
      .with('plano_fora_do_catalogo', hash_including(slug: 'coberturas_dos_planos', faltando: ['planos']))
  end

  # Sem `nacional`, os dois catálogos são lidos (cada um com o seu cache); o primeiro que tem o nome responde.
  context 'without nacional (o nome do plano diz o catálogo)' do
    it '"Master" acha no internacional, e o catálogo nacional também é lido' do
      internacional = catalogo
      nacional = catalogo(nacional: true)
      saida = JSON.parse(consultar({ 'planos' => ['Master'], 'nacional' => nil }))
      expect(saida['catalogo']).to eq('internacional')
      expect(saida['planos'].pluck('plano')).to eq(['Master USA +'])
      expect(saida['aviso']).to include('dólar')
      expect(internacional).to have_been_requested
      expect(nacional).not_to have_been_requested
    end

    it '"Nacional +" acha no nacional; o campo ausente vale o mesmo que nil' do
      catalogo
      catalogo(nacional: true)
      saida = JSON.parse(consultar({ 'planos' => ['Nacional +'] }))
      expect(saida['catalogo']).to eq('nacional')
      expect(saida['planos'].pluck('plano')).to eq(['Nacional +'])
      expect(saida['aviso']).not_to include('dólar')
    end

    it 'um nome em cada catálogo: devolve os dois, cada plano com o seu catálogo' do
      catalogo
      catalogo(nacional: true)
      saida = JSON.parse(consultar({ 'planos' => ['Master', 'Nacional +'] }))
      expect(saida['catalogo']).to eq('internacional e nacional')
      expect(saida['planos'].map { |plano| plano.values_at('plano', 'catalogo') })
        .to eq([['Master USA +', 'internacional'], ['Nacional +', 'nacional']])
    end

    it 'nome que nenhum dos dois tem: recusa com os nomes de ambos' do
      catalogo
      catalogo(nacional: true)
      texto = consultar({ 'planos' => ['Platinum'] })
      expect(texto).to include('Platinum', 'Master USA +', 'Nacional +')
    end

    it 'um catálogo fora e o outro acha: devolve o que achou, com o aviso do que ficou de fora' do
      catalogo(status: 500, corpo: '')
      catalogo(nacional: true)
      saida = JSON.parse(consultar({ 'planos' => ['Nacional +'] }))
      expect(saida['planos'].pluck('plano')).to eq(['Nacional +'])
      expect(saida['aviso']).to include('internacional fora do ar')
    end

    it 'um catálogo fora e nada achado no outro: trata a falha, sem dizer que o plano não existe' do
      catalogo(status: 500, corpo: '')
      catalogo(nacional: true)
      expect(consultar({ 'planos' => ['Master'] })).to eq(falhas::TEXTO_INDISPONIVEL)
    end

    it 'os dois fora: texto de indisponível, sem levantar' do
      catalogo(status: 500, corpo: '')
      catalogo(nacional: true, status: 500, corpo: '')
      expect(consultar({ 'planos' => ['Master'] })).to eq(falhas::TEXTO_INDISPONIVEL)
    end

    it 'lista vazia: os planos dos dois catálogos' do
      catalogo
      catalogo(nacional: true)
      saida = JSON.parse(consultar({ 'planos' => [] }))
      expect(saida['planos'].pluck('catalogo').uniq).to eq(%w[internacional nacional])
    end

    it 'nacional explícito lê só aquele catálogo' do
      catalogo
      nacional = catalogo(nacional: true)
      consultar({ 'planos' => ['Master'], 'nacional' => false })
      expect(nacional).not_to have_been_requested
    end
  end

  it 'schema: nacional é opcional (tipo aceita null) e continua listado em required' do
    esquema = described_class.openai_schema[:parameters]
    expect(esquema[:properties]['nacional']['type']).to eq(%w[boolean null])
    expect(esquema[:required]).to include('nacional')
  end

  it 'Universal fora: devolve o texto de indisponível, sem levantar' do
    catalogo(status: 500, corpo: '')
    expect(consultar({ 'planos' => ['Master'], 'nacional' => false })).to eq(falhas::TEXTO_INDISPONIVEL)
  end

  it 'pedido inválido da Universal vira indisponível: não há dado do cliente a corrigir' do
    catalogo(status: 400, corpo: { 'message' => 'Parâmetro inválido' }.to_json)
    expect(consultar({ 'planos' => ['Master'], 'nacional' => false })).to eq(falhas::TEXTO_INDISPONIVEL)
  end

  it 'login recusado: manda passar para a equipe, como nas outras ferramentas' do
    catalogo(status: 401, corpo: '')
    expect(consultar({ 'planos' => ['Master'], 'nacional' => false })).to eq(falhas::TEXTO_PASSAR)
    expect(contratado.acesso_da_seguradora.reload.estado).to eq('recusado')
  end

  it 'funciona sem conversa (Testar, playground): o catálogo é o mesmo para todas' do
    catalogo
    expect(JSON.parse(consultar({ 'planos' => ['Master'], 'nacional' => false }, entrega: nil))['planos'].size).to eq(1)
  end
end
