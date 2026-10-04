require 'spec_helper'
require 'rake'
require 'climate_control'

# rubocop:disable RSpec/VerifiedDoubleReference -- The task delegates to a double without booting Rails or its services.
RSpec.describe Rake::Task do
  subject(:task) { Rake.application['instagram:rollout_assisted_onboarding'] }

  let(:rollout) { instance_double('Instagram::Automation::AccountRollout', call: { would_enable: 2, enabled: 0 }) }

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    described_class.define_task(:environment)
    load File.expand_path('../../../../lib/tasks/instagram_account_rollout.rake', __dir__)
    example.run
  ensure
    Rake.application = original_application
  end

  before do
    class_double('Instagram::Automation::AccountRollout').as_stubbed_const
    allow(Instagram::Automation::AccountRollout).to receive(:new).and_return(rollout)
  end

  it 'defaults to dry-run with no confirmation' do
    with_modified_env DRY_RUN: nil, INSTAGRAM_ROLLOUT_CONFIRM: nil do
      expect { task.invoke }.to output(a_string_including('dry_run=true', 'would_enable=2')).to_stdout
    end
    expect(rollout).to have_received(:call).with(dry_run: true, confirmation: nil)
  end

  it 'requires DRY_RUN=false even when the confirmation is present' do
    with_modified_env DRY_RUN: nil, INSTAGRAM_ROLLOUT_CONFIRM: 'instagram_assisted_onboarding' do
      task.invoke
    end
    expect(rollout).to have_received(:call).with(dry_run: true, confirmation: 'instagram_assisted_onboarding')
  end

  it 'passes explicit apply mode and confirmation to the service' do
    with_modified_env DRY_RUN: 'false', INSTAGRAM_ROLLOUT_CONFIRM: 'instagram_assisted_onboarding' do
      task.invoke
    end
    expect(rollout).to have_received(:call).with(dry_run: false, confirmation: 'instagram_assisted_onboarding')
  end

  it 'propagates a missing-confirmation error from the service' do
    allow(rollout).to receive(:call).with(dry_run: false, confirmation: nil).and_raise(ArgumentError, 'confirmation required')
    with_modified_env DRY_RUN: 'false', INSTAGRAM_ROLLOUT_CONFIRM: nil do
      expect { task.invoke }.to raise_error(ArgumentError, 'confirmation required')
    end
  end

  it 'rejects malformed modes before constructing the service' do
    ['', '0', '1', 'False', 'typo'].each do |mode|
      task.reenable
      with_modified_env DRY_RUN: mode do
        expect { task.invoke }.to raise_error(ArgumentError, 'DRY_RUN must be true or false')
      end
    end
    expect(Instagram::Automation::AccountRollout).not_to have_received(:new)
  end
end
# rubocop:enable RSpec/VerifiedDoubleReference
