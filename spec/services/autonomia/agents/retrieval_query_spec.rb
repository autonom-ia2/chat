require 'rails_helper'

RSpec.describe Autonomia::Agents::RetrievalQuery do
  let(:subject_question) { 'Qual o valor da analise codigo 2468 para 125 amostras?' }
  let(:history) do
    [{ role: 'user', content: subject_question }, { role: 'assistant', content: 'O valor e R$ 42 por amostra.' }]
  end

  it 'preserves the service when the customer changes the quantity in a sentence' do
    query = 'Vou fazer só de 10.'

    expect(described_class.new(query: query, history: history).call).to eq("#{query}\n#{subject_question}")
  end

  it 'works for another segment without importing the previous assistant price' do
    turns = [{ role: 'user', content: 'Qual o valor do plano Equipe para 15 usuarios?' },
             { role: 'assistant', content: 'Custa R$ 80 por usuario.' }]

    result = described_class.new(query: 'Na verdade, serão só 2 usuários.', history: turns).call

    expect(result).to eq("Na verdade, serão só 2 usuários.\nQual o valor do plano Equipe para 15 usuarios?")
    expect(result).not_to include('R$ 80')
  end

  it 'supports an English quantity correction' do
    turns = [{ role: 'user', content: 'How much for 15 licenses of Team?' },
             { role: 'assistant', content: 'Each license is $80.' }]

    expect(described_class.new(query: 'Actually, make it just 3 licenses.', history: turns).call)
      .to eq("Actually, make it just 3 licenses.\nHow much for 15 licenses of Team?")
  end

  it 'keeps the bare-number reply after a quantity question working' do
    turns = [{ role: 'user', content: 'Quanto custa a assinatura Equipe?' },
             { role: 'assistant', content: 'Quantos usuarios voce precisa?' }]

    expect(described_class.new(query: '2', history: turns).call)
      .to eq("2\nQuanto custa a assinatura Equipe?\nQuantos usuarios voce precisa?")
  end

  it 'can use a quantity question as a search hint without a previous user turn' do
    turns = [{ role: 'assistant', content: 'How many licenses of Team do you need?' }]

    expect(described_class.new(query: '3', history: turns).call).to eq("3\nHow many licenses of Team do you need?")
  end

  it 'retains the original subject through repeated corrections and split assistant replies' do
    turns = history + [{ role: 'assistant', content: 'O prazo e 4 dias.' },
                       { role: 'user', content: 'Vou fazer só de 10.' },
                       { role: 'assistant', content: 'O total anterior era R$ 420.' }]

    expect(described_class.new(query: 'Na verdade, serão só 2 amostras.', history: turns).call)
      .to eq("Na verdade, serão só 2 amostras.\n#{subject_question}")
  end

  it 'uses the latest customer subject rather than an older topic' do
    turns = history + [{ role: 'user', content: 'Quanto custa o plano Empresa para 20 usuarios?' },
                       { role: 'assistant', content: 'Vou consultar.' }]

    expect(described_class.new(query: 'Serão apenas 5 usuários.', history: turns).call)
      .to eq("Serão apenas 5 usuários.\nQuanto custa o plano Empresa para 20 usuarios?")
  end

  it 'does not change a standalone question, an unrelated number or a new topic' do
    ['Oi', '2', 'Qual o prazo de entrega?', 'Quero 2 pastilhas para outra moto.',
     'Meu telefone é 5511999999999', 'Na verdade, meu CEP é 12345678', 'Na verdade, quero 2,5 litros.'].each do |query|
      expect(described_class.new(query: query, history: history).call).to eq(query)
    end
  end

  it 'does not construct context without a subject or quantity question' do
    expect(described_class.new(query: 'Vou fazer só de 10.').call).to eq('Vou fazer só de 10.')
    expect(described_class.new(query: '2').call).to eq('2')
    expect(described_class.new(query: 'Serão apenas 5.', history: [{ role: 'assistant', content: 'Custa R$ 42.' }]).call)
      .to eq('Serão apenas 5.')
  end

  it 'does not look beyond the bounded history window' do
    turns = history + Array.new(described_class::HISTORY_MESSAGES) { { role: 'assistant', content: 'Certo.' } }

    expect(described_class.new(query: 'Vou fazer só de 10.', history: turns).call).to eq('Vou fazer só de 10.')
  end

  it 'bounds the search hint without mutating the original messages' do
    question = 'Qual o valor do plano Equipe? ' + ('x' * 1000)
    turns = [{ role: 'user', content: question }]
    query = 'Vou fazer só de 10.'

    result = described_class.new(query: query, history: turns).call

    expect(result).to eq("#{query}\n#{question[0, described_class::HISTORY_ITEM_CHARS]}")
    expect(turns.first[:content]).to eq(question)
    expect(query).to eq('Vou fazer só de 10.')
  end
end
