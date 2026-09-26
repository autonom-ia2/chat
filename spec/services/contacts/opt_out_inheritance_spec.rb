require 'rails_helper'

# chat#713: a recusa é da pessoa do número ou do e-mail, não do registro. Contato que nasce depois (mensagem no inbox,
# importação, criação manual, API) ou que passa a ter o telefone ou o e-mail de quem recusou herda a recusa.
RSpec.describe Contacts::OptOutInheritance do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }

  def refuse_by_prospecting(phone, target_account: account)
    Autonomia::Prospecting::Lead.create!(
      account: target_account, provider: 'mock', provider_place_id: "heranca-#{phone}", name: 'Lead recusado', phone: phone,
      country: 'BR', status: :no_consent
    )
  end

  def unsubscribe(email)
    EmailCampaigns::SuppressionRegistry.new(account: account, email: email)
                                       .block!(reason: 'unsubscribe', source: 'link', event_key: "unsubscribe:#{email}")
  end

  def inheriting(&)
    perform_enqueued_jobs(only: Contacts::OptOutInheritanceJob, &)
  end

  it 'contato criado depois com o telefone de um lead recusado nasce com a recusa da Prospecção' do
    refuse_by_prospecting('+5531999997002')

    contact = inheriting { account.contacts.create!(name: 'Escreveu no inbox', phone_number: '+5531999997002') }

    expect(contact.reload).to be_opted_out
    expect(contact.opt_out_source).to eq('prospecting')
  end

  it 'contato criado depois com um e-mail descadastrado nasce com a recusa do descadastro' do
    unsubscribe('saiu@exemplo.com.br')

    contact = inheriting { account.contacts.create!(name: 'Novo', email: 'Saiu@Exemplo.com.br') }

    expect(contact.reload.opt_out_source).to eq('email_unsubscribe')
  end

  it 'contato que passa a ter o telefone recusado herda a recusa' do
    refuse_by_prospecting('+5531999997010')
    contact = account.contacts.create!(name: 'Antes', phone_number: '+5531999997011')

    inheriting { contact.update!(phone_number: '+5531999997010') }

    expect(contact.reload.opt_out_source).to eq('prospecting')
  end

  it 'contato sem relação com a recusa da conta não é marcado' do
    refuse_by_prospecting('+5531999997020')

    contact = inheriting { account.contacts.create!(name: 'Outro', phone_number: '+5531999997021') }

    expect(contact.reload).not_to be_opted_out
  end

  it 'conta sem recusa nenhuma não enfileira nada' do
    expect { account.contacts.create!(name: 'Comum', phone_number: '+5531999997030', email: 'comum@exemplo.com.br') }
      .not_to have_enqueued_job(Contacts::OptOutInheritanceJob)
  end

  it 'recusa de outra conta não vale' do
    refuse_by_prospecting('+5531999997040', target_account: create(:account))

    contact = inheriting { account.contacts.create!(name: 'Mesmo número', phone_number: '+5531999997040') }

    expect(contact.reload).not_to be_opted_out
  end

  it 'contato importado por CSV com o telefone recusado herda a recusa' do
    refuse_by_prospecting('+5531999997050')
    csv = "name,phone_number,email\nImportado,+5531999997050,importado@exemplo.com.br\n"
    import_file = Rack::Test::UploadedFile.new(StringIO.new(csv), 'text/csv', original_filename: 'contatos.csv')
    data_import = create(:data_import, account: account, import_file: import_file)

    inheriting { DataImportJob.perform_now(data_import) }

    expect(account.contacts.find_by!(phone_number: '+5531999997050').opt_out_source).to eq('prospecting')
  end
end
