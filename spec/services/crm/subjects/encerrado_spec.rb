require 'rails_helper'

# IA entende a conversa F2 (flag `crm_ia_assunto_encerrado`): quais cards fechados viram opção da IA de assunto, como a
# pergunta os descreve e o "o que entra aqui" da IA de etapa. Sem a flag, tudo como antes.
RSpec.describe Crm::Subjects::Encerrado do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Funil A') }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:contact) { create(:contact, account: account, name: 'Pessoa Cliente') }

  def card(titulo, status: :open, fechado_ha: nil, nomeado: true)
    criado = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: titulo,
                                       metadata: nomeado ? { 'subject' => { 'source' => 'ai' } } : {})
    return criado if status == :open

    criado.update!(status: status)
    criado.update_columns(closed_at: fechado_ha.ago) # rubocop:disable Rails/SkipsModelValidations
    criado
  end

  def question(encerrados:, varios: false, abertos: [])
    Crm::Subjects::Question.new(account: account, pipelines: [pipeline], cards: abertos, atual: abertos.first, varios: varios,
                                encerrados: encerrados)
  end

  describe '.da_conversa' do
    it 'sem a flag, nenhum' do
      expect(described_class.da_conversa(account, [card('Pedido A', status: :lost, fechado_ha: 1.day)])).to eq([])
    end

    context 'with the flag on' do
      before { account.enable_features!(described_class::FLAG) }

      it 'só fechados dentro da janela, os mais recentes primeiro, até o máximo', :aggregate_failures do
        aberto = card('Pedido aberto')
        velho = card('Pedido velho', status: :won, fechado_ha: 91.days)
        fechados = [card('Pedido 1', status: :lost, fechado_ha: 5.days), card('Pedido 2', status: :won, fechado_ha: 1.day),
                    card('Pedido 3', status: :lost, fechado_ha: 3.days), card('Pedido 4', status: :lost, fechado_ha: 10.days)]

        escolhidos = described_class.da_conversa(account, [aberto, velho, *fechados])

        expect(escolhidos.map(&:title)).to eq(['Pedido 2', 'Pedido 3', 'Pedido 1'])
        expect(escolhidos.size).to eq(described_class::MAX)
      end
    end
  end

  describe 'a pergunta' do
    let(:fechado) { card('Pedido A', status: :won, fechado_ha: 2.days) }

    it 'com encerrado: a opção, a descrição, a chave na lista de vários e a frase no fim das instruções', :aggregate_failures do
      pergunta = question(encerrados: [fechado], varios: true)
      chave = "encerrado_#{fechado.id}"
      descricao = pergunta.respostas.find { |resposta| resposta['chave'] == chave }['descricao']

      expect(pergunta.opcao(chave)).to have_attributes(tipo: :encerrado, card: fechado)
      expect(descricao).to include('closed subject "Pedido A"', 'closed as won 2 days ago', 'does not continue')
      expect(pergunta.chaves_de_assunto).to include(chave)
      expect(pergunta.instrucoes).to end_with(described_class::INSTRUCAO)
      expect(pergunta.com_encerrados('x', lista: true)).to end_with(described_class::INSTRUCAO_DA_LISTA)
    end

    it 'o encerrado sem nome vai sem o título (o nome do contato), com a última etapa' do
      sem_nome = card('Pessoa Cliente', status: :lost, fechado_ha: 0.days, nomeado: false)
      descricao = question(encerrados: [sem_nome]).respostas.find { |resposta| resposta['chave'] == "encerrado_#{sem_nome.id}" }['descricao']

      expect(descricao).to include("with no name, last stage \"#{stage.name}\"", 'closed as lost today')
      expect(descricao).not_to include('Pessoa Cliente')
    end

    it 'sem encerrado, a pergunta é a de sempre, palavra por palavra', :aggregate_failures do
      pergunta = question(encerrados: [])

      expect(pergunta.instrucoes).to eq(Crm::Subjects::Question::INSTRUCOES)
      expect(pergunta.chaves).to eq(['sem_assunto', "novo_#{pipeline.id}"])
      expect(pergunta.com_encerrados('x', lista: true)).to eq('x')
    end
  end

  describe '.quando_usar' do
    before { pipeline.update!(when_to_use: nil, description: 'Texto que a conta escreveu.') }

    it 'sem a flag, só o "quando usar", como antes' do
      expect(described_class.quando_usar(pipeline)).to be_nil
    end

    it 'com a flag, a descrição quando não há "quando usar"; o "quando usar" vale mais', :aggregate_failures do
      account.enable_features!(described_class::FLAG)

      expect(described_class.quando_usar(pipeline)).to eq('Texto que a conta escreveu.')
      pipeline.update!(when_to_use: 'Quando usar escrito.')
      expect(described_class.quando_usar(pipeline)).to eq('Quando usar escrito.')
    end

    it 'com a flag, a descrição longa entra com o teto do "quando usar"' do
      account.enable_features!(described_class::FLAG)
      pipeline.update!(description: 'a' * (Crm::Pipeline::MAX_WHEN_TO_USE + 500))

      expect(described_class.quando_usar(pipeline).size).to eq(Crm::Pipeline::MAX_WHEN_TO_USE)
    end
  end
end
