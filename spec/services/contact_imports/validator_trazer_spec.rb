require 'rails_helper'

# #2896 — "Trazer minha lista" marca a importação de contatos com options['trazer']. Com a marca, a leitura não para
# para perguntar as colunas e a coluna "não guardar" não vira informação da pessoa. Sem a marca (a tela antiga de
# Importar contatos e a automação) nada muda: validator_import_spec.rb e custom_attributes_spec.rb seguem valendo.
RSpec.describe ContactImports::Validator, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:planilha) { "Nome,Celular,Email,Plano,Segredo\nAna,11987650001,,Ouro,abc\nBia,11987650002,bia@exemplo.com.br,Prata,def\n" }

  def importacao(texto = planilha, trazer: {})
    campaign_import = create_contact_import(account: account, user: user, content: texto)
    campaign_import.update!(options: campaign_import.options.merge('trazer' => trazer)) if trazer
    campaign_import
  end

  def lida(...)
    campaign_import = importacao(...)
    described_class.new(campaign_import).perform
    campaign_import.reload
  end

  describe 'colunas que o sistema sugeriu sem certeza' do
    it 'com a marca, aceita a sugestão, segue até ficar pronta e guarda quais colunas são duvidosas' do
      campaign_import = lida

      expect(campaign_import).to have_attributes(status: 'ready_to_confirm', total_rows: 2, valid_rows: 2, invalid_rows: 0)
      expect(campaign_import.schema_resolution).to include('method' => 'deterministic', 'needs_confirmation' => false,
                                                           'uncertain_targets' => %w[name phone email company])
      expect(campaign_import.schema_resolution).not_to have_key('manual_mapping')
      expect(campaign_import.schema_resolution['targets'].transform_values { |alvo| alvo.slice('column', 'source', 'confident') }).to eq(
        'name' => { 'column' => 0, 'source' => 'alias', 'confident' => false },
        'phone' => { 'column' => 1, 'source' => 'alias', 'confident' => false },
        'email' => { 'column' => 2, 'source' => 'alias', 'confident' => false },
        'company' => { 'column' => nil, 'source' => nil, 'confident' => false }
      )
      expect(campaign_import.extra_columns).to eq(%w[Plano Segredo])
      expect(campaign_import.normalized_csv).to be_attached
    end

    it 'sem a marca, para e pergunta as colunas como sempre' do
      campaign_import = lida(trazer: nil)

      expect(campaign_import).to be_needs_column_choice
      expect(campaign_import.schema_resolution).to include('method' => 'deterministic', 'needs_confirmation' => true)
      expect(campaign_import.campaign_import_rows).to be_empty
    end

    it 'com a marca e sem coluna de telefone nem de e-mail, falha dizendo que falta a coluna de contato' do
      campaign_import = lida("Nome,Cidade\nAna,Campinas\nBia,Santos\n")

      expect(campaign_import).to be_validation_failed
      expect(campaign_import.validation_summary['errors']).to eq('missing_contact_column' => 1)
      expect(campaign_import.campaign_import_rows).to be_empty
    end

    it 'sem a marca, a planilha sem coluna de contato continua pedindo as colunas' do
      expect(lida("Nome,Cidade\nAna,Campinas\nBia,Santos\n", trazer: nil)).to be_needs_column_choice
    end

    it 'com a marca e as colunas achadas com certeza, não há coluna duvidosa' do
      enable_audience_jev
      stub_audience_jev(phone: 'column_1', email: 'column_2', name: 'column_0', company: 'none')

      campaign_import = lida

      expect(campaign_import).to be_ready_to_confirm
      expect(campaign_import.schema_resolution).to include('method' => 'jev', 'needs_confirmation' => false, 'uncertain_targets' => [])
    end
  end

  describe 'coluna que a pessoa mandou não guardar' do
    it 'com a marca, não guarda o valor na linha, não o mostra no resumo, não o grava nem cria a informação' do
      campaign_import = lida(trazer: { 'destinos' => { '4' => 'nao_guardar' } })

      expect(campaign_import.extra_columns).to eq(%w[Plano Segredo])
      expect(campaign_import.campaign_import_rows.order(:row_number).pluck(:extra_values)).to eq([{ 'Plano' => 'Ouro' }, { 'Plano' => 'Prata' }])
      expect(campaign_import.validation_summary['contact_attributes'].pluck('column')).to eq(['Plano'])

      import_contacts!(campaign_import)

      expect(campaign_import).to be_completed
      expect(account.contacts.order(:name).pluck(:name, :custom_attributes)).to eq([['Ana', { 'plano' => 'Ouro' }], ['Bia', { 'plano' => 'Prata' }]])
      expect(account.custom_attribute_definitions.pluck(:attribute_key)).to eq(['plano'])
      expect(campaign_import.validation_summary['contact_attributes_created']).to eq(1)
    end

    it 'com a marca, a coluna com tipo que não será guardada não entra na conta dos valores que não servem' do
      account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'segredo',
                                                   attribute_display_name: 'Segredo', attribute_display_type: :number)

      expect(lida.validation_summary['attribute_problems']).to include('count' => 2, 'by_attribute' => { 'Segredo' => 2 })
      expect(lida(trazer: { 'destinos' => { '4' => 'nao_guardar' } }).validation_summary['attribute_problems'])
        .to include('count' => 0, 'by_attribute' => {})
    end

    it 'com a marca e sem coluna marcada, guarda todas as colunas extras' do
      campaign_import = lida

      expect(campaign_import.campaign_import_rows.order(:row_number).pluck(:extra_values))
        .to eq([{ 'Plano' => 'Ouro', 'Segredo' => 'abc' }, { 'Plano' => 'Prata', 'Segredo' => 'def' }])

      import_contacts!(campaign_import)

      expect(account.contacts.order(:name).pluck(:custom_attributes))
        .to eq([{ 'plano' => 'Ouro', 'segredo' => 'abc' }, { 'plano' => 'Prata', 'segredo' => 'def' }])
      expect(account.custom_attribute_definitions.pluck(:attribute_key)).to match_array(%w[plano segredo])
    end

    it 'sem a marca, guarda todas as colunas extras como sempre' do
      campaign_import = importacao(trazer: nil)
      validate_contact_import(campaign_import, { 'name' => 0, 'phone' => 1, 'email' => 2, 'company' => nil })

      import_contacts!(campaign_import)

      expect(account.contacts.order(:name).pluck(:custom_attributes))
        .to eq([{ 'plano' => 'Ouro', 'segredo' => 'abc' }, { 'plano' => 'Prata', 'segredo' => 'def' }])
    end
  end

  describe 'DDD numa coluna separada' do
    it 'junta o DDD ao número antes de ler, e a coluna do DDD não vira informação' do
      campaign_import = lida("Nome,DDD,Celular,Idade\nAna,11,98765-0001,21\nBia,(21),987650002,35\nCaio,20,987650003,40\n")

      expect(campaign_import).to have_attributes(status: 'ready_to_confirm', valid_rows: 2, invalid_rows: 1)
      expect(campaign_import.schema_resolution['columns'].pluck('header')).to eq(%w[Nome Celular Idade])
      expect(campaign_import.extra_columns).to eq(['Idade'])
      expect(campaign_import.validation_summary).to include('ddd_juntado' => 2)
      expect(CampaignImports::NormalizedRows.new(campaign_import).perform.pluck(:phone_number)).to eq(%w[+5511987650001 +5521987650002])
      # O DDD 20 não existe: a linha segue sem DDD e vira problema de telefone.
      expect(campaign_import.campaign_import_rows.find_by!(row_number: 4).error_messages).to eq(['invalid_brazilian_mobile_number'])
    end

    it 'sem a marca, a planilha é lida como sempre: o DDD continua numa coluna à parte' do
      campaign_import = importacao("Nome,DDD,Celular\nAna,11,98765-0001\n", trazer: nil)
      validate_contact_import(campaign_import, { 'name' => 0, 'phone' => 2, 'email' => nil, 'company' => nil })

      expect(campaign_import).to be_validation_failed
      expect(campaign_import.extra_columns).to eq(['DDD'])
    end
  end

  describe 'a mesma pessoa em várias linhas' do
    let(:repetidas) do
      <<~CSV
        Nome,Celular,Email,Empresa,Plano
        Ana Albuquerino,11987650001,,,Ouro
        ana albuquerino,(11) 98765-0001,ANA@exemplo.com.br,Padaria Bom Dia,
        Bia Brandolim,11987650002,bia@exemplo.com.br,,
        Beatriz Outra,11987650009,BIA@exemplo.com.br,,
        Ana Albuquerino,11987650007,,,
      CSV
    end

    it 'junta numa linha só as linhas sem conflito e completa a primeira com o que só a outra tinha' do
      campaign_import = lida(repetidas)

      expect(campaign_import).to have_attributes(status: 'ready_to_confirm', total_rows: 4, valid_rows: 3, invalid_rows: 1)
      expect(campaign_import.validation_summary).to include('mesma_pessoa' => 1)
      expect(campaign_import.campaign_import_rows.order(:row_number).pluck(:row_number, :status, :company_name, :extra_values)).to eq(
        [[2, 'valid', 'Padaria Bom Dia', { 'Plano' => 'Ouro' }], [4, 'valid', nil, {}], [5, 'invalid', nil, {}], [6, 'valid', nil, {}]]
      )
      conferidas = CampaignImports::NormalizedRows.new(campaign_import).perform.map { |linha| linha.slice(:row_number, :name, :phone_number, :email) }
      expect(conferidas).to eq(
        [{ row_number: 2, name: 'Ana Albuquerino', phone_number: '+5511987650001', email: 'ana@exemplo.com.br' },
         { row_number: 4, name: 'Bia Brandolim', phone_number: '+5511987650002', email: 'bia@exemplo.com.br' },
         # Nome igual não junta ninguém: a Ana de outro telefone é outra pessoa.
         { row_number: 6, name: 'Ana Albuquerino', phone_number: '+5511987650007', email: nil }]
      )
    end

    it 'com dado em conflito, a segunda linha vira problema de linha repetida e guarda as células das duas' do
      campaign_import = lida(repetidas)

      expect(campaign_import.campaign_import_rows.find_by!(row_number: 5).error_messages).to eq(['duplicate_email_in_file'])
      gravadas = campaign_import.linhas_com_problema.download.force_encoding(Encoding::UTF_8).lines.map { |linha| JSON.parse(linha) }
      expect(gravadas).to eq(
        [{ 'linha' => 5, 'celulas' => { 'name' => 'Beatriz Outra', 'phone' => '11987650009', 'email' => 'BIA@exemplo.com.br', 'company' => '' },
           'outra' => { 'linha' => 4,
                        'celulas' => { 'name' => 'Bia Brandolim', 'phone' => '11987650002', 'email' => 'bia@exemplo.com.br', 'company' => '' } } }]
      )
    end

    it 'grava uma pessoa só para as linhas juntadas, com os dados das duas' do
      campaign_import = lida(repetidas)

      import_contacts!(campaign_import)

      expect(account.contacts.where(phone_number: '+5511987650001').sole).to have_attributes(
        name: 'Ana Albuquerino', email: 'ana@exemplo.com.br', custom_attributes: { 'plano' => 'Ouro' }
      )
      expect(account.contacts.count).to eq(3)
    end
  end

  describe 'linha sem nome' do
    it 'vira problema de nome quando a planilha tem coluna de nome, e a linha com o mesmo contato e nome a completa' do
      campaign_import = lida("Nome,Celular,Email\n,11987650001,\n,11987650002,\nBia Brandolim,11987650002,bia@exemplo.com.br\n")

      expect(campaign_import).to have_attributes(status: 'ready_to_confirm', total_rows: 2, valid_rows: 1, invalid_rows: 1)
      expect(campaign_import.campaign_import_rows.order(:row_number).pluck(:row_number, :status, :error_messages, :raw_name)).to eq(
        [[2, 'invalid', ['blank_name'], ''], [3, 'valid', [], 'Bia Brandolim']]
      )
      problema = Relacionamentos::Trazer::Leitura.new(campaign_import).call[:problemas].sole
      expect(problema).to eq(linha: 2, tipo: 'nome', nome: '', valor: '', estado: 'aberto', contato: '11987650001', motivo: 'blank_name')
    end

    it 'continua entrando sem nome quando a planilha não tem coluna de nome' do
      campaign_import = lida("Celular,Email\n11987650001,\n")

      expect(campaign_import).to have_attributes(status: 'ready_to_confirm', valid_rows: 1, invalid_rows: 0)
    end

    it 'sem a marca, a linha sem nome entra como sempre' do
      campaign_import = importacao("Nome,Celular\n,11987650001\n", trazer: nil)
      validate_contact_import(campaign_import, { 'name' => 0, 'phone' => 1, 'email' => nil, 'company' => nil })

      expect(campaign_import).to have_attributes(status: 'ready_to_confirm', valid_rows: 1, invalid_rows: 0)
    end
  end
end
