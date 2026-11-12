require 'rails_helper'

# #2896 — "Trazer minha lista" na hora de gravar: para onde vai cada coluna que a pessoa mandou para fora das
# informações (cidade, telefone da empresa, cliente), a resposta "sim, todas são clientes" e a informação com nome e
# "para que serve". Quem já existia é completado, nunca sobrescrito. Sem a marca nada muda: custom_attributes_spec.rb.
RSpec.describe ContactImports::CustomAttributes, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  # Colunas: 0 Nome, 1 Celular, 2 Empresa, 3 Cidade, 4 Cliente?, 5 Fone 2, 6 Plano.
  let(:planilha) do
    <<~CSV
      Nome,Celular,Empresa,Cidade,Cliente?,Fone 2,Plano
      Ana Albuquerino,11987650001,Padaria Bom Dia,Campinas,Sim,1133330001,Ouro
      Bruno Brandolim,11987650002,,Santos,não,,Prata
      Carla Carvalhedo,11987650003,Mercado Sol,,X,1133330003,
      Davi Dornelino,11987650004,,Recife,CLIENTE,,
    CSV
  end
  let(:destinos) { { '3' => 'cidade', '4' => 'cliente', '5' => 'telefone_da_empresa' } }

  # Quem é cliente é a pessoa que diz, escolhendo os valores da coluna: aqui, "Sim", "X" e "CLIENTE". A chave de cada
  # valor é da importação e da coluna (4, "Cliente?").
  def escolha(campaign_import)
    { 'modo' => 'valores', 'chaves' => %w[sim x cliente].map { |valor| ContactImports::Trazer::Cliente.chave(campaign_import.id, 4, valor) } }
  end

  before { account.enable_features!('companies') }

  # trazer: as marcas da conferência, ou um bloco que as monta com a importação já criada.
  def trazida(trazer, texto = planilha)
    campaign_import = create_contact_import(account: account, user: user, content: texto)
    trazer = trazer.call(campaign_import) if trazer.respond_to?(:call)
    campaign_import.update!(options: campaign_import.options.merge('trazer' => trazer))
    ContactImports::Validator.new(campaign_import).perform
    import_contacts!(campaign_import)
  end

  def pessoa(nome)
    account.contacts.find_by!(name: nome)
  end

  it 'leva a cidade, o telefone da empresa e o cliente para o lugar certo, sem criar informação para essas colunas' do
    freeze_time do
      campaign_import = trazida(->(importacao) { { 'destinos' => destinos, 'respostas' => { 'valores_cliente' => escolha(importacao) } } })

      expect(campaign_import).to be_completed
      expect(account.contacts.order(:name).map { |contato| [contato.name, contato.additional_attributes['city'], contato.customer?] }).to eq(
        [['Ana Albuquerino', 'Campinas', true], ['Bruno Brandolim', 'Santos', false], ['Carla Carvalhedo', nil, true],
         ['Davi Dornelino', 'Recife', true]]
      )
      expect(pessoa('Ana Albuquerino')).to have_attributes(customer_since: Time.current, custom_attributes: { 'plano' => 'Ouro' })
      expect(pessoa('Bruno Brandolim')).to have_attributes(contact_type: 'lead', customer_since: nil, custom_attributes: { 'plano' => 'Prata' })
      expect(account.companies.order(:name).map { |empresa| [empresa.name, empresa.additional_attributes['phone_number']] })
        .to eq([['Mercado Sol', '1133330003'], ['Padaria Bom Dia', '1133330001']])
      expect(account.custom_attribute_definitions.pluck(:attribute_key)).to eq(['plano'])
      expect(campaign_import.validation_summary['contact_attributes'].pluck('column')).to eq(['Plano'])
    end
  end

  it 'completa quem já existia e nunca sobrescreve: cidade, telefone da empresa e a data de cliente ficam como estavam' do
    desde = Time.zone.parse('2024-03-10 12:00')
    padaria = account.companies.create!(name: 'Padaria Bom Dia', additional_attributes: { 'phone_number' => '1133330009' })
    ana = create(:contact, account: account, name: 'Ana A.', phone_number: '+5511987650001', company: padaria,
                           additional_attributes: { 'city' => 'Sorocaba' }, contact_type: :customer, customer_since: desde)
    bruno = create(:contact, account: account, name: 'Bruno B.', phone_number: '+5511987650002', additional_attributes: { 'country' => 'BR' })

    trazida('destinos' => destinos, 'respostas' => { 'clientes' => 'sim_todas' })

    expect(ana.reload).to have_attributes(name: 'Ana A.', customer_since: desde, contact_type: 'customer')
    expect(ana.additional_attributes).to include('city' => 'Sorocaba')
    expect(padaria.reload.additional_attributes).to eq('phone_number' => '1133330009')
    # O Bruno já existia sem cidade e sem ser cliente: ganha os dois, e o que tinha fica.
    expect(bruno.reload).to have_attributes(name: 'Bruno B.', contact_type: 'customer')
    expect(bruno.additional_attributes).to include('city' => 'Santos', 'country' => 'BR')
    expect(bruno.customer_since).to be_present
  end

  it '"sim, todas" marca todo mundo da lista, com ou sem coluna de cliente' do
    trazida('respostas' => { 'clientes' => 'sim_todas' })

    expect(account.contacts.pluck(:contact_type).uniq).to eq(['customer'])
    # Sem destino escolhido, as colunas continuam virando informação da pessoa.
    expect(pessoa('Ana Albuquerino').custom_attributes).to eq('cidade' => 'Campinas', 'cliente' => 'Sim', 'fone_2' => '1133330001', 'plano' => 'Ouro')
  end

  it 'sem resposta e sem coluna de cliente, ninguém vira cliente' do
    trazida({})

    expect(account.contacts.pluck(:contact_type).uniq).to eq(['lead'])
  end

  it 'cria a informação com o nome e o "para que serve" que a pessoa escreveu' do
    trazida('destinos' => destinos, 'campos' => { '6' => { 'nome' => 'Plano contratado', 'para_que_serve' => 'O plano que a pessoa paga hoje' } })

    expect(account.custom_attribute_definitions.sole).to have_attributes(
      attribute_key: 'plano_contratado', attribute_display_name: 'Plano contratado', attribute_description: 'O plano que a pessoa paga hoje',
      attribute_display_type: 'text'
    )
    expect(pessoa('Ana Albuquerino').custom_attributes).to eq('plano_contratado' => 'Ouro')
  end

  it 'usa a informação que a conta já tem quando o nome escrito é o dela, sem mudar a descrição' do
    account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'nivel', attribute_display_name: 'Nível',
                                                 attribute_display_type: :text, attribute_description: 'Como a conta chama o plano')

    trazida('destinos' => destinos, 'campos' => { '6' => { 'nome' => 'nivel', 'para_que_serve' => 'Outra descrição' } })

    expect(account.custom_attribute_definitions.sole).to have_attributes(attribute_key: 'nivel', attribute_description: 'Como a conta chama o plano')
    expect(pessoa('Bruno Brandolim').custom_attributes).to eq('nivel' => 'Prata')
  end

  it 'a coluna que não é para guardar não cria informação nem valor' do
    trazida('destinos' => destinos.merge('6' => 'nao_guardar'))

    expect(account.custom_attribute_definitions).to be_empty
    expect(account.contacts.pluck(:custom_attributes).uniq).to eq([{}])
  end

  it 'a coluna "cliente" não marca ninguém sem a pessoa escolher os valores: o código não interpreta a célula' do
    trazida('destinos' => destinos)

    expect(account.contacts.pluck(:contact_type).uniq).to eq(['lead'])
    expect(account.custom_attribute_definitions.pluck(:attribute_key)).to eq(['plano'])
  end

  it '"toda linha com algo escrito" marca quem tem a célula preenchida, diga ela o que disser' do
    trazida({ 'destinos' => destinos, 'respostas' => { 'valores_cliente' => { 'modo' => 'preenchidas' } } },
            planilha.sub('Davi Dornelino,11987650004,,Recife,CLIENTE,,', 'Davi Dornelino,11987650004,,Recife,,,'))

    expect(account.contacts.order(:name).map { |contato| [contato.name, contato.customer?] }).to eq(
      [['Ana Albuquerino', true], ['Bruno Brandolim', true], ['Carla Carvalhedo', true], ['Davi Dornelino', false]]
    )
  end

  # Rodada 5: quem aplica os destinos é o importador, depois das informações. "Sim, todas" não depende de a linha ter
  # alguma coluna além das de contato.
  it '"sim, todas são clientes" vale numa planilha sem nenhuma coluna além das de contato' do
    freeze_time do
      trazida({ 'respostas' => { 'clientes' => 'sim_todas' } }, "Nome,Celular\nAna Albuquerino,11987650001\nBruno Brandolim,11987650002\n")

      expect(account.contacts.order(:name).map { |contato| [contato.name, contato.customer?, contato.customer_since] }).to eq(
        [['Ana Albuquerino', true, Time.current], ['Bruno Brandolim', true, Time.current]]
      )
      expect(account.custom_attribute_definitions).to be_empty
    end
  end

  it 'o gravador das informações não aplica mais os destinos: recebe só a pessoa e os valores da linha' do
    expect(described_class.instance_method(:merge!).parameters).to eq([%i[req contact], %i[req extra_values]])
  end

  # M1: o telefone da empresa só vai para a empresa da linha.
  describe 'telefone da empresa do contato que já tinha outra empresa' do
    let(:outra) { create(:company, account: account, name: 'Outra Empresa') }

    it 'não é gravado na empresa que o contato já tinha e que não é a da linha' do
      create(:contact, account: account, name: 'Ana A.', phone_number: '+5511987650001', email: nil, company: outra)

      trazida({ 'destinos' => destinos })

      expect(outra.reload.additional_attributes.to_h['phone_number']).to be_blank
      expect(account.companies.find_by!(name: 'Mercado Sol').additional_attributes['phone_number']).to eq('1133330003')
    end

    it 'não é gravado quando a célula da empresa veio vazia, mesmo com o contato já ligado a uma empresa' do
      create(:contact, account: account, name: 'Bruno B.', phone_number: '+5511987650002', email: nil, company: outra)

      trazida({ 'destinos' => destinos }, planilha.sub('Santos,não,,Prata', 'Santos,não,1133330002,Prata'))

      expect(outra.reload.additional_attributes.to_h['phone_number']).to be_blank
    end
  end
end
