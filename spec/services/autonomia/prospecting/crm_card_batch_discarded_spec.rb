require 'rails_helper'

# Lead descartado não vai para o CRM (#732, item 10), nem em lote nem no envio individual, que passa pelo mesmo lote.
RSpec.describe Autonomia::Prospecting::CrmCardBatch do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }

  before { allow(Crm::Config).to receive(:enabled?).and_return(true) }

  def create_lead(index, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "crm-discarded-#{index}", name: "Empresa #{index}",
      phone: "+55 31 99999-20#{index.to_s.rjust(2, '0')}", country: 'BR', **attributes
    )
  end

  it 'lead descartado falha com o motivo e não cria card nem contato; o resto do lote segue' do
    pipeline, stage = pipeline_and_stage
    ok = create_lead(1)
    discarded = create_lead(2, status: :discarded, discard_reason: 'Sem interesse')

    result = described_class.new(account: account, user: user, lead_ids: [ok.id, discarded.id], pipeline_id: pipeline.id,
                                 stage_id: stage.id).perform

    expect(result.created.map { |row| row[:lead_id] }).to eq([ok.id])
    expect(result.failed).to eq([{ lead_id: discarded.id, reason_code: 'discarded',
                                   message: I18n.t('autonomia.prospecting.crm_send.failures.discarded') }])
    expect(discarded.reload.crm_card_id).to be_nil
    expect(discarded.contact_id).to be_nil
    expect(account.crm_cards.count).to eq(1)
  end
end
