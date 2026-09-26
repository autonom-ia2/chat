require 'rails_helper'

# A recusa do lead segue os números dele (chat#713): o lead recusado que ganha depois um telefone, um WhatsApp ou um
# e-mail novo (enriquecimento, busca refeita) marca o contato que já existia com esse número ou e-mail, na mesma gravação.
# E o "Desfazer" só solta a marca dos contatos que o próprio lead desfeito alcança: marca que sobra (número antigo,
# contato mesclado, contato que o converter marcou por outro número) é o erro conservador, quem recusou não volta a
# receber por engano.
RSpec.describe Autonomia::Prospecting::ContactOptOutSync do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:sync) { described_class.new(account: account) }

  def create_lead(key, phone, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "sync-#{key}", name: "Lead #{key}", phone: phone, country: 'BR',
      **attributes
    )
  end

  def new_contact(phone: nil, email: nil)
    create(:contact, account: account, phone_number: phone, email: email)
  end

  describe 'lead recusado que ganha número ou e-mail novo' do
    it 'o WhatsApp achado no enriquecimento marca o contato que já tinha o número' do
      existing = new_contact(phone: '+5531988887001')
      lead = create_lead(1, '+553133334444')
      sync.refuse!(lead, user: admin)
      expect(existing.reload).not_to be_opted_out

      lead.reload.update!(enriched_whatsapp: '+5531988887001')

      existing.reload
      expect(existing).to be_opted_out
      expect(existing.opt_out_source).to eq('prospecting')
    end

    it 'o e-mail achado no enriquecimento marca o contato que já tinha o e-mail' do
      existing = new_contact(email: 'dono@exemplo.com.br')
      lead = create_lead(2, '+553133334445')
      sync.refuse!(lead, user: admin)

      lead.reload.update!(enriched_email: 'Dono@Exemplo.com.br')

      expect(existing.reload.opt_out_source).to eq('prospecting')
    end

    it 'o telefone trocado pela busca refeita marca o contato que já tinha o número novo' do
      existing = new_contact(phone: '+5531988887011')
      lead = create_lead(3, '+553133334446')
      sync.refuse!(lead, user: admin)

      lead.reload.update!(phone: '+5531988887011')

      expect(existing.reload).to be_opted_out
    end

    it 'o lead sem recusa que ganha número não marca ninguém' do
      existing = new_contact(phone: '+5531988887021')
      lead = create_lead(4, '+553133334447')

      lead.update!(enriched_whatsapp: '+5531988887021')

      expect(existing.reload).not_to be_opted_out
    end

    it 'a recusa manual que o contato já tinha fica como está' do
      existing = new_contact(phone: '+5531988887031')
      existing.opt_out!(source: 'manual', by: admin)
      lead = create_lead(5, '+553133334448')
      sync.refuse!(lead, user: admin)

      lead.reload.update!(enriched_whatsapp: '+5531988887031')

      expect(existing.reload.opt_out_source).to eq('manual')
    end
  end

  describe 'Desfazer depois de o lead trocar de número' do
    it 'a marca que o lead pôs com o número antigo fica: o Desfazer não varre a conta' do
      old_contact = new_contact(phone: '+5531988887003')
      lead = create_lead(6, '+5531988887003')
      sync.refuse!(lead, user: admin)
      expect(old_contact.reload.opt_out_source).to eq('prospecting')
      lead.reload.update!(phone: '+5531988887999')

      described_class.new(account: account).withdraw!(lead.reload)

      expect(old_contact.reload).to be_opted_out
      expect(old_contact.opt_out_source).to eq('prospecting')
    end

    it 'a marca que outro lead recusado ainda sustenta fica' do
      shared = new_contact(phone: '+5531988887004')
      lead = create_lead(7, '+5531988887004')
      other = create_lead(8, '+5531988887004')
      sync.refuse!(lead, user: admin)
      sync.refuse!(other, user: admin)
      lead.reload.update!(phone: '+5531988887998')

      described_class.new(account: account).withdraw!(lead.reload)

      expect(shared.reload.opt_out_source).to eq('prospecting')
    end

    it 'recusa de outra origem sem sustento não sai pelo Desfazer da Prospecção' do
      manual = new_contact(phone: '+5531988887005')
      manual.opt_out!(source: 'manual', by: admin)
      lead = create_lead(9, '+5531988887006')
      sync.refuse!(lead, user: admin)

      described_class.new(account: account).withdraw!(lead.reload)

      expect(manual.reload.opt_out_source).to eq('manual')
    end
  end

  describe 'Desfazer de um lead não solta a recusa que outro lead pôs' do
    it 'a recusa que veio para o contato por mescla fica quando outro lead desfaz a dele' do
      mergee = new_contact(phone: '+5531988887041')
      lead_a = create_lead(10, '+5531988887041', contact: mergee)
      sync.refuse!(lead_a, user: admin)
      base = new_contact(phone: '+5531977777042')
      ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform
      other = create_lead(11, '+553133337043')
      sync.refuse!(other, user: admin)

      described_class.new(account: account).withdraw!(other.reload)

      expect(base.reload).to be_opted_out
      expect(base.opt_out_source).to eq('prospecting')
    end

    it 'o contato que o converter marcou pelo telefone recusado fica quando outro lead desfaz a dele' do
      lead_a = create_lead(12, '+5531966667044')
      sync.refuse!(lead_a, user: admin)
      verification = { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5531955557045' } }
      lead_c = create_lead(13, '+5531966667044', enriched_whatsapp: '+5531955557045', metadata: verification)
      contact = Autonomia::Prospecting::ContactConverter.new(lead: lead_c, user: admin).perform.contact
      expect(contact).to be_opted_out
      other = create_lead(14, '+553133337046')
      sync.refuse!(other, user: admin)

      described_class.new(account: account).withdraw!(other.reload)

      expect(contact.reload).to be_opted_out
      expect(contact.opt_out_source).to eq('prospecting')
    end
  end
end
