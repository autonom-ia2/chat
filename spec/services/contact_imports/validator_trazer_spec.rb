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

  # O DDD em outra coluna não é juntado ao número (#3010): decidir pelo título qual coluna é o DDD seria adivinhar o que
  # a pessoa escreveu. O que não dá para usar aparece: a linha vira problema, ou a leitura falha dizendo por quê.
  describe 'DDD numa coluna separada' do
    it 'não é juntado: o número sem DDD vira problema de telefone e a coluna do DDD fica como qualquer outra' do
      campaign_import = lida("Nome,DDD,Celular,Idade\nAna,11,98765-0001,21\nBia,21,(21) 98765-0002,35\n")

      expect(campaign_import).to have_attributes(status: 'ready_to_confirm', valid_rows: 1, invalid_rows: 1)
      expect(campaign_import.schema_resolution['columns'].pluck('header')).to eq(%w[Nome DDD Celular Idade])
      expect(campaign_import.extra_columns).to eq(%w[DDD Idade])
      expect(campaign_import.validation_summary).not_to have_key('ddd_juntado')
      expect(CampaignImports::NormalizedRows.new(campaign_import).perform.pluck(:phone_number)).to eq(%w[+5521987650002])
      expect(campaign_import.campaign_import_rows.find_by!(row_number: 2).error_messages).to eq(['invalid_brazilian_mobile_number'])
      expect(Relacionamentos::Trazer::Leitura.new(campaign_import).call[:problemas].sole).to include(linha: 2, tipo: 'telefone', estado: 'aberto')
    end

    it 'quando nenhuma linha tem o DDD junto do número, a leitura falha e a tela recebe o motivo' do
      campaign_import = lida("Nome,DDD,Celular\nAna,11,98765-0001\nBia,21,987650002\n")

      expect(campaign_import).to be_validation_failed
      expect(campaign_import.validation_summary['errors'].keys).to include('no_valid_rows')
      expect(Relacionamentos::Trazer::Leitura.new(campaign_import).call).to eq(id: campaign_import.id, situacao: 'falhou', erro: 'sem_contato')
    end

    # Com e-mail bom, a linha entra só com o e-mail (regra da leitura de planilhas, que não muda). Quem entra assim é
    # contado para a tela avisar (ContactImports::Trazer::QuemEntra): só quem tinha um número escrito na coluna do
    # telefone. A conta é feita sobre as linhas gravadas, a cada pedido: a leitura não guarda esse número.
    it 'a linha com e-mail bom e número sem DDD entra só com o e-mail, e a tela recebe quantas são' do
      campaign_import = lida(<<~CSV)
        Nome,DDD,Celular,Email
        Ana,11,98765-0001,ana@exemplo.com.br
        Bia,,,bia@exemplo.com.br
        Caio,11,(11) 98765-0003,caio@exemplo.com.br
        Davi,11,3333-0004,davi@exemplo.com.br
      CSV

      expect(campaign_import).to have_attributes(status: 'ready_to_confirm', valid_rows: 4, invalid_rows: 0)
      expect(CampaignImports::NormalizedRows.new(campaign_import).perform.pluck(:phone_number)).to eq([nil, nil, '+5511987650003', nil])
      # A Ana (sem DDD) e o Davi (telefone fixo). A Bia não tinha telefone na planilha: nada se perde.
      expect(ContactImports::Trazer::QuemEntra.new(campaign_import, {}).sem_telefone).to eq(2)
      expect(Relacionamentos::Trazer::Leitura.new(campaign_import).call[:resumo]).to include(semTelefone: 2, entram: 4, comProblema: 0)
      expect(campaign_import.validation_summary).not_to have_key('sem_telefone')
      guardado = [campaign_import.options, campaign_import.validation_summary]
      expect(guardado.to_json).not_to include('98765-0001', '3333-0004')
    end

    # Trazer assim mesmo não perde o telefone para sempre: a planilha corrigida, enviada de novo, acha a pessoa pelo
    # e-mail e completa o telefone que faltava (CampaignImports::ContactRow e CampaignImports::ContactBlankFields).
    it 'a planilha corrigida, enviada de novo, completa o telefone de quem entrou só com o e-mail' do
      import_contacts!(lida("Nome,DDD,Celular,Email\nAna,11,98765-0001,ana@exemplo.com.br\n"))
      expect(account.contacts.sole).to have_attributes(name: 'Ana', phone_number: nil, email: 'ana@exemplo.com.br')

      corrigida = lida("Nome,Celular,Email\nAna,(11) 98765-0001,ana@exemplo.com.br\n")
      expect(Relacionamentos::Trazer::Leitura.new(corrigida).call[:resumo]).to include(semTelefone: 0, entram: 1)
      import_contacts!(corrigida)

      expect(account.contacts.sole).to have_attributes(name: 'Ana', phone_number: '+5511987650001', email: 'ana@exemplo.com.br')
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
        ana albuquerino,(11) 98765-0001,ANA@exemplo.com.br,Padaria Bom Dia,Prata
        Bia Brandolim,11987650002,bia@exemplo.com.br,,
        Beatriz Outra,11987650009,BIA@exemplo.com.br,,
        Ana Albuquerino,11987650007,,,
        Caio Carvalhedo,11987650003,,,
        caio carvalhedo,(11) 98765-0003,caio@exemplo.com.br,Mercado Central,
      CSV
    end

    # Linhas 7 e 8: a mesma pessoa, sem nada em conflito. Linhas 2 e 3: a mesma pessoa, com o plano diferente.
    it 'junta numa linha só as linhas sem conflito e completa a primeira com o que só a outra tinha' do
      campaign_import = lida(repetidas)

      expect(campaign_import).to have_attributes(status: 'ready_to_confirm', total_rows: 6, valid_rows: 4, invalid_rows: 2)
      expect(campaign_import.validation_summary).to include('mesma_pessoa' => 1)
      linhas = campaign_import.campaign_import_rows.order(:row_number)
      expect(linhas.pluck(:row_number, :status)).to eq([[2, 'valid'], [3, 'invalid'], [4, 'valid'], [5, 'invalid'], [6, 'valid'], [7, 'valid']])
      expect(linhas.where(status: :valid).pluck(:row_number, :company_name, :extra_values)).to eq(
        [[2, nil, { 'Plano' => 'Ouro' }], [4, nil, {}], [6, nil, {}], [7, 'Mercado Central', {}]]
      )
      conferidas = CampaignImports::NormalizedRows.new(campaign_import).perform.map { |linha| linha.slice(:row_number, :name, :phone_number, :email) }
      expect(conferidas).to eq(
        [{ row_number: 2, name: 'Ana Albuquerino', phone_number: '+5511987650001', email: nil },
         { row_number: 4, name: 'Bia Brandolim', phone_number: '+5511987650002', email: 'bia@exemplo.com.br' },
         # Nome igual não junta ninguém: a Ana de outro telefone é outra pessoa.
         { row_number: 6, name: 'Ana Albuquerino', phone_number: '+5511987650007', email: nil },
         { row_number: 7, name: 'Caio Carvalhedo', phone_number: '+5511987650003', email: 'caio@exemplo.com.br' }]
      )
    end

    it 'com dado em conflito, a segunda linha vira problema de linha repetida e guarda as células das duas' do
      campaign_import = lida(repetidas)

      # O plano diferente (Ouro e Prata) é conflito: juntar ficaria com o Ouro, e o Prata sumiria sem ninguém ver.
      expect(campaign_import.campaign_import_rows.find_by!(row_number: 3).error_messages).to eq(['duplicate_phone_in_file'])
      expect(campaign_import.campaign_import_rows.find_by!(row_number: 5).error_messages).to eq(['duplicate_email_in_file'])
      gravadas = campaign_import.linhas_com_problema.download.force_encoding(Encoding::UTF_8).lines.map { |linha| JSON.parse(linha) }
      expect(gravadas).to eq(
        [{ 'linha' => 3,
           'celulas' => { 'name' => 'ana albuquerino', 'phone' => '(11) 98765-0001', 'email' => 'ANA@exemplo.com.br',
                          'company' => 'Padaria Bom Dia' },
           'outra' => { 'linha' => 2, 'celulas' => { 'name' => 'Ana Albuquerino', 'phone' => '11987650001', 'email' => '', 'company' => '' } } },
         { 'linha' => 5, 'celulas' => { 'name' => 'Beatriz Outra', 'phone' => '11987650009', 'email' => 'BIA@exemplo.com.br', 'company' => '' },
           'outra' => { 'linha' => 4,
                        'celulas' => { 'name' => 'Bia Brandolim', 'phone' => '11987650002', 'email' => 'bia@exemplo.com.br', 'company' => '' } } }]
      )
    end

    it 'grava uma pessoa só para as linhas juntadas, com os dados das duas' do
      campaign_import = lida(repetidas)

      import_contacts!(campaign_import)

      expect(account.contacts.where(phone_number: '+5511987650003').sole).to have_attributes(name: 'Caio Carvalhedo', email: 'caio@exemplo.com.br')
      # A linha em conflito ficou de fora: a Ana entra com o plano da linha dela e sem o e-mail da outra.
      expect(account.contacts.where(phone_number: '+5511987650001').sole).to have_attributes(
        name: 'Ana Albuquerino', email: nil, custom_attributes: { 'plano' => 'Ouro' }
      )
      expect(account.contacts.count).to eq(4)
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
