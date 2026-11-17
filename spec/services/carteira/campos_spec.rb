require 'rails_helper'

# E8.1 (#3043): o que a história guarda de cada campo da gaveta, e como quem desfaz lê de volta. Dados fictícios.
RSpec.describe Carteira::Campos do
  describe '.mudanca' do
    it 'guarda o antes e o depois dos campos comuns, a placa e a classe de bônus inclusive' do
      expect([described_class.mudanca('valor', 100, 200), described_class.mudanca('placa', nil, 'EXM0A00'),
              described_class.mudanca('bonus', 4, 5)])
        .to eq([{ campo: 'valor', antes: 100, depois: 200 }, { campo: 'placa', antes: nil, depois: 'EXM0A00' },
                { campo: 'bonus', antes: 4, depois: 5 }])
    end

    it 'do nascimento, do sexo e do CEP guarda só se antes estava vazio, nunca um valor' do
      mudancas = [described_class.mudanca('nascimento', nil, '1985-03-15'), described_class.mudanca('sexo', 'F', 'M'),
                  described_class.mudanca('cep', '01001000', nil)]

      expect(mudancas).to eq([{ campo: 'nascimento', antes_vazio: true }, { campo: 'sexo', antes_vazio: false },
                              { campo: 'cep', antes_vazio: false }])
      expect(mudancas.to_json).not_to include('1985-03-15', '01001000')
    end
  end

  describe '.desfeito' do
    it 'o campo comum volta ao de antes só quando ainda está como a mudança deixou' do
      mudanca = { 'campo' => 'placa', 'antes' => 'EXM0A00', 'depois' => 'EXM1B11' }

      expect([described_class.desfeito(mudanca, 'EXM1B11'), described_class.desfeito(mudanca, 'EXM2C22')])
        .to eq([[true, 'EXM0A00'], [false, 'EXM0A00']])
    end

    it 'o dado pessoal volta a vazio quando estava vazio antes e hoje tem valor; nos outros casos não volta' do
      era_vazio = { 'campo' => 'nascimento', 'antes_vazio' => true }
      tinha_valor = { 'campo' => 'cep', 'antes_vazio' => false }

      expect(described_class.desfeito(era_vazio, '1985-03-15')).to eq([true, nil])
      expect([described_class.desfeito(era_vazio, nil), described_class.desfeito(tinha_valor, '12345678'),
              described_class.desfeito({ 'campo' => 'sexo' }, 'F')].map(&:first)).to all(be(false))
    end
  end
end
