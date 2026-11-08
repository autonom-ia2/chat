require 'rails_helper'

# IA entende a conversa F2 (flag `crm_ia_assunto_encerrado`): a IA de etapa lê o "quando usar" do funil e, sem ele, a
# descrição que a conta já escreveu, como a IA de assunto. Sem a flag, só o "quando usar", como antes.
RSpec.describe Crm::Ai::StageClassifier do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Funil A') }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:card) { account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: create(:contact, account: account), title: 'Pedido') }

  before { pipeline.update!(when_to_use: nil, description: 'Texto que a conta escreveu.') }

  def funil_na_entrada
    described_class.new(card: card, client: nil, stages: [], context: { current_stage: { id: stage.id, name: stage.name } }).pacote[:pipeline]
  end

  it 'sem a flag, a entrada é a de antes (sem a descrição)' do
    expect(funil_na_entrada).to eq(kind: pipeline.kind)
  end

  it 'com a flag, a descrição entra como "quando usar"; o "quando usar" escrito vale mais', :aggregate_failures do
    account.enable_features!(Crm::Subjects::Encerrado::FLAG)

    expect(funil_na_entrada).to eq(kind: pipeline.kind, when_to_use: 'Texto que a conta escreveu.')
    pipeline.update!(when_to_use: 'Quando usar escrito.')
    expect(funil_na_entrada).to eq(kind: pipeline.kind, when_to_use: 'Quando usar escrito.')
  end
end
