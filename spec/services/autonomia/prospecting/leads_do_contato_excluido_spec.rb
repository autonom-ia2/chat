require 'rails_helper'

# #2143 (LGPD): excluir o contato apaga de vez o lead da Prospecção que é desta pessoa (o dono do contato e o que chega
# a ela só pelo card), por todo caminho de exclusão, com a flag crm_arquivados. O lead de outra empresa que divide o
# número só perde o vínculo. O que recusou contato fica só com a prova da recusa, que veta a campanha ao mesmo número.
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
        decision_linkedin: 'https://linkedin.test/maria', enrichment_summary: 'Dona da clinica', score: 80,
        raw_payload: { 'displayName' => 'Clinica Sorriso Maria' }, enriched_data: { 'email' => 'maria@clinica.test' },
        metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5511999992143' },
                    'research' => { 'owners' => [{ 'name' => 'Maria Decisora' }] } }
      }.merge(attributes)
    )
    list.list_leads.create!(account: account, lead: lead)
    lead
  end

  # O lead que gravou o contato (ContactConverter): a marca fica no contato.
  def create_dono(place, **attributes)
    create_lead(place, contact: contact, **attributes).tap do |lead|
      contact.update!(custom_attributes: { 'autonomia_prospecting_lead_id' => lead.id })
    end
  end

  def create_card(contact)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Clinica Sorriso', status: :open)
  end

  def leads_com_dado_pessoal
    Autonomia::Prospecting::Lead.where(account_id: account.id)
                                .where('decision_name = :d OR website = :w OR enrichment_summary IS NOT NULL OR raw_payload <> :v',
                                       d: 'Maria Decisora', w: 'https://clinica.test', v: '{}')
  end

  def auditoria
    Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO).sole.audited_changes
  end

  context 'with the crm_arquivados flag' do
    before { account.enable_features!(:crm_arquivados) }

    it 'DELETE do contato (destroy!): o lead dono sai inteiro, sem sobrar dado pessoal, com frase própria na Auditoria' do
      lead = create_dono('dono')
      Current.user = admin

      contact.destroy!

      expect(Autonomia::Prospecting::Lead.exists?(lead.id)).to be(false)
      expect(Autonomia::Prospecting::ListLead.where(prospect_lead_id: lead.id)).to be_empty
      expect(leads_com_dado_pessoal).to be_empty
      expect(auditoria).to include('alvo' => 'contato', 'contact_id' => contact.id, 'modo' => 'leads', 'leads_apagados' => 1,
                                   'lead_ids_apagados' => [lead.id], 'leads_minimizados' => 0)
    ensure
      Current.reset
    end

    it 'lead de outra empresa que divide o número com o contato só perde o vínculo' do
      dono = create_dono('dono')
      outra_empresa = create_lead('central-unica', contact: contact, name: 'Clinica Vizinha', decision_name: 'Joao Vizinho')

      contact.destroy!

      expect(Autonomia::Prospecting::Lead.exists?(dono.id)).to be(false)
      expect(outra_empresa.reload).to have_attributes(contact_id: nil, name: 'Clinica Vizinha', decision_name: 'Joao Vizinho')
      expect(auditoria).to include('lead_ids_apagados' => [dono.id])
    end

    it 'o lead que chega à pessoa só pelo card também sai; o da outra empresa com card do contato só perde o vínculo' do
      card = create_card(contact)
      pelo_card = create_lead('pelo-card', crm_card: card)
      outra_empresa = create_lead('outra', contact: contact, crm_card: create_card(contact))

      contact.destroy!

      expect(Autonomia::Prospecting::Lead.exists?(pelo_card.id)).to be(false)
      expect(outra_empresa.reload).to have_attributes(contact_id: nil, crm_card_id: nil, name: 'Clinica Sorriso Maria')
      expect(auditoria).to include('modo' => 'keep', 'leads_apagados' => 1, 'cards_mantidos' => 2)
    end

    it 'lead de card religado a outro contato vivo (ContactLinker) é daquela pessoa e fica' do
      card = create_card(contact)
      outra_pessoa = account.contacts.create!(name: 'Outra', phone_number: '+5511944442143')
      religado = create_lead('religado', crm_card: card, contact: outra_pessoa)

      contact.destroy!

      expect(religado.reload).to have_attributes(contact_id: outra_pessoa.id, name: 'Clinica Sorriso Maria')
    end

    it 'o recusado sem lugar no Google perde também a chave de duplicidade, que era o nome do negócio' do
      sem_lugar = create_dono('x', provider_place_id: nil, status: :no_consent)
      expect(sem_lugar.dedupe_key).to eq('mock:clinica sorriso maria')

      contact.destroy!

      expect(sem_lugar.reload.dedupe_key).to eq("mock:removido-#{sem_lugar.id}")
    end

    it 'o dono que recusou contato fica só com a prova da recusa, e o veto da campanha ao mesmo número continua' do
      recusou = create_dono('recusou', consent_refused_at: 1.day.ago, consent_refused_by: admin)

      contact.destroy!

      recusou.reload
      expect(recusou).to have_attributes(
        contact_id: nil, phone: '+5511999992143', enriched_whatsapp: '+5511999992143', enriched_email: 'maria@clinica.test',
        consent_refused_by_id: admin.id, name: "Lead removido ##{recusou.id}", decision_name: nil, decision_linkedin: nil,
        website: nil, address: nil, provider_place_id: nil, enrichment_summary: nil, score: nil, raw_payload: {},
        enriched_data: {}, enrichment_status: 'skipped', prospect_search_id: nil
      )
      expect(recusou.consent_refused_at).to be_present
      expect(recusou.metadata).to eq('whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5511999992143' })
      expect(Autonomia::Prospecting::ListLead.where(prospect_lead_id: recusou.id)).to be_empty
      expect(leads_com_dado_pessoal).to be_empty
      novo = create_lead('reimportado', phone: '+5511999992143', provider_place_id: 'places/outro')
      expect(Autonomia::Prospecting::ConsentVeto.new(account: account).vetoed?(lead: novo, contact: nil)).to be(true)
      expect(auditoria).to include('modo' => 'leads', 'leads_apagados' => 0, 'lead_ids_minimizados' => [recusou.id])
    end

    it 'o lead no_consent também fica só com a prova, mesmo sem data de recusa gravada antes' do
      no_consent = create_dono('no-consent', status: :no_consent)

      contact.destroy!

      expect(no_consent.reload).to have_attributes(status: 'no_consent', decision_name: nil, phone: '+5511999992143')
    end

    it 'lead nunca ligado ao contato, mesmo com o mesmo telefone, não é tocado e não há Auditoria' do
      solto = create_lead('solto')

      contact.destroy!

      expect(solto.reload.decision_name).to eq('Maria Decisora')
      expect(Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO)).to be_empty
    end

    it 'exclusão em lote: o lead dono sai com o contato' do
      lead = create_dono('lote')

      Contacts::BulkDeleteService.new(account: account, contact_ids: [contact.id], user: admin).perform

      expect(Autonomia::Prospecting::Lead.exists?(lead.id)).to be(false)
      expect(Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO).sole.user).to eq(admin)
    end

    it "excluir de vez com 'delete': os cards e o lead saem, numa linha só da Auditoria" do
      card = create_card(contact)
      lead = create_dono('delete', crm_card: card)

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
      lead = create_dono('mescla')
      base = account.contacts.create!(name: 'Base', phone_number: '+5511955552143')

      ContactMergeAction.new(account: account, base_contact: base, mergee_contact: contact).perform

      expect(lead.reload.contact_id).to eq(base.id)
    end
  end

  it 'sem a flag, como na main: o lead só perde o contato' do
    lead = create_dono('sem-flag')

    contact.destroy!

    expect(lead.reload).to have_attributes(contact_id: nil, decision_name: 'Maria Decisora')
  end

  describe 'com_retentativa (impasse com a conversão de um lead)' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:transaction_open?).and_return(false)
      allow(Crm::ExclusaoDefinitiva).to receive(:sleep)
    end

    it 'refaz o pedido depois de um impasse e desiste depois de TENTATIVAS' do
      tentativas = 0
      resultado = Crm::ExclusaoDefinitiva.com_retentativa do
        tentativas += 1
        raise ActiveRecord::Deadlocked if tentativas == 1

        :feito
      end
      expect([resultado, tentativas]).to eq([:feito, 2])

      expect { Crm::ExclusaoDefinitiva.com_retentativa { raise ActiveRecord::Deadlocked } }.to raise_error(ActiveRecord::Deadlocked)
      expect(Crm::ExclusaoDefinitiva).to have_received(:sleep).exactly(3).times
    end
  end
end
