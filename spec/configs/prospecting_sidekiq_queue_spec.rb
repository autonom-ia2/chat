require 'rails_helper'

# Fila própria da Prospecção (#678): na low, com prioridade estrita, uma busca de 60 leads com pesquisa ligada segurava a
# scheduled_jobs (varredor, agendamentos, IMAP, follow-ups do CRM de todas as contas) enquanto houvesse enriquecimento.
RSpec.describe 'Fila da Prospecção no Sidekiq' do # rubocop:disable RSpec/DescribeClass
  let(:queues) { YAML.load(ERB.new(Rails.root.join('config/sidekiq.yml').read).result)[:queues] }

  it 'enriquecimento e verificação de WhatsApp rodam na fila prospecting' do
    expect(Autonomia::Prospecting::EnrichLeadJob.new.queue_name).to eq('prospecting')
    expect(Autonomia::Prospecting::VerifyWhatsappJob.new.queue_name).to eq('prospecting')
  end

  it 'a fila prospecting existe no Sidekiq e fica abaixo da scheduled_jobs' do
    expect(queues).to include('prospecting')
    expect(queues.index('prospecting')).to be > queues.index('scheduled_jobs')
  end
end
