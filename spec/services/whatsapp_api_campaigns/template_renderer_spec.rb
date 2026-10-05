require 'rails_helper'

RSpec.describe WhatsappApiCampaigns::TemplateRenderer do
  it 'renders the two supported contact variables' do
    contact = Contact.new(name: 'Ana Maria')

    rendered = described_class.new(
      template: 'Olá {{contact.first_name}} de {{ contact.name }}',
      contact: contact
    ).render

    expect(rendered).to eq('Olá Ana de Ana Maria')
  end

  # #999 D7: the company token; values go in one pass and are never read again as tokens.
  it 'renders the company and never re-reads an inserted value as a token' do
    contact = Contact.new(name: '{{contact.first_name}} Ana', additional_attributes: { 'company_name' => "Alfa\nCorretora" })

    rendered = described_class.new(template: "{{contact.name}} | {{ contact.company }} | {{contact.first_name}}\n", contact: contact).render

    expect(rendered).to eq("{{contact.first_name}} Ana | Alfa Corretora | {{contact.first_name}}\n")
    expect(described_class.unsupported_variables_in('{{contact.company}} {{ }} {{x')).to eq([])
  end

  it 'falls back to the default company text given by the campaign' do
    rendered = described_class.new(template: 'da {{contact.company}}', contact: Contact.new(name: 'Bia'),
                                   variables: { 'contact.company' => 'sua empresa' }).render

    expect(rendered).to eq('da sua empresa')
  end

  it 'detects unsupported variables' do
    unsupported = described_class.unsupported_variables_in('Olá {{contact.email}} {{ contact.name }}')

    expect(unsupported).to eq(['contact.email'])
  end
end
