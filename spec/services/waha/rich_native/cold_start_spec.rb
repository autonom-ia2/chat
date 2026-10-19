require 'rails_helper'

# chat#1709: ligar a flag lê os motores na hora, sem esperar o cron (até 5 min).
RSpec.describe Waha::RichNative::ColdStart do
  let(:account) { create(:account) }

  around { |example| with_modified_env(WAHA_RICH_NATIVE_ENGINES: 'https://waha.example') { example.run } }

  it 'enqueues the refresh once when the flag is turned on' do
    expect { account.enable_features!(Waha::RichNative::FLAG) }.to have_enqueued_job(Waha::EngineCapabilitiesRefreshJob).once
  end

  it 'does not enqueue for another flag, for an account already with the flag, or without engines' do
    account.enable_features!(Waha::RichNative::FLAG)

    expect { account.enable_features!('crm_outro_canal') }.not_to have_enqueued_job(Waha::EngineCapabilitiesRefreshJob)
    expect { account.update!(name: 'Outra') }.not_to have_enqueued_job(Waha::EngineCapabilitiesRefreshJob)
    expect { account.disable_features!(Waha::RichNative::FLAG) }.not_to have_enqueued_job(Waha::EngineCapabilitiesRefreshJob)
    with_modified_env(WAHA_RICH_NATIVE_ENGINES: '') do
      expect { account.enable_features!(Waha::RichNative::FLAG) }.not_to have_enqueued_job(Waha::EngineCapabilitiesRefreshJob)
    end
  end
end
