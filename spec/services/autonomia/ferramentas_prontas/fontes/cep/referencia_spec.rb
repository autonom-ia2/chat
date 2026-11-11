require 'rails_helper'

# #2858 — o "CEP de referência da cidade" (regra "QI 70"): para a fonte cujo dado é por cidade e que pede um CEP só para
# saber a cidade, a plataforma acha um CEP daquela cidade sozinha, sem perguntar ao cliente. Quem usa: a F7.
RSpec.describe Autonomia::FerramentasProntas::Fontes::Cep::Referencia do
  let(:uberlandia) { 'https://viacep.com.br/ws/MG/Uberlandia/Rua/json/' }
  let(:serra) { 'https://viacep.com.br/ws/MG/Serra%20da%20Saudade/Rua/json/' }

  before do
    resolver_hosts_das_prontas
    cache_em_memoria
  end

  def rua(cep, bairro, ibge: '3170206')
    { cep: cep, logradouro: 'Rua A', bairro: bairro, localidade: 'Uberlândia', uf: 'MG', ibge: ibge }
  end

  it 'cidade com CEP por rua: o menor CEP da propria cidade (conferido pelo codigo IBGE)' do
    fonte_responde(uberlandia, [rua('38410-776', 'Élisson Prieto'), rua('38400-263', 'Tabajaras'), rua('01001-000', 'Outra', ibge: '3550308')])

    expect(described_class.cep_da_cidade(cidade: 'Uberlândia')).to eq('38400-263')
  end

  it 'cidade de CEP unico: o CEP geral da cidade, que o ViaCEP devolve sem rua' do
    fonte_responde(serra, [{ cep: '35617-000', logradouro: '', bairro: '', localidade: 'Serra da Saudade', uf: 'MG', ibge: '3166600' }])

    expect(described_class.cep_da_cidade(cidade: 'Serra da Saudade', uf: 'mg')).to eq('35617-000')
  end

  it 'guarda por 30 dias: a segunda vez nao chama a fonte' do
    pedido = fonte_responde(uberlandia, [rua('38400-263', 'Tabajaras')])

    2.times { described_class.cep_da_cidade(cidade: 'Uberlândia') }

    expect(pedido).to have_been_requested.once
  end

  it 'cidade homonima sem UF, cidade que nao existe, fonte fora ou sem resposta: nil (quem chama decide)' do
    fonte_fora(uberlandia)

    expect(described_class.cep_da_cidade(cidade: 'Bom Jesus')).to be_nil
    expect(described_class.cep_da_cidade(cidade: 'Nao Existe')).to be_nil
    expect(described_class.cep_da_cidade(cidade: 'Uberlândia')).to be_nil
    expect(a_request(:get, /Bom|Nao/)).not_to have_been_made
  end

  it 'CEP especial (sufixo 900 a 999) fica de fora do menor, mesmo com prefixo menor; so vale se nao houver outro' do
    fonte_responde(uberlandia, [rua('38400-263', 'Tabajaras'), rua('38400-901', 'Centro'), rua('38100-950', 'Centro')])

    expect(described_class.cep_da_cidade(cidade: 'Uberlândia')).to eq('38400-263')
  end

  it 'so CEP especial na cidade: usa o especial' do
    fonte_responde(uberlandia, [rua('38400-901', 'Centro')])

    expect(described_class.cep_da_cidade(cidade: 'Uberlândia')).to eq('38400-901')
  end

  it 'cache fora do ar (erro de conexao): consulta a fonte e loga a classe do erro' do
    fonte_responde(uberlandia, [rua('38400-263', 'Tabajaras')])
    allow(Rails.cache).to receive(:read).and_raise(Redis::CannotConnectError)
    allow(Rails.logger).to receive(:warn)

    expect(described_class.cep_da_cidade(cidade: 'Uberlândia')).to eq('38400-263')
    expect(Rails.logger).to have_received(:warn).with(include('Redis::CannotConnectError')).at_least(:once)
  end

  describe '.cep (o que a F7 chama em Premium::Endereco.cep)' do
    let(:paulista) { 'https://viacep.com.br/ws/SP/Sao%20Paulo/Avenida%20Paulista/json/' }
    let(:de_sp) { { logradouro: 'Avenida Paulista', localidade: 'São Paulo', uf: 'SP', ibge: '3550308' } }

    it 'sem rua: o CEP de referencia da cidade' do
      fonte_responde(uberlandia, [rua('38400-263', 'Tabajaras')])

      expect(described_class.cep(cidade: 'Uberlândia', uf: 'MG')).to eq('cep' => '38400-263')
    end

    it 'com a rua: um CEP so vira cep; varios viram candidatos, o da rua antes do especial; o bairro filtra' do
      fonte_responde(paulista, [de_sp.merge(cep: '01311-921', complemento: '1159', bairro: 'Bela Vista'),
                                de_sp.merge(cep: '01310-100', complemento: 'de 1 a 609 - lado ímpar', bairro: 'Bela Vista'),
                                de_sp.merge(cep: '01311-000', complemento: 'de 611 a 1045', bairro: 'Cerqueira César')])

      candidatos = described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Avenida Paulista')['candidatos']

      expect(candidatos.pluck('cep')).to eq(%w[01310-100 01311-000 01311-921])
      expect(candidatos.first).to include('bairro' => 'Bela Vista', 'complemento' => 'de 1 a 609 - lado ímpar')
      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Avenida Paulista', bairro: 'cerqueira')).to eq('cep' => '01311-000')
    end

    it 'bairro que esvazia a lista ("Jardim America" contra "Jd America"): os candidatos da rua, sem o filtro' do
      fonte_responde(paulista, [de_sp.merge(cep: '01310-100', bairro: 'Jd America'), de_sp.merge(cep: '01311-000', bairro: 'Bela Vista')])

      resultado = described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Avenida Paulista', bairro: 'Jardim America')

      expect(resultado['candidatos'].pluck('cep')).to eq(%w[01310-100 01311-000])
    end

    it 'a busca pela rua guarda a lista inteira por 30 dias: a segunda nao chama a fonte' do
      pedido = fonte_responde(paulista, [de_sp.merge(cep: '01310-100', bairro: 'Bela Vista')])

      2.times { described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Avenida Paulista') }

      expect(pedido).to have_been_requested.once
    end

    it 'fonte fora: nil, sem guardar (a próxima tenta de novo)' do
      fonte_fora(paulista)

      2.times { expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Avenida Paulista')).to be_nil }
      expect(a_request(:get, paulista)).to have_been_made.twice
    end

    it 'rua que nao existe, cidade que nao existe ou fonte fora: nil' do
      fonte_responde(paulista, [])

      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Avenida Paulista')).to be_nil
      expect(described_class.cep(cidade: 'Nao Existe', uf: 'SP', rua: 'Rua A')).to be_nil
    end
  end

  # C15c/C15d do testador: com o bairro já informado e mais de um CEP sobrando, pedia o bairro de novo, e o agente ficava
  # em laço. Dados reais do ViaCEP (11/11/2026).
  describe '.cep com o bairro e o número' do
    let(:augusta) { 'https://viacep.com.br/ws/SP/Sao%20Paulo/Rua%20Augusta/json/' }
    let(:sete_de_setembro) { 'https://viacep.com.br/ws/SP/Campinas/Rua%20Sete%20de%20Setembro/json/' }

    def real(nome)
      Rails.root.join('spec/fixtures/ferramentas_prontas', nome).read
    end

    before do
      fonte_responde(augusta, real('viacep_rua_augusta_sao_paulo.json'))
      fonte_responde(sete_de_setembro, real('viacep_rua_sete_de_setembro_campinas.json'))
    end

    it 'Rua Augusta, Consolação, nº 100: o número escolhe pela faixa ("até 698 - lado par")' do
      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua Augusta', bairro: 'Consolação', numero: '100'))
        .to eq('cep' => '01304-000')
      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua Augusta', bairro: 'Consolação', numero: '101'))
        .to eq('cep' => '01305-000')
    end

    it 'Rua Augusta, Consolação, sem o número: pede o NÚMERO, não o bairro de novo' do
      resultado = described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua Augusta', bairro: 'Consolação')

      expect(resultado['falta']).to eq('numero')
      expect(resultado['candidatos'].pluck('bairro').uniq).to eq(['Consolação'])
    end

    it 'Rua Augusta sem o bairro, em bairros diferentes: pede o bairro, mesmo com o número (outra Rua Augusta sem faixa pode ter o 100)' do
      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua Augusta')['falta']).to eq('bairro')
      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua Augusta', numero: '100')['falta']).to eq('bairro')
    end

    it 'Vila Industrial, sem número: o CEP da rua (13035-350) e não o especial do prédio (13035-901)' do
      expect(described_class.cep(cidade: 'Campinas', uf: 'SP', rua: 'Rua Sete de Setembro', bairro: 'Vila Industrial'))
        .to eq('cep' => '13035-350')
    end

    it 'Vila Industrial com um número que não é o do prédio: o CEP da rua; com o número do prédio, o CEP dele' do
      expect(described_class.cep(cidade: 'Campinas', uf: 'SP', rua: 'Rua Sete de Setembro', bairro: 'Vila Industrial', numero: '50'))
        .to eq('cep' => '13035-350')
      expect(described_class.cep(cidade: 'Campinas', uf: 'SP', rua: 'Rua Sete de Setembro', bairro: 'Vila Industrial', numero: '189'))
        .to eq('cep' => '13035-901')
    end

    # Revisor (lote 3, ALTO): com o número dito, pedir o número de novo era o mesmo laço. O CEP do prédio (complemento
    # igual ao número) vale mais que a faixa que também cobre o número.
    it 'Rua Augusta, Consolação, nº de prédio: o CEP do prédio, não a faixa que também cobre o número' do
      { '1260' => '01304-971', '129' => '01305-900', '1626' => '01304-902', '1029' => '01305-904', '257' => '01305-901',
        '1371' => '01305-902', '1600' => '01304-901', '1118' => '01304-900', '1611' => '01305-903' }.each do |numero, cep|
        resultado = described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua Augusta', bairro: 'Consolação', numero: numero)
        expect(resultado).to eq('cep' => cep), "nº #{numero}: #{resultado.inspect[0, 120]}"
      end
    end

    it 'Rua Augusta, Consolação, nº 1682 (nenhuma faixa da Consolação cobre): pede o bairro, com os candidatos' do
      resultado = described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua Augusta', bairro: 'Consolação', numero: '1682')

      expect(resultado['falta']).to eq('bairro')
      expect(resultado['candidatos']).to be_present
    end

    it 'com o número dito, nunca pede o número de novo' do
      %w[1 100 698 699 1260 1682 2438 2766 5000].product(['Consolação', 'Cerqueira César', nil]).each do |numero, bairro|
        resultado = described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua Augusta', bairro: bairro, numero: numero)
        expect(resultado['falta']).not_to eq('numero'), "nº #{numero}, bairro #{bairro.inspect}"
      end
    end

    it 'a escolha olha TODOS os CEPs da rua, não só os 10 que a consulta por_endereco mostra ao agente' do
      resultado = described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua Augusta', bairro: 'Consolação', numero: '1260')

      expect(resultado).to eq('cep' => '01304-971')
      expect(resultado.to_s).not_to include('01304-001')
    end

    it 'Rua Sete de Setembro sem o bairro, em Sousas e na Vila Industrial: pede o bairro' do
      resultado = described_class.cep(cidade: 'Campinas', uf: 'SP', rua: 'Rua Sete de Setembro')

      expect(resultado['falta']).to eq('bairro')
      expect(resultado['candidatos'].pluck('cep')).to contain_exactly('13106-022', '13035-350', '13035-901')
    end
  end
end
