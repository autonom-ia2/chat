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
end
