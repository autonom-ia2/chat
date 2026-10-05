require 'rails_helper'

# #1000 — caso real da conta 16: o e-mail "Novo lead Chat2You" chega, a plataforma cria o contato
# (nome = começo do e-mail) e a empresa (nome = domínio), e a automação atualiza os dois com o que veio
# no corpo do e-mail.
RSpec.describe Autonomia::Decisores::Aplicador do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:empresa_do_dominio) { Company.create!(account_id: account.id, name: 'Vidadeouro', domain: 'vidadeouro.com.br') }
  let(:contact) do
    create(:contact, account: account, name: 'novafriburgo', email: 'novafriburgo@vidadeouro.com.br').tap do |contato|
      contato.update!(company: empresa_do_dominio)
    end
  end
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:campos) do
    [{ chave: 'nome', descricao: 'Nome', destino: 'contato.nome', trocar: true },
     { chave: 'corretora', descricao: 'Corretora', destino: 'empresa.nome', trocar: true },
     { chave: 'cargo', descricao: 'Cargo', destino: 'contato.cargo', trocar: true },
     { chave: 'whatsapp', descricao: 'WhatsApp', destino: 'contato.telefone', trocar: true },
     { chave: 'bio', descricao: 'Equipe, desafio e origem', destino: 'contato.biografia', trocar: true }]
  end
  let(:decisor) { create(:autonomia_decisor, account: account, campos: campos) }
  let(:valores) do
    { 'nome' => 'roberto louback', 'corretora' => 'Vida de ouro Nova friburgo', 'cargo' => 'socio',
      'whatsapp' => '22974049400', 'bio' => 'Equipe: 1 a 3 pessoas. Desafio: conforme conversamos no congresso.' }
  end

  def aplicar(lista = campos, entrada = valores)
    decisor.update!(campos: lista)
    described_class.new(decisor: decisor, conversation: conversation).aplicar(entrada)
  end

  it 'atualiza contato e empresa com o que veio no e-mail' do
    resultado = aplicar

    contact.reload
    expect(contact).to have_attributes(name: 'roberto louback', phone_number: '+5522974049400')
    expect(contact.custom_attributes).to include('job_title' => 'socio')
    expect(contact.additional_attributes).to include('description' => valores['bio'])
    expect(contact.company.reload).to have_attributes(id: empresa_do_dominio.id, name: 'Vida de ouro Nova friburgo',
                                                      domain: 'vidadeouro.com.br')
    expect(resultado.aplicados.keys).to contain_exactly('nome', 'corretora', 'cargo', 'whatsapp', 'bio')
    expect(resultado.recusados).to be_empty
  end

  it 'sem trocar, só preenche o vazio e diz por que não gravou' do
    contact.update!(name: 'Roberto L.', custom_attributes: { 'job_title' => 'diretor' })
    resultado = aplicar(campos.map { |campo| campo.except(:trocar) })

    expect(contact.reload).to have_attributes(name: 'Roberto L.', phone_number: '+5522974049400')
    expect(contact.custom_attributes['job_title']).to eq('diretor')
    expect(contact.company.reload.name).to eq('Vidadeouro')
    expect(resultado.recusados).to include('nome' => 'já tinha valor', 'cargo' => 'já tinha valor', 'corretora' => 'já tinha empresa')
  end

  it 'empresa com outros contatos não é renomeada: o contato passa para a empresa do nome novo' do
    create(:contact, account: account, email: 'outra@vidadeouro.com.br').update!(company: empresa_do_dominio)

    aplicar

    expect(empresa_do_dominio.reload.name).to eq('Vidadeouro')
    expect(contact.reload.company.name).to eq('Vida de ouro Nova friburgo')
  end

  it 'aceita o telefone escrito de vários jeitos e completa o país pela conta' do
    ['(22) 97404-9400', '+55 22 97404-9400', '5522974049400'].each do |escrito|
      contact.update!(phone_number: nil)
      aplicar(campos.values_at(3), 'whatsapp' => escrito)
      expect(contact.reload.phone_number).to eq('+5522974049400'), escrito
    end
  end

  it 'telefone de outro contato não grava: vai para a biografia e o motivo fica no resultado' do
    outro = create(:contact, account: account, phone_number: '+5522974049400')
    resultado = aplicar(campos.values_at(3))

    expect(contact.reload.phone_number).to be_nil
    expect(contact.additional_attributes['description']).to include('+5522974049400', "##{outro.id}")
    expect(resultado.recusados['whatsapp']).to include("contato ##{outro.id}")
  end

  it 'telefone sem jeito de número é recusado com o motivo' do
    resultado = aplicar(campos.values_at(3), 'whatsapp' => 'ligar à tarde')

    expect(resultado.recusados['whatsapp']).to include('fora do formato')
  end

  it 'nunca troca o e-mail do contato, mesmo com trocar' do
    resultado = aplicar([{ chave: 'email', descricao: 'E-mail', destino: 'contato.email', trocar: true }],
                        'email' => 'roberto@outro.com')

    expect(contact.reload.email).to eq('novafriburgo@vidadeouro.com.br')
    expect(resultado.recusados).to eq('email' => 'já tinha valor')
  end
end
