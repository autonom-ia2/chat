require 'rails_helper'

# #1924: a IA de assunto separa venda de pós-venda. Cada exemplo diz a falha que pega.
RSpec.describe Crm::Subjects::Question do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Pessoa Teste') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas').first }
  let(:atendimento) { create_crm_pipeline(account: account, user: admin, name: 'Atendimento').first.tap { |p| p.update!(counts_as_sale: false) } }
  let!(:implantacao) { create_crm_stage(account: account, pipeline: vendas, name: 'Implantação', position: 1) }

  def card(titulo, pipeline: vendas, stage: implantacao)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, primary_conversation: conversation, inbox: inbox,
                              title: titulo)
  end

  def descricoes(atual)
    question = described_class.new(account: account, pipelines: [vendas, atendimento], cards: [atual].compact, atual: atual)
    question.respostas.to_h { |resposta| [resposta['chave'], resposta['descricao']] }
  end

  # MOTIVO: sem o tipo do funil, um cancelamento de quem já é cliente caía no funil de venda.
  it 'cada pedido novo diz o tipo do funil: venda ou atendimento a quem já é cliente' do
    lido = descricoes(nil)

    expect(lido["novo_#{vendas.id}"]).to include(described_class::TIPOS_DE_FUNIL.fetch('sell'))
    expect(lido["novo_#{atendimento.id}"]).to include(described_class::TIPOS_DE_FUNIL.fetch('serve'))
  end

  # MOTIVO: dúvida de quem está na Implantação de um funil de venda é do assunto atual; a IA precisa ver a etapa e o tipo.
  it 'o assunto aberto diz o funil, o tipo e a etapa em que está' do
    lido = descricoes(card('Plano anual'))

    expect(lido[described_class::MESMO_ASSUNTO]).to include('"Plano anual"', '"Vendas"', described_class::TIPOS_DE_FUNIL.fetch('sell'),
                                                            'stage "Implantação"')
  end

  # MOTIVO: com o card atual sem nome, o funil dele tinha um texto mais convidativo e puxava o pedido para lá.
  it 'com o card atual sem nome, o pedido novo tem o mesmo texto em todos os funis' do
    lido = descricoes(card('Pessoa Teste'))
    sem_tipo = lambda do |pipeline|
      lido["novo_#{pipeline.id}"].sub(pipeline.name, 'X').sub(described_class::TIPOS_DE_FUNIL.fetch(pipeline.kind), 'T')
    end

    expect(lido).not_to have_key(described_class::MESMO_ASSUNTO)
    expect(sem_tipo.call(vendas)).to eq(sem_tipo.call(atendimento))
  end

  # MOTIVO: o Jev precisa da regra que diz o que fazer com o tipo, nas duas versões da pergunta.
  it 'as instruções explicam o tipo do funil, com e sem vários assuntos' do
    [false, true].each do |varios|
      question = described_class.new(account: account, pipelines: [vendas], cards: [], atual: nil, varios: varios)
      expect(question.instrucoes).to include(described_class::REGRA_DO_TIPO)
    end
  end
end
