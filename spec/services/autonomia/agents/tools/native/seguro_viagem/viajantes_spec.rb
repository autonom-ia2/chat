require 'rails_helper'

# Dados fictícios: os CPFs têm dígito verificador válido e não são de ninguém conhecido.
RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::Viajantes do
  let(:titular) do
    { 'nome_completo' => '  Fulano   de Teste ', 'cpf' => '529.982.247-25', 'data_nascimento' => '1981-03-15',
      'email' => 'fulano@exemplo.test', 'telefone' => '(11) 98765-4321', 'cep' => '01310-100', 'numero' => '1000',
      'complemento' => nil }
  end
  let(:outro) { { 'nome_completo' => 'Ciclana de Teste', 'cpf' => '111.444.777-35', 'data_nascimento' => '2014-07-01' } }

  before { travel_to Time.utc(2026, 11, 24, 15, 0, 0) }

  it 'devolve os dados limpos, o titular primeiro' do
    viajantes, falta = described_class.conferir(titular: titular, demais: [outro])
    expect(falta).to be_nil
    expect(viajantes.first)
      .to eq('nome_completo' => 'Fulano de Teste', 'cpf' => '52998224725', 'nascimento' => Date.new(1981, 3, 15),
             'email' => 'fulano@exemplo.test', 'telefone' => '11987654321', 'cep' => '01310100', 'numero' => '1000',
             'complemento' => nil)
    expect(viajantes.second).to eq('nome_completo' => 'Ciclana de Teste', 'cpf' => '11144477735',
                                   'nascimento' => Date.new(2014, 7, 1))
  end

  # 26/11: a proposta parou com o telefone do WhatsApp (+55, 13 dígitos); o cliente não precisa digitar o próprio número.
  it 'telefone com o DDI do Brasil perde o 55, e sem telefone aceito vale o do WhatsApp da conversa', :aggregate_failures do
    viajantes, = described_class.conferir(titular: titular.merge('telefone' => '+55 (11) 98765-4321'), demais: [])
    expect(viajantes.first['telefone']).to eq('11987654321')

    viajantes, = described_class.conferir(titular: titular.merge('telefone' => 'o WhatsApp desta conversa'), demais: [],
                                          telefone_da_conversa: '+5511912345678')
    expect(viajantes.first['telefone']).to eq('11912345678')

    viajantes, = described_class.conferir(titular: titular, demais: [], telefone_da_conversa: '+5511912345678')
    expect(viajantes.first['telefone']).to eq('11987654321')

    _, falta = described_class.conferir(titular: titular.merge('telefone' => nil), demais: [], telefone_da_conversa: nil)
    expect(falta.campo).to eq('titular.telefone')
  end

  it 'DDD 55 (RS) não perde o 55, número com erro não é trocado pelo da conversa', :aggregate_failures do
    expect(described_class.conferir(titular: titular.merge('telefone' => '55991234567'), demais: []).first.first['telefone'])
      .to eq('55991234567')
    expect(described_class.conferir(titular: titular.merge('telefone' => '+55 55 99123-4567'), demais: []).first.first['telefone'])
      .to eq('55991234567')
    _, falta = described_class.conferir(titular: titular.merge('telefone' => '987654321'), demais: [],
                                        telefone_da_conversa: '+5511912345678')
    expect(falta.campo).to eq('titular.telefone')
  end

  it 'CPF com 10 dígitos é falta do CPF, sem levantar (R17)' do
    viajantes, falta = described_class.conferir(titular: titular.merge('cpf' => '5299822472'), demais: [])
    expect(viajantes).to be_nil
    expect(falta.campo).to eq('titular.cpf')
  end

  it 'CPF com dígito verificador errado é falta do CPF' do
    _, falta = described_class.conferir(titular: titular, demais: [outro.merge('cpf' => '11144477736')])
    expect(falta.campo).to eq('demais_viajantes.cpf')
  end

  it 'CPF repetido entre titular e demais é falta' do
    _, falta = described_class.conferir(titular: titular, demais: [outro.merge('cpf' => '52998224725')])
    expect(falta.campo).to eq('demais_viajantes.cpf')
  end

  it 'e-mail sem ponto depois do @ é falta do e-mail' do
    _, falta = described_class.conferir(titular: titular.merge('email' => 'fulano@exemplo'), demais: [])
    expect(falta.campo).to eq('titular.email')
  end

  it 'nome sem sobrenome, nascimento fora do formato ou no futuro, telefone, CEP e número' do
    casos = {
      { 'nome_completo' => 'Fulano' } => 'titular.nome_completo',
      { 'data_nascimento' => '15/03/1981' } => 'titular.data_nascimento',
      { 'data_nascimento' => '2030-01-01' } => 'titular.data_nascimento',
      { 'telefone' => '98765-4321' } => 'titular.telefone',
      { 'cep' => '0131010' } => 'titular.cep',
      { 'numero' => ' ' } => 'titular.numero'
    }
    casos.each do |troca, campo|
      _, falta = described_class.conferir(titular: titular.merge(troca), demais: [])
      expect(falta&.campo).to eq(campo), "#{troca.inspect} devia faltar #{campo}"
    end
  end

  it 'a falta não repete o valor recebido' do
    _, falta = described_class.conferir(titular: titular.merge('cpf' => '52998224726'), demais: [])
    expect(falta.texto).not_to include('52998224726')
  end

  it 'titular e demais fora do formato não levantam' do
    expect(described_class.conferir(titular: 'texto', demais: 'texto').last.campo).to eq('titular.nome_completo')
  end

  it 'contato de emergência: nome e telefone com DDD' do
    expect(described_class.contato('nome' => 'Beltrana de Teste', 'telefone' => '(11) 91234-5678'))
      .to eq([{ 'nome' => 'Beltrana de Teste', 'telefone' => '11912345678' }, nil])
    expect(described_class.contato('nome' => 'Beltrana', 'telefone' => '1234').last.campo)
      .to eq('contato_de_emergencia.telefone')
    expect(described_class.contato(nil).last.campo).to eq('contato_de_emergencia.nome')
  end
end
