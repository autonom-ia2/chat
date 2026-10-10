require 'rails_helper'

RSpec.describe CampaignImports::AudienceValidator, :aggregate_failures do
  let(:xlsx_type) { 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }

  def b1_xlsx
    build_xlsx(
      [
        ['Segurado', 'Fone 1', 'Corretora', 'Vencimento'],
        ['Ana Souza', '(11) 98765-4321', 'Corretora Alfa', '10/2026'],
        ['Bruno Lima', '21987654321', 'Beta Seguros', '11/2026']
      ]
    )
  end

  describe 'B1: XLSX Segurado / Fone 1 / Corretora / Vencimento with Jev' do
    it 'binds name, phone and company, keeps Vencimento as extra column and records method jev' do
      account, user = create_account_and_user
      enable_audience_jev
      requests = stub_audience_jev(phone: 'column_1', email: 'none', name: 'column_0', company: 'column_2')
      campaign_import = create_audience_import(account: account, user: user, content: b1_xlsx, filename: 'b1.xlsx', content_type: xlsx_type)

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_ready_to_confirm
      resolution = campaign_import.schema_resolution
      expect(resolution).to include('method' => 'jev', 'needs_confirmation' => false, 'header_row' => 1)
      expect(resolution['targets'].transform_values { |entry| entry['header'] }).to eq(
        'name' => 'Segurado', 'phone' => 'Fone 1', 'email' => nil, 'company' => 'Corretora'
      )
      expect(campaign_import.extra_columns).to eq(['Vencimento'])
      expect(campaign_import.channels).to eq(
        'email' => { 'enabled' => false, 'count' => 0 }, 'whatsapp' => { 'enabled' => true, 'count' => 2 },
        'sms' => { 'enabled' => false, 'count' => 2 }
      )
      rows = campaign_import.campaign_import_rows.order(:row_number)
      expect(rows.pluck(:company_name, :extra_values)).to eq([['Corretora Alfa', { 'Vencimento' => '10/2026' }],
                                                              ['Beta Seguros', { 'Vencimento' => '11/2026' }]])
      expect(requests.size).to eq(1)
    end

    # B4 / Q1: the request carries only headers, counts and masked formats.
    it 'never sends a name, number or email from the file to Jev' do
      account, user = create_account_and_user
      enable_audience_jev
      requests = stub_audience_jev(phone: 'column_1', email: 'column_2', name: 'column_0', company: 'none')
      content = "Nome;Celular;E-mail\nAna Souza;(11) 98765-4321;ana.souza@example.org\nBruno Lima;21987654321;bruno@cliente.com.br\n"
      campaign_import = create_audience_import(account: account, user: user, content: content)

      described_class.new(campaign_import).perform

      body = requests.to_json
      expect(requests.size).to eq(1)
      expect(requests.first.dig('state', 'headers')).to eq(%w[Nome Celular E-mail])
      expect(requests.first.dig('state', 'profiles', 1)).to include('valid_phone_count' => 2, 'non_blank_count' => 2)
      expect(body).not_to include('Ana', 'Souza', 'Bruno', 'Lima', '98765', '4321', '987654321', 'ana.souza', 'example.org', 'cliente.com.br', '@')
      expect(campaign_import.reload).to be_ready_to_confirm
    end
  end

  describe 'B1c: CSV with ; and Responsável / Email comercial / Corretora' do
    it 'binds name, email and company and turns the email channel on' do
      account, user = create_account_and_user
      enable_audience_jev
      stub_audience_jev(phone: 'none', email: 'column_1', name: 'column_0', company: 'column_2')
      content = "Responsável;Email comercial;Corretora\nAna Souza;ana@alfa.com.br;Alfa\nBruno Lima;BRUNO@beta.com.br;Beta\n"
      campaign_import = create_audience_import(account: account, user: user, content: content)

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_ready_to_confirm
      expect(campaign_import.schema_resolution).to include('method' => 'jev', 'delimiter' => ';')
      expect(campaign_import.schema_resolution['targets'].transform_values { |entry| entry['column'] }).to eq(
        'name' => 0, 'phone' => nil, 'email' => 1, 'company' => 2
      )
      expect(campaign_import.channels['email']).to eq('enabled' => true, 'count' => 2)
      expect(campaign_import.channels['whatsapp']).to eq('enabled' => false, 'count' => 0)
      expect(campaign_import.extra_columns).to eq([])
      expect(campaign_import.campaign_import_rows.order(:row_number).pluck(:email_masked)).to eq(['a**@alfa.com.br', 'b****@beta.com.br'])
    end
  end

  describe 'customer_base reading (#1246)' do
    def import_for(content, customer_base:, **answers)
      account, user = create_account_and_user
      account.enable_features!('customer_base') if customer_base
      enable_audience_jev
      stub_audience_jev(**answers)
      create_audience_import(account: account, user: user, content: content)
    end

    let(:multi_email) { "Nome,Emails\nAna,ana@alfa.com.br; ana.souza@beta.com.br\nBia,bia@; bia@\nCaio,caio@gama.com.br\n" }
    let(:legacy_phone) { "Nome,Celular\nAna,(11) 8765-4321\nBia,21987654321\n" }
    let(:headless) { "Ana,11987654321\nBia,21987654321\n" }

    context 'when on' do
      it 'takes the first valid email of the cell and never stores the others in clear' do
        campaign_import = import_for(multi_email, customer_base: true, phone: 'none', email: 'column_1', name: 'column_0', company: 'none')

        described_class.new(campaign_import).perform

        rows = campaign_import.reload.campaign_import_rows.order(:row_number)
        expect(campaign_import.valid_rows).to eq(2)
        expect(rows.pluck(:email_masked)).to eq(['a**@alfa.com.br', 'b**@; b**@', 'c***@gama.com.br'])
      end

      it 'restores the ninth digit of a legacy mobile and counts it in the summary' do
        campaign_import = import_for(legacy_phone, customer_base: true, phone: 'column_1', email: 'none', name: 'column_0', company: 'none')

        described_class.new(campaign_import).perform

        campaign_import.reload
        expect(campaign_import.valid_rows).to eq(2)
        expect(campaign_import.validation_summary['ninth_digit_added']).to eq(1)
      end

      it 'asks for the columns of a file without a header and keeps its first line as data' do
        campaign_import = import_for(headless, customer_base: true, phone: 'column_1', email: 'none', name: 'column_0', company: 'none')

        described_class.new(campaign_import).perform

        expect(campaign_import.reload).to be_needs_column_choice
        expect(campaign_import.schema_resolution).to include('header_row' => 0, 'needs_confirmation' => true)

        manual = { 'name' => 0, 'phone' => 1, 'email' => nil, 'company' => nil }
        campaign_import.update!(schema_resolution: campaign_import.schema_resolution.merge('manual_mapping' => manual))
        described_class.new(campaign_import).perform

        expect(campaign_import.reload).to be_ready_to_confirm
        expect(campaign_import.valid_rows).to eq(2)
      end
    end

    context 'when off' do
      it 'keeps a cell with two emails invalid and masked as before' do
        campaign_import = import_for(multi_email, customer_base: false, phone: 'none', email: 'column_1', name: 'column_0', company: 'none')

        described_class.new(campaign_import).perform

        rows = campaign_import.reload.campaign_import_rows.order(:row_number)
        expect(campaign_import.valid_rows).to eq(1)
        expect(rows.pluck(:email_masked)).to eq(['a**@alfa.com.br; ana.souza@beta.com.br', 'b**@; bia@', 'c***@gama.com.br'])
      end

      it 'keeps refusing a legacy mobile and adds nothing to the summary' do
        campaign_import = import_for(legacy_phone, customer_base: false, phone: 'column_1', email: 'none', name: 'column_0', company: 'none')

        described_class.new(campaign_import).perform

        campaign_import.reload
        expect(campaign_import.valid_rows).to eq(1)
        expect(campaign_import.validation_summary).not_to have_key('ninth_digit_added')
      end

      it 'keeps refusing a file without a header' do
        campaign_import = import_for(headless, customer_base: false, phone: 'column_1', email: 'none', name: 'column_0', company: 'none')

        described_class.new(campaign_import).perform

        expect(campaign_import.reload).to be_validation_failed
        expect(campaign_import.validation_summary['errors']).to have_key('empty_file')
      end
    end
  end

  describe 'B2 / Q3: no confident answer means a manual column choice, never an error' do
    let(:content) { "nome;telefone;empresa;plano\nAna;11987654321;Alfa;Ouro\nBia;21987654321;Beta;Prata\n" }

    it 'stops at needs_column_choice with alias suggestions when Jev is off' do
      account, user = create_account_and_user
      campaign_import = create_audience_import(account: account, user: user, content: content)

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_needs_column_choice
      expect(campaign_import.schema_resolution).to include('method' => 'deterministic', 'needs_confirmation' => true)
      expect(campaign_import.schema_resolution['jev']).to eq('status' => 'disabled')
      expect(campaign_import.schema_resolution['targets']['phone']).to include('column' => 1, 'source' => 'alias', 'confident' => false)
      expect(campaign_import.schema_resolution['uncertain_targets']).to match_array(%w[name phone email company])
      expect(campaign_import.campaign_import_rows.count).to eq(0)
      expect(account.contacts.count).to eq(0)
    end

    it 'stops at needs_column_choice when Jev fails, keeping the error code' do
      account, user = create_account_and_user
      enable_audience_jev
      stub_request(:post, AudienceJevHelpers::JEV_URL).to_return(status: 401, body: '{}')
      campaign_import = create_audience_import(account: account, user: user, content: content)

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_needs_column_choice
      expect(campaign_import.schema_resolution['jev']).to eq('status' => 'failed', 'error' => 'typesafe_invalid_key')
    end

    it 'asks only for the targets Jev was unsure about' do
      account, user = create_account_and_user
      enable_audience_jev
      stub_audience_jev(phone: 'column_1', email: 'none', name: 'column_0', company: 'column_3',
                        confidence: { phone: 0.95, email: 0.95, name: 0.95, company: 0.4 })
      campaign_import = create_audience_import(account: account, user: user, content: content)

      described_class.new(campaign_import).perform

      resolution = campaign_import.reload.schema_resolution
      expect(campaign_import).to be_needs_column_choice
      expect(resolution['uncertain_targets']).to eq(['company'])
      expect(resolution['targets']['company']).to include('column' => 2, 'source' => 'alias', 'confident' => false)
    end

    it 'validates with the chosen columns once the user picks them' do
      account, user = create_account_and_user
      campaign_import = create_audience_import(account: account, user: user, content: content)
      described_class.new(campaign_import).perform
      resolution = campaign_import.reload.schema_resolution
      campaign_import.update!(schema_resolution: resolution.merge('manual_mapping' => { 'name' => 0, 'phone' => 1, 'email' => nil, 'company' => 2 }))

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_ready_to_confirm
      expect(campaign_import.schema_resolution).to include('method' => 'manual', 'needs_confirmation' => false)
      expect(campaign_import.extra_columns).to eq(['plano'])
      expect(campaign_import.valid_rows).to eq(2)
    end
  end

  describe 'B3: header on row 3' do
    it 'finds the header below a title and a note without intervention' do
      account, user = create_account_and_user
      enable_audience_jev
      requests = stub_audience_jev(phone: 'column_1', email: 'column_2', name: 'column_0', company: 'column_3')
      xlsx = build_xlsx(
        [
          ['Relatório de clientes', '', '', ''],
          ['Gerado em 01/10/2026', '', '', ''],
          %w[Nome Celular E-mail Empresa],
          ['Ana Souza', '11987654321', 'ana@alfa.com.br', 'Alfa']
        ]
      )
      campaign_import = create_audience_import(account: account, user: user, content: xlsx, filename: 'b3.xlsx', content_type: xlsx_type)

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_ready_to_confirm
      expect(campaign_import.schema_resolution['header_row']).to eq(3)
      expect(requests.first.dig('state', 'headers')).to eq(%w[Nome Celular E-mail Empresa])
      expect(campaign_import.campaign_import_rows.pluck(:row_number)).to eq([4])
    end
  end

  describe 'rows, channels and duplicates' do
    it 'keeps a row with a phone or an email, the first occurrence wins, and counts each channel' do
      account, user = create_account_and_user
      enable_audience_jev
      stub_audience_jev(phone: 'column_1', email: 'column_2', name: 'column_0', company: 'none')
      content = <<~CSV
        Nome,Celular,Email
        Ana,11987654321,ana@x.com.br
        Bia,,bia@x.com.br
        Caio,21987654321,
        Ana de novo,11987654321,outra@x.com.br
        Bia de novo,31987654321,BIA@x.com.br
        Sem contato,1133334444,nao-e-email
        Vazio,,
      CSV
      campaign_import = create_audience_import(account: account, user: user, content: content)

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_ready_to_confirm
      expect(campaign_import.valid_rows).to eq(3)
      expect(campaign_import.invalid_rows).to eq(4)
      expect(campaign_import.channels).to eq(
        'email' => { 'enabled' => true, 'count' => 2 }, 'whatsapp' => { 'enabled' => true, 'count' => 2 },
        'sms' => { 'enabled' => false, 'count' => 2 }
      )
      errors = campaign_import.campaign_import_rows.status_invalid.order(:row_number).pluck(:row_number, :error_messages)
      expect(errors).to eq(
        [[5, ['duplicate_phone_in_file']], [6, ['duplicate_email_in_file']],
         [7, %w[invalid_brazilian_mobile_number invalid_email]], [8, ['missing_contact']]]
      )
      expect(campaign_import.error_csv.download).not_to include('1133334444', 'bia@x.com.br')
    end

    it 'refuses the file when no row has a valid phone or email' do
      account, user = create_account_and_user
      campaign_import = create_audience_import(account: account, user: user, content: "Nome,Celular\nAna,123\n")
      campaign_import.update!(schema_resolution: { 'manual_mapping' => { 'name' => 0, 'phone' => 1 }, 'header_row' => 1, 'table_index' => 0 })

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_validation_failed
      expect(campaign_import.validation_summary['errors']).to include('no_valid_rows')
      expect(campaign_import.normalized_csv).not_to be_attached
      expect(account.contacts.count).to eq(0)
    end
  end
end
