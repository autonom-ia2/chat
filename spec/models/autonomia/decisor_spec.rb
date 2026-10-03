require 'rails_helper'

RSpec.describe Autonomia::Decisor do
  let(:account) { create(:account) }

  def decisor(**atributos)
    build(:autonomia_decisor, account: account, **atributos)
  end

  def respostas(quantas)
    Array.new(quantas) { |i| { chave: "r#{i}", descricao: "Resposta #{i}" } }
  end

  it 'aceita de 2 a 8 respostas com chave e descrição' do
    expect(decisor(respostas: respostas(2))).to be_valid
    expect(decisor(respostas: respostas(8))).to be_valid
    expect(decisor(respostas: respostas(1))).not_to be_valid
    expect(decisor(respostas: respostas(9))).not_to be_valid
  end

  it 'recusa chave repetida ou resposta sem descrição' do
    expect(decisor(respostas: [{ chave: 'sim', descricao: 'a' }, { chave: 'sim', descricao: 'b' }])).not_to be_valid
    expect(decisor(respostas: [{ chave: 'sim', descricao: 'a' }, { chave: 'nao', descricao: '' }])).not_to be_valid
  end

  it 'confere a certeza mínima entre 0,50 e 0,99' do
    expect(decisor(certeza_minima: 0.5)).to be_valid
    expect(decisor(certeza_minima: 0.99)).to be_valid
    expect(decisor(certeza_minima: 0.49)).not_to be_valid
    expect(decisor(certeza_minima: 1)).not_to be_valid
  end

  it 'nome é único por conta' do
    create(:autonomia_decisor, account: account, nome: 'É lead?')

    expect(decisor(nome: 'É lead?')).not_to be_valid
    expect(build(:autonomia_decisor, nome: 'É lead?')).to be_valid
  end

  it 'recusa exemplo com resposta fora da lista e mais de 30 exemplos' do
    fora = decisor(exemplos: [{ texto: 'oi', resposta: 'talvez', origem: 'pessoa' }])
    exemplos = Array.new(31) { { texto: 'oi', resposta: 'sim', origem: 'pessoa' } }

    expect(fora).not_to be_valid
    expect(decisor(exemplos: exemplos)).not_to be_valid
    expect(decisor(exemplos: exemplos.first(30))).to be_valid
  end

  it 'guarda exemplos novos e descarta os mais antigos acima de 30' do
    salvo = create(:autonomia_decisor, account: account,
                                       exemplos: Array.new(30) { |i| { texto: "antigo #{i}", resposta: 'nao', origem: 'pessoa' } })

    salvo.guardar_exemplo!(texto: 'quero cotar meu carro', resposta: 'sim', origem: 'guia', decisao_id: 9)

    expect(salvo.reload.exemplos.size).to eq(30)
    expect(salvo.exemplos.first['texto']).to eq('antigo 1')
    expect(salvo.exemplos.last).to include('texto' => 'quero cotar meu carro', 'resposta' => 'sim', 'origem' => 'guia', 'decisao_id' => 9)
  end

  describe 'campos' do
    it 'aceita os destinos da lista fechada' do
      campos = Autonomia::Decisor::DESTINOS.each_with_index.map { |destino, i| { chave: "c#{i}", descricao: 'x', destino: destino } }

      expect(decisor(campos: campos)).to be_valid
    end

    it 'aceita atributo personalizado de contato que existe e recusa o que não existe' do
      create(:custom_attribute_definition, account: account, attribute_key: 'produto', attribute_model: 'contact_attribute')

      expect(decisor(campos: [{ chave: 'produto', descricao: 'x', destino: 'contato.atributo:produto' }])).to be_valid
      invalido = decisor(campos: [{ chave: 'produto', descricao: 'x', destino: 'contato.atributo:inexistente' }])
      expect(invalido).not_to be_valid
      expect(invalido.errors[:campos].join).to include('contato.atributo:produto')
    end

    it 'recusa destino fora da lista, mostrando os aceitos' do
      invalido = decisor(campos: [{ chave: 'cpf', descricao: 'x', destino: 'contato.cpf' }])

      expect(invalido).not_to be_valid
      expect(invalido.errors[:campos].join).to include('contato.cpf', 'contato.telefone')
    end
  end
end
