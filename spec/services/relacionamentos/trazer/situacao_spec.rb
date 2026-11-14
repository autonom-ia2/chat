require 'rails_helper'

# #2896 — a situação de uma lista trazida, nas palavras da tela, e quais importações entram no histórico.
RSpec.describe Relacionamentos::Trazer::Situacao, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  def importacao(**dados)
    account.campaign_imports.create!(user: user, mode: 'single_label', options: { 'flow' => CampaignImport::CONTACTS_FLOW }, **dados)
  end

  it 'diz "trazendo" da confirmação até a gravação acabar' do
    %i[confirmed queued importing].each do |status|
      expect(described_class.de(importacao(status: status))).to eq('trazendo'), status.to_s
    end
  end

  it 'diz "pronto" para a lista gravada, com ou sem linha que falhou, enquanto ninguém a desfez' do
    %i[completed completed_with_failures].each do |status|
      expect(described_class.de(importacao(status: status))).to eq('pronto'), status.to_s
      expect(described_class.de(importacao(status: status, undo_status: :failed))).to eq('pronto'), status.to_s
    end
  end

  it 'diz "desfazendo" e "desfeito" pelo estado do desfazer' do
    expect(described_class.de(importacao(status: :completed, undo_status: :processing))).to eq('desfazendo')
    expect(described_class.de(importacao(status: :completed_with_failures, undo_status: :completed))).to eq('desfeito')
  end

  it 'diz "falhou" só para a gravação que começou e quebrou' do
    expect(described_class.de(importacao(status: :failed, import_started_at: 1.hour.ago))).to eq('falhou')
    expect(described_class.de(importacao(status: :failed))).to be_nil
  end

  it 'não dá situação ao rascunho nem ao que não é lista trazida' do
    %i[uploaded validating validation_failed ready_to_confirm needs_column_choice cancelled expired undoing_labels labels_undone
       undo_failed].each do |status|
      expect(described_class.de(importacao(status: status))).to be_nil, status.to_s
    end
  end

  it 'põe no histórico exatamente as importações que têm situação' do
    todas = CampaignImport.statuses.keys.flat_map do |status|
      [importacao(status: status), importacao(status: status, import_started_at: 1.hour.ago)]
    end
    com_situacao = todas.select { |feita| described_class.de(feita) }

    expect(described_class.no_historico(account.campaign_imports).pluck(:id)).to match_array(com_situacao.map(&:id))
    expect(com_situacao.map(&:status).uniq).to match_array(%w[confirmed queued importing completed completed_with_failures failed])
  end

  it 'conta 100 por cento para a lista que acabou e o que já passou para a que está entrando ou parou' do
    expect(described_class.porcentagem('pronto', 0, 10)).to eq(100)
    expect(described_class.porcentagem('desfazendo', 3, 10)).to eq(100)
    expect(described_class.porcentagem('desfeito', 3, 10)).to eq(100)
    expect(described_class.porcentagem('trazendo', 0, 10)).to eq(0)
    expect(described_class.porcentagem('trazendo', 1, 3)).to eq(33)
    expect(described_class.porcentagem('falhou', 5, 10)).to eq(50)
    expect(described_class.porcentagem('trazendo', 10, 10)).to eq(100)
    expect(described_class.porcentagem('trazendo', 0, 0)).to eq(0)
  end
end
