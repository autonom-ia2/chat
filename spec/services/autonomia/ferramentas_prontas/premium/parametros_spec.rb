require 'rails_helper'

# #2858 (F7): os parâmetros dos cards Premium normalizam antes de qualquer gasto. O que não normaliza é pedido inválido,
# e a BigDataCorp não é chamada.
RSpec.describe Autonomia::FerramentasProntas::Premium::Parametros do
  it 'placa antiga e Mercosul, com ou sem traço; o resto não serve' do
    expect(described_class::PLACA.normalizar('abc-1234')).to eq('ABC1234')
    expect(described_class::PLACA.normalizar('ABC1D23')).to eq('ABC1D23')
    expect(described_class::PLACA.normalizar('AB12345')).to be_nil
    expect(described_class::PLACA.normalizar('ABC12345')).to be_nil
    expect(described_class::PLACA.normalizar('ABCD123')).to be_nil
  end

  it 'CPF só com dígito verificador certo' do
    expect(described_class::CPF.normalizar('111.444.777-35')).to eq('11144477735')
    expect(described_class::CPF.normalizar('111.444.777-36')).to be_nil
    expect(described_class::CPF.normalizar('11111111111')).to be_nil
  end

  it 'CNPJ não aceita um CPF' do
    expect(described_class::CNPJ.normalizar('11.222.333/0001-81')).to eq('11222333000181')
    expect(described_class::CNPJ.normalizar('111.444.777-35')).to be_nil
  end

  it 'número do imóvel só com dígitos' do
    expect(described_class::NUMERO.normalizar('123')).to eq('123')
    expect(described_class::NUMERO.normalizar('s/n')).to be_nil
    expect(described_class::NUMERO.normalizar('12 apto 3')).to be_nil
  end

  it 'código do CAR com estado do Brasil, município e 32 posições' do
    codigo = "MT-5107065-#{'EXEMPLO0' * 4}"
    expect(described_class::CODIGO_CAR.normalizar(codigo)).to eq("MT5107065#{'EXEMPLO0' * 4}")
    expect(described_class::CODIGO_CAR.normalizar("XX5107065#{'EXEMPLO0' * 4}")).to be_nil
    expect(described_class::CODIGO_CAR.normalizar('MT5107065')).to be_nil
  end

  # Regra "QI 70" (11/11): cada parâmetro diz o que o agente faz quando o valor falta ou não serve, pelo `deduza:` ou
  # `pergunte:` do `Parametro`, com o texto de `ORIENTACOES`.
  describe 'as orientações da QI 70' do
    let(:parametros) { described_class.constants.map { |nome| described_class.const_get(nome) }.grep(Autonomia::FerramentasProntas::Parametro) }
    let(:orientacoes) { described_class::ORIENTACOES }

    it 'todo parâmetro Premium tem uma orientação só, deduza ou pergunte, com texto' do
      expect(orientacoes.keys).to match_array(parametros.map(&:nome))
      orientacoes.each_value do |orientacao|
        expect(orientacao.keys).to contain_exactly(:deduza).or contain_exactly(:pergunte)
        expect(orientacao.values.first).to be_present
      end
    end

    it 'pergunta o que muda o resultado; deduz o CEP e a UF' do
      perguntados = orientacoes.select { |_nome, orientacao| orientacao.key?(:pergunte) }.keys

      expect(perguntados).to match_array(%w[cnpj cpf placa numero codigo_car cidade rua bairro])
      expect(orientacoes.select { |_nome, orientacao| orientacao.key?(:deduza) }.keys).to match_array(%w[cep uf])
    end

    it 'cada parâmetro recebe a sua orientação, no texto da recusa' do
      resposta = Autonomia::FerramentasProntas::Resposta
      parametros.each do |parametro|
        orientacao = orientacoes.fetch(parametro.nome)
        esperado = if orientacao[:deduza]
                     resposta.deduza(parametro.nome, orientacao[:deduza])
                   else
                     resposta.pergunte(parametro.nome, orientacao[:pergunte])
                   end
        expect(parametro.orientacao).to eq(esperado)
      end
    end

    it 'a UF é opcional e a mesma das grátis: aceita o nome do estado' do
      expect(described_class::UF.normalizar('Minas Gerais')).to eq('mg')
      expect(described_class::UF.normalizar('sp')).to eq('sp')
      expect(described_class::UF).to be_local
    end

    it 'o código do CAR diz onde achar: no recibo do CAR' do
      expect(orientacoes['codigo_car'][:pergunte]).to include('recibo do CAR')
    end
  end
end
