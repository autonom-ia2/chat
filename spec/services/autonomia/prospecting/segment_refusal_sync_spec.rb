require 'rails_helper'

# Recusa depois do segmento (#732, revisão da E8), o trabalho do job: tirar a etiqueta de segmento só dos contatos que os
# leads recusados alcançam, em todas as listas cuja etiqueta está neles, sem salvar o contato inteiro e sem reprocessar a
# lista inteira.
RSpec.describe Autonomia::Prospecting::SegmentRefusalSync do
  include ProspectingEventLogHelpers

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }

  def new_list(name)
    Autonomia::Prospecting::List.create!(account: account, user: admin, name: name)
  end

  def create_lead(key, phone, lists:)
    lead = Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "sync-#{key}", name: "Lead #{key}", phone: phone, country: 'BR',
      status: :ready_for_campaign, metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => phone } }
    )
    lists.each { |list| list.list_leads.create!(account: account, lead: lead) }
    lead
  end

  def phone(index) = format('+55319%08d', index)

  def generate_segment(list)
    Autonomia::Prospecting::CampaignSegmentBuilder.new(list: list, user: admin).perform.label.title
  end

  def refuse(*leads)
    leads.each { |lead| lead.update!(status: :discarded, discard_reason: 'Sem interesse') }
    described_class.new(account: account).perform(leads.map(&:id))
  end

  def labels_of(lead) = lead.reload.contact.reload.label_list

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql].start_with?('SAVEPOINT', 'RELEASE') }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  it 'tira a etiqueta das duas listas em que o lead estava e mantém o outro lead elegível da segunda' do
    first_list = new_list('Primeira')
    second_list = new_list('Segunda')
    refused = create_lead(1, phone(1), lists: [first_list, second_list])
    other = create_lead(2, phone(2), lists: [second_list])
    create_lead(3, phone(3), lists: [first_list])
    first_label = generate_segment(first_list)
    second_label = generate_segment(second_list)

    refuse(refused)

    expect(labels_of(refused)).not_to include(first_label, second_label)
    expect(labels_of(other)).to include(second_label)
  end

  it 'lead que voltou a não ser recusado antes do job não perde a etiqueta' do
    list = new_list('Lista')
    lead = create_lead(1, phone(1), lists: [list])
    label_title = generate_segment(list)
    lead.update!(status: :discarded, discard_reason: 'Engano')
    lead.update!(status: :ready_for_campaign)

    described_class.new(account: account).perform([lead.id])

    expect(labels_of(lead)).to include(label_title)
  end

  it 'falha ao tirar a etiqueta de um contato vai para o registro, sem dado pessoal, e os outros seguem' do
    list = new_list('Lista')
    leads = [1, 2, 3].map { |index| create_lead(index, phone(index), lists: [list]) }
    label_title = generate_segment(list)
    broken_contact_id = leads[1].reload.contact_id
    allow(ActsAsTaggableOn::Tagging).to receive(:where).and_wrap_original do |original, *args, **kwargs|
      conditions = args.first.is_a?(Hash) ? args.first : kwargs
      raise ActiveRecord::StatementInvalid, 'falha simulada' if conditions[:taggable_id] == broken_contact_id

      original.call(*args, **kwargs)
    end
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original

    captured = capture_prospecting_events { refuse(*leads) }

    expect(labels_of(leads[0])).not_to include(label_title)
    expect(labels_of(leads[2])).not_to include(label_title)
    expect(labels_of(leads[1])).to include(label_title)
    expect(captured.events).to include(
      a_hash_including('event' => 'segment.label_removal_failed', 'lead_id' => leads[1].id, 'reason' => 'ActiveRecord::StatementInvalid')
    )
    expect(captured.text).not_to include(phone(2))
    expect(ChatwootExceptionTracker).to have_received(:new).with(kind_of(ActiveRecord::StatementInvalid), account: account)
  end

  it 'o número de queries não cresce com o tamanho da lista' do
    queries = [3, 40].map do |size|
      list = new_list("Lista #{size}")
      leads = Array.new(size) { |index| create_lead("#{size}-#{index}", phone((size * 100) + index), lists: [list]) }
      generate_segment(list)
      leads.first.update!(status: :discarded, discard_reason: 'Sem interesse')
      count_queries { described_class.new(account: account).perform([leads.first.id]) }
    end

    expect(queries.last).to be <= queries.first
    expect(queries.last).to be <= 25
  end
end
