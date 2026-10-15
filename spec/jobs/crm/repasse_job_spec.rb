require 'rails_helper'

RSpec.describe Crm::RepasseJob do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:com_pessoa) { create(:conversation, account: account, inbox: inbox, status: :open, assignee: agent) }
  let(:sem_pessoa) { create(:conversation, account: account, inbox: inbox, status: :open, assignee: nil) }
  let(:resolvida) { create(:conversation, account: account, inbox: inbox, status: :resolved, assignee: agent) }

  it 'agenda só as conversas em andamento com pessoa no nome' do
    ids = [com_pessoa.id, sem_pessoa.id, resolvida.id]
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.agendar(ids)

    expect(described_class).to have_been_enqueued.with(com_pessoa.id).once
    expect(described_class).not_to have_been_enqueued.with(sem_pessoa.id)
    expect(described_class).not_to have_been_enqueued.with(resolvida.id)
  end

  it 'avalia a sugestão da conversa, e nada faz com o CRM desligado ou a conversa sumida' do
    allow(Crm::Repasse).to receive(:sugerir!)
    allow(Crm::Config).to receive(:enabled?).and_return(true)

    described_class.perform_now(com_pessoa.id)
    described_class.perform_now(0)
    expect(Crm::Repasse).to have_received(:sugerir!).once

    allow(Crm::Config).to receive(:enabled?).and_return(false)
    described_class.perform_now(com_pessoa.id)
    expect(Crm::Repasse).to have_received(:sugerir!).once
  end
end
