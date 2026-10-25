require 'rails_helper'

# #2143 (LGPD): excluir o contato apaga de vez os leads da Prospecção ligados a ele, por todo caminho de exclusão, com a
# flag crm_arquivados. O lead que recusou contato fica: é a prova da recusa e o que veta a campanha ao mesmo número.
RSpec.describe Autonomia::Prospecting::LeadsDoContatoExcluido do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { account.contacts.create!(name: 'Maria Decisora', phone_number: '+5511999992143', email: 'maria@clinica.test') }
  let(:list) { Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Clinicas') }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }

  # Tudo o que o lead guarda da pessoa: o que a busca trouxe, o que o enriquecimento e a pesquisa acharam.
  def create_lead(place, **attributes)
    lead = Autonomia::Prospecting::Lead.create!(
      {
        account: account, provider: 'mock', provider_place_id: "places/#{place}", name: 'Clinica Sorriso Maria',
        phone: '+5511999992143', website: 'https://clinica.test', address: 'Rua das Flores, 10', country: 'BR',
        enriched_email: 'maria@clinica.test', enriched_whatsapp: '+5511999992143', decision_name: 'Maria Decisora',
        decision_linkedin: 'https://linkedin.test/maria', enrichment_summary: 'Dona da clinica',
        raw_payload: { 'displayName' => 'Clinica Sorriso Maria' }, enriched_data: { 'email' => 'maria@clinica.test' }
      }.merge(attributes)
    )
    list.list_leads.create!(account: account, lead: lead)
    lead
  end

  def create_card(contact)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Clinica Sorriso', status: :open)
  end

  def leads_com_dado_pessoal
    Autonomia::Prospecting::Lead.where(account_id: account.id)
                                .where('phone = :p OR enriched_email = :e OR decision_name = :d',
                                       p: '+5511999992143', e: 'maria@clinica.test', d: 'Maria Decisora')
  end

  def auditoria
    Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO).sole.audited_changes
  end

  context 'with the crm_arquivados flag' do
    before { account.enable_features!(:crm_arquivados) }

    it 'DELETE do contato (destroy!): o lead ligado sai inteiro, sem sobrar dado pessoal, e entra na Auditoria' do
      lead = create_lead('ligado', contact: contact)
      Current.user = admin

      contact.destroy!

      expect(Autonomia::Prospecting::Lead.exists?(lead.id)).to be(false)
      expect(Autonomia::Prospecting::ListLead.where(prospect_lead_id: lead.id)).to be_empty
      expect(leads_com_dado_pessoal).to be_empty
      expect(auditoria).to include('alvo' => 'contato', 'contact_id' => contact.id, 'leads_apagados' => 1,
                                   'lead_ids_apagados' => [lead.id], 'leads_mantidos_por_recusa' => 0)
    ensure
      Current.reset
    end

    it 'o lead ligado só pelo card do contato também sai' do
      card = create_card(contact)
      lead = create_lead('pelo-card', crm_card: card)

      contact.destroy!

      expect(Autonomia::Prospecting::Lead.exists?(lead.id)).to be(false)
      expect(auditoria).to include('leads_apagados' => 1, 'cards_mantidos' => 1)
    end

    it 'o lead que recusou contato fica com o telefone (prova da recusa e veto da campanha), só sem o contato' do
      recusou = create_lead('recusou', contact: contact, consent_refused_at: 1.day.ago)
      no_consent = create_lead('no-consent', contact: contact, status: :no_consent, phone: '+5511988882143')
      apagado = create_lead('apagado', contact: contact, phone: '+5511977772143')

      contact.destroy!

      expect(recusou.reload).to have_attributes(contact_id: nil, phone: '+5511999992143')
      expect(recusou.consent_refused_at).to be_present
      expect(no_consent.reload).to have_attributes(contact_id: nil, status: 'no_consent')
      expect(Autonomia::Prospecting::Lead.exists?(apagado.id)).to be(false)
      expect(auditoria).to include('leads_apagados' => 1, 'lead_ids_mantidos_por_recusa' => [recusou.id, no_consent.id])
    end

    it 'lead nunca ligado ao contato, mesmo com o mesmo telefone, e lead de outro contato não são tocados' do
      solto = create_lead('solto')
      outro = create_lead('outro', contact: account.contacts.create!(name: 'Outro', phone_number: '+5511966662143'))

      contact.destroy!

      expect(Autonomia::Prospecting::Lead.where(id: [solto.id, outro.id]).count).to eq(2)
      expect(Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO)).to be_empty
    end

    it 'exclusão em lote: o lead sai com o contato' do
      lead = create_lead('lote', contact: contact)

      Contacts::BulkDeleteService.new(account: account, contact_ids: [contact.id], user: admin).perform

      expect(Autonomia::Prospecting::Lead.exists?(lead.id)).to be(false)
      expect(Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO).sole.user).to eq(admin)
    end

    it "excluir de vez com 'delete': os cards e o lead saem, numa linha só da Auditoria" do
      card = create_card(contact)
      lead = create_lead('delete', contact: contact, crm_card: card)

      Crm::ExclusaoDefinitiva.contato!(contact: contact, user: admin, modo: 'delete')

      expect(Autonomia::Prospecting::Lead.exists?(lead.id)).to be(false)
      expect(leads_com_dado_pessoal).to be_empty
      expect(auditoria).to include('modo' => 'delete', 'card_ids' => [card.id], 'leads_apagados' => 1)
    end

    it "excluir de vez com 'keep': o card fica sem dado pessoal e o lead sai, numa linha só da Auditoria" do
      card = create_card(contact)
      lead = create_lead('keep', crm_card: card)

      Crm::ExclusaoDefinitiva.contato!(contact: contact, user: admin, modo: 'keep')

      expect(Autonomia::Prospecting::Lead.exists?(lead.id)).to be(false)
      expect(auditoria).to include('modo' => 'keep', 'card_ids_mantidos' => [card.id], 'lead_ids_apagados' => [lead.id])
    end

    it 'mesclar contatos não apaga o lead: ele passa para o contato que fica' do
      lead = create_lead('mescla', contact: contact)
      base = account.contacts.create!(name: 'Base', phone_number: '+5511955552143')

      ContactMergeAction.new(account: account, base_contact: base, mergee_contact: contact).perform

      expect(lead.reload.contact_id).to eq(base.id)
    end
  end

  it 'sem a flag, como na main: o lead só perde o contato' do
    lead = create_lead('sem-flag', contact: contact)

    contact.destroy!

    expect(lead.reload).to have_attributes(contact_id: nil, decision_name: 'Maria Decisora')
  end
end
