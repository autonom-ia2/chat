require 'rails_helper'

# #2896 (fatia 3) — o que a gravação de "Trazer minha lista" anota de cada linha, para o "Desfazer" devolver só isso: os
# campos que a lista preencheu em quem a conta já tinha, com o resumo com segredo do valor e nunca o valor. De quem a
# lista criou, só o resumo da pessoa inteira, para o Desfazer saber se alguém a editou depois.
RSpec.describe Relacionamentos::Trazer::CamposPreenchidos, :aggregate_failures do
  include_context 'with lista trazida'

  let(:campos) { Relacionamentos::CampoPreenchido }

  it 'anota cada campo que a lista preencheu em quem a conta já tinha, e de quem ela criou só o resumo da pessoa inteira' do
    importacao = trazer_lista

    expect(importacao).to be_completed
    expect(anotados(ana)).to match_array(%w[email cidade informacao:plano empresa cliente telefone_da_empresa])
    expect(anotados(bruno)).to match_array(%w[nome telefone cidade informacao:plano cliente])
    # A Carla nasceu com a lista: dela nenhum campo é anotado, só o resumo dela inteira. O telefone da empresa fica na
    # empresa da linha, não nela.
    expect(anotados(pessoa('Carla Carvalhedo'))).to match_array(%w[pessoa_criada telefone_da_empresa])
    expect(campos.pluck(:account_id).uniq).to eq([account.id])
    expect(campos.where(contact_id: ana.id).pluck(:campaign_import_row_id).uniq).to eq([importacao.campaign_import_rows.find_by!(row_number: 2).id])
    expect(campos.where.not(devolvido_em: nil)).to be_empty
  end

  it 'guarda o resumo com segredo do valor: nunca o valor, nunca um hash puro, e diferente em cada linha e em cada campo' do
    trazer_lista

    guardado = campos.all.flat_map { |campo| campo.attributes.values.map(&:to_s) }.join(' ')
    %w[ana.albuquerino 11987650002 1133330001 1133330003 Campinas Santos Ouro Prata Brandolim].each do |valor|
      expect(guardado).not_to include(valor)
    end

    email = campos.find_by!(contact_id: ana.id, campo: 'email')
    valor = 'ana.albuquerino@exemplo.com.br'
    expect(email.valor_posto_hash).to eq(campos.resumo(email.campaign_import_row_id, 'email', valor))
    expect(email.valor_posto_hash.size).to eq(64)
    expect(email.valor_posto_hash).not_to eq(Digest::SHA256.hexdigest(valor))
    expect(campos.resumo(email.campaign_import_row_id + 1, 'email', valor)).not_to eq(email.valor_posto_hash)
    expect(campos.resumo(email.campaign_import_row_id, 'nome', valor)).not_to eq(email.valor_posto_hash)
    expect([email.mesmo_valor?(valor), email.mesmo_valor?('outra@exemplo.com.br'), email.mesmo_valor?(nil)]).to eq([true, false, false])
  end

  it 'o resumo de quem a lista criou é o da pessoa como a linha a deixou: quem não foi editada sai, quem foi fica' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    criada = Relacionamentos::Trazer::PessoaCriada.new(importacao)
    expect(criada.editadas([carla.id, ana.id, bruno.id])).to be_empty

    carla.update!(name: 'Carla C.')

    expect(criada.editadas([carla.id, ana.id, bruno.id])).to contain_exactly(carla.id)
    guardado = campos.find_by!(contact_id: carla.id, campo: 'pessoa_criada').attributes.values.join(' ')
    expect(guardado).not_to include('Carvalhedo')
    expect(guardado).not_to include('11987650003')
  end

  it 'refaz o resumo de quem a lista criou quando uma linha de baixo a completa: foi a lista que mexeu, não alguém' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    # Uma linha de baixo da mesma lista acha a Carla e põe o e-mail que faltava (CampaignImports::ContactRow#write).
    de_baixo = importacao.campaign_import_rows.create!(row_number: 9, status: :imported, contact_id: carla.id, was_existing_contact: true)
    carla.update!(email: 'carla.carvalhedo@exemplo.com.br')
    gravada = CampaignImports::ContactRow::Result.new(contact: carla, existing: true, company: nil, filled: [:email])

    described_class.new(importacao).registrar(de_baixo, gravada, {}, ContactImports::Trazer::DestinosDaLinha::Postos.new)

    expect(anotados(carla)).to match_array(%w[pessoa_criada telefone_da_empresa email])
    expect(Relacionamentos::Trazer::PessoaCriada.new(importacao).editadas([carla.id])).to be_empty
    expect(Relacionamentos::Trazer::PreviaDoDesfazer.new(importacao).call).to include(tira: 1, ficam: 0)
  end

  it 'anota a marca de cliente só de quem a lista promoveu, com a data gravada e o tipo que a pessoa tinha' do
    ana.update!(contact_type: :customer, customer_since: Time.zone.parse('2024-03-10 12:00'))

    trazer_lista

    # A Ana já era cliente: a lista não mexe nela e não anota. O Bruno era lead e virou cliente.
    expect(anotados(ana)).not_to include('cliente')
    cliente = campos.find_by!(contact_id: bruno.id, campo: 'cliente')
    expect(cliente.tipo_anterior).to eq(Contact.contact_types['lead'])
    expect(cliente.mesmo_valor?(bruno.reload.customer_since.utc.iso8601(6))).to be(true)
    expect(campos.where.not(campo: 'cliente').pluck(:tipo_anterior).uniq).to eq([nil])
  end

  it 'não anota nada da importação que não nasceu em "Trazer minha lista"' do
    importacao = importar_pela_tela_antiga("Nome,Celular,E-mail\nAna Albuquerino,11987650001,ana.albuquerino@exemplo.com.br\n")

    expect(importacao).to be_completed
    expect(ana.reload.email).to eq('ana.albuquerino@exemplo.com.br')
    expect(campos.count).to eq(0)
  end
end
