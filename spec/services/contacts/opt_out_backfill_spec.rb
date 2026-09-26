require 'rails_helper'

# chat#713: recusas gravadas antes da coluna no contato (lead em no_consent, descadastro de e-mail) passam para o contato
# no deploy. Sem isto, campanha e follow-up automático, que leem só Contact.opted_out, mandariam mensagem para quem já
# tinha pedido para não receber.
RSpec.describe Contacts::OptOutBackfill do
  let(:account) { create(:account) }

  def legacy_refused_lead(phone, contact: nil, target_account: account)
    lead = Autonomia::Prospecting::Lead.create!(
      account: target_account, provider: 'mock', provider_place_id: "backfill-#{phone}", name: 'Lead antigo', phone: phone,
      country: 'BR', contact: contact
    )
    # Dado de antes da coluna no contato: o status e o backfill da migration da recusa do lead (consent_refused_at =
    # updated_at) gravados sem passar pelo ContactOptOutSync nem pelo callback do lead.
    legacy = { status: Autonomia::Prospecting::Lead.statuses[:no_consent], consent_refused_at: lead.updated_at }
    lead.update_columns(legacy) # rubocop:disable Rails/SkipsModelValidations
    lead
  end

  def legacy_unsubscribe(email, target_account: account)
    EmailSuppression.create!(account: target_account, email: email, reason: 'unsubscribe', source: 'link')
  end

  it 'lead legado em no_consent marca o contato dele e os do mesmo telefone com a origem da Prospecção' do
    own = account.contacts.create!(name: 'Do lead', phone_number: '+5531999970061')
    legacy_refused_lead('+5531999970061', contact: own)
    expect(Contact.opted_out.exists?(own.id)).to be(false)

    result = described_class.new(account: account).perform

    expect(own.reload).to be_opted_out
    expect(own.opt_out_source).to eq('prospecting')
    expect(Contact.opted_out.exists?(own.id)).to be(true)
    expect(result).to eq(before: 0, after: 1)
  end

  it 'lead recusado e depois descartado, sem contato ligado, marca o contato do mesmo telefone' do
    other = account.contacts.create!(name: 'Mesmo número', phone_number: '+5531999970062')
    legacy_refused_lead('+5531999970062').update!(status: :discarded, discard_reason: 'Sem interesse')

    described_class.new(account: account).perform

    expect(other.reload.opt_out_source).to eq('prospecting')
  end

  it 'descadastro de e-mail antigo marca os contatos do mesmo e-mail, sem diferenciar maiúsculas' do
    contact = account.contacts.create!(name: 'Saiu', email: 'Saiu@Exemplo.com.br')
    legacy_unsubscribe('saiu@exemplo.com.br')

    described_class.new(account: account).perform

    expect(contact.reload.opt_out_source).to eq('email_unsubscribe')
  end

  it 'descadastro que só existe no estado novo de supressão também marca' do
    contact = account.contacts.create!(name: 'Saiu', email: 'estado@exemplo.com.br')
    EmailSuppressionState.create!(account: account, email: 'estado@exemplo.com.br', reason: 'unsubscribe', active: true)

    described_class.new(account: account).perform

    expect(contact.reload.opt_out_source).to eq('email_unsubscribe')
  end

  it 'bounce e reclamação não são pedido da pessoa e não marcam' do
    contact = account.contacts.create!(name: 'Bounce', email: 'bounce@exemplo.com.br')
    EmailSuppression.create!(account: account, email: 'bounce@exemplo.com.br', reason: 'hard_bounce', source: 'ses')

    described_class.new(account: account).perform

    expect(contact.reload).not_to be_opted_out
  end

  it 'recusa que o contato já tem fica como está, e rodar de novo não muda nada' do
    admin = create(:user, account: account, role: :administrator)
    contact = account.contacts.create!(name: 'Manual', phone_number: '+5531999970063')
    contact.opt_out!(source: 'manual', by: admin)
    legacy_refused_lead('+5531999970063', contact: contact)

    first = described_class.new(account: account).perform
    second = described_class.new(account: account).perform

    expect(contact.reload.opt_out_source).to eq('manual')
    expect(first).to eq(before: 1, after: 1)
    expect(second).to eq(before: 1, after: 1)
  end

  it 'a recusa de uma conta não marca contato de outra' do
    other_account = create(:account)
    stranger = other_account.contacts.create!(name: 'Outra conta', phone_number: '+5531999970064', email: 'x@exemplo.com.br')
    legacy_refused_lead('+5531999970064')
    legacy_unsubscribe('x@exemplo.com.br')

    described_class.new(account: account).perform

    expect(stranger.reload).not_to be_opted_out
  end

  describe '.accounts_with_legacy_refusals' do
    it 'traz só as contas com lead recusado ou descadastro de e-mail' do
      with_lead = create(:account)
      with_unsubscribe = create(:account)
      create(:account)
      legacy_refused_lead('+5531999970065', target_account: with_lead)
      legacy_unsubscribe('y@exemplo.com.br', target_account: with_unsubscribe)

      expect(described_class.accounts_with_legacy_refusals).to contain_exactly(with_lead, with_unsubscribe)
    end
  end
end
