require 'rails_helper'

# E8.1 (#3043): os dados do segurado da cotação só passam quando estão escritos nas páginas, como os outros campos.
# Dados fictícios.
RSpec.describe Carteira::Leitor::Ancora do
  subject(:ancora) { described_class.new([pagina.new(numero: 1, texto: primeira), pagina.new(numero: 2, texto: segunda)]) }

  let(:pagina) { Carteira::Leitor::Paginas::Pagina }
  let(:primeira) do
    <<~TEXTO
      DADOS DO SEGURADO   Nome: Marina Exemplo   CPF: 123.456.789-00
      Data de nascimento: 15/03/85   Sexo: Feminino
      Endereço: Rua das Amostras, 100 - CEP 12345-678
      CONDUTOR PRINCIPAL   Nascimento: 02/07/1990   Sexo: Masculino   Filho nascido em 10/10/05
      VEÍCULO: Modelo Exemplo   Placa: EXM-0A00   Placa do reboque: AB12
      Classe de bônus: 5   Bônus: 10% de desconto
    TEXTO
  end
  let(:segunda) do
    <<~TEXTO
      CORRETOR: Corretora Amostra - CEP 98765-432
      Protocolo 123456789 e código 1234567
    TEXTO
  end

  before { travel_to(Time.zone.local(2026, 11, 17, 12)) }

  describe 'nascimento' do
    it 'confere a data escrita com o ano inteiro, como AAAA-MM-DD' do
      expect(ancora.data_de_nascimento('1990-07-02')).to eq('1990-07-02')
    end

    it 'o ano com dois dígitos é do século passado quando passa do ano de hoje, e deste quando não passa' do
      expect(ancora.data_de_nascimento('1985-03-15')).to eq('1985-03-15')
      expect(ancora.data_de_nascimento('2005-10-10')).to eq('2005-10-10')
      expect([ancora.data_de_nascimento('2085-03-15'), ancora.data_de_nascimento('1905-10-10')]).to eq([nil, nil])
    end

    it 'recusa a data que não está escrita, a do futuro, a que não existe e o que não é data' do
      recusados = ['1985-03-16', '2027-01-01', '1985-02-30', '15/03/85', '', nil, 19_850_315]

      expect(recusados.map { |valor| ancora.data_de_nascimento(valor) }).to all(be_nil)
    end
  end

  describe 'CEP' do
    it 'os 8 dígitos num bloco inteiro de número, e sai só com os dígitos' do
      expect([ancora.cep('12345-678'), ancora.cep('12345678'), ancora.cep('98765-432')]).to eq(%w[12345678 12345678 98765432])
    end

    it 'recusa o que não está escrito, o pedaço de um número maior e o que não tem 8 dígitos' do
      recusados = ['12345-679', '23456789', '1234567', '12345-6789', '', nil]

      expect(recusados.map { |valor| ancora.cep(valor) }).to all(be_nil)
    end
  end

  describe 'placa' do
    it 'confere o bloco inteiro e sai em maiúsculas, sem traço nem espaço' do
      expect([ancora.placa('EXM-0A00'), ancora.placa('exm-0a00')]).to eq(%w[EXM0A00 EXM0A00])
    end

    it 'recusa o que não está escrito como bloco e o que não tem a forma de placa' do
      recusados = %w[EXM0A00 EXM-0A01 AB12 1234567] + ['', nil]

      expect(recusados.map { |valor| ancora.placa(valor) }).to all(be_nil)
    end
  end

  describe 'sexo' do
    it 'vale quando a palavra de onde o modelo o tirou está escrita' do
      expect([ancora.sexo('F', 'Feminino'), ancora.sexo('M', 'Masculino')]).to eq(%w[F M])
    end

    it 'sem a palavra, com palavra que não está escrita ou fora de F e M: não achei' do
      recusados = [%w[F] + [nil], %w[F Mulher], %w[X Feminino], [nil, 'Feminino'], %w[f Feminino]]

      expect(recusados.map { |valor, palavra| ancora.sexo(valor, palavra) }).to all(be_nil)
    end
  end

  describe 'classe de bônus' do
    it 'vale quando o trecho está escrito e o número é uma das palavras dele' do
      expect(ancora.bonus(5, 'Classe de bônus: 5')).to eq(5)
    end

    it 'o número fora do trecho, o trecho que não está escrito e a classe fora de 0 a 10: não achei' do
      recusados = [[6, 'Classe de bônus: 5'], [5, 'Classe de bônus 5 com desconto'], [5, nil], [20, 'Bônus: 10% de desconto'],
                   [-1, 'Classe de bônus: 5'], ['5', 'Classe de bônus: 5'], [nil, 'Classe de bônus: 5']]

      expect(recusados.map { |classe, trecho| ancora.bonus(classe, trecho) }).to all(be_nil)
    end

    # O limite que fica: a âncora não sabe que o 10 do percentual não é a classe. Quem mede é a bateria com gabarito.
    it 'o percentual ao lado também está escrito, e a âncora deixa passar' do
      expect(ancora.bonus(10, 'Bônus: 10% de desconto')).to eq(10)
    end
  end
end
