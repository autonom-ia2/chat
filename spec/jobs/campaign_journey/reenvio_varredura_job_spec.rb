require 'rails_helper'

# #3101: o cron do "Mandar de novo" roda a varredura (CampaignJourney::Reenvio::Varredura) e está no schedule.
RSpec.describe CampaignJourney::ReenvioVarreduraJob do
  it 'runs the sweep' do
    allow(CampaignJourney::Reenvio::Varredura).to receive(:rodar)

    described_class.perform_now

    expect(CampaignJourney::Reenvio::Varredura).to have_received(:rodar)
  end

  it 'is scheduled every 15 minutes' do
    entrada = YAML.load_file(Rails.root.join('config/schedule.yml'))['campaign_journey_reenvio_varredura_job']

    expect(entrada).to include('cron' => '*/15 * * * *', 'class' => 'CampaignJourney::ReenvioVarreduraJob')
  end
end
