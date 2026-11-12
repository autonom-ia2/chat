# #2921: imports ready to be written in each flow the Importer serves, and ways to stop the Importer midway.
# The specs that use these set CampaignImports::Importer::BLOCK_SIZE to 2: five people are three blocks.
module CampaignImportResumeHelpers
  FLOWS = %i[contacts audience campaign_base].freeze
  PEOPLE = 5

  def resume_phones
    (1..PEOPLE).map { |index| "+551198765000#{index}" }
  end

  # Five valid people, validated and queued, as "confirmar" leaves an import.
  def queued_import(flow, account:, user:)
    campaign_import = case flow
                      when :contacts then validated_contacts_import(account, user)
                      when :audience then validated_audience_import(account, user)
                      when :campaign_base then validated_campaign_base_import(account, user)
                      end
    campaign_import.update!(status: :queued)
    campaign_import.reload
  end

  # What the automation step "para cada item" keeps in Contatos > Importações: no file, written by the step itself.
  def automation_import(account:, user:, status:, started_at: Time.current)
    account.campaign_imports.create!(
      user: user, status: status, mode: 'single_label', batch_count: 1, name: 'Automação', total_rows: 2,
      confirmed_at: started_at, import_started_at: started_at,
      options: { flow: CampaignImport::CONTACTS_FLOW, origem: CampaignImport::AUTOMATION_ORIGIN, default_country: 'BR' },
      validation_summary: status.to_s == 'failed' ? { 'parou' => 'sem_acesso' } : {}
    )
  end

  # Stops the Importer when it reaches the given block. A StandardError is what the Importer rescues (the import ends
  # `failed`); Interrupt is the killed worker: nothing rescues it and the import stays `importing`.
  # Spreadsheet flows prepare the companies of each block; the campaign base flow labels each block.
  def break_import_on_block(number, error)
    blocks = 0
    breaker = lambda do |original, *args|
      blocks += 1
      raise error if blocks == number

      original.call(*args)
    end
    allow_any_instance_of(CampaignImports::ImportCompanies).to receive(:prepare).and_wrap_original(&breaker) # rubocop:disable RSpec/AnyInstance
    allow(CampaignImports::BulkContactLabeler).to receive(:new).and_wrap_original(&breaker)
  end

  # The worker died when it reached the given block: the blocks before it are saved and the import stays `importing`.
  def kill_import_on_block(campaign_import, number)
    break_import_on_block(number, Interrupt.new('worker killed'))
    expect { CampaignImports::Importer.new(campaign_import).perform }.to(raise_error { |error| expect(error.class.name).to eq('Interrupt') })
    campaign_import.reload
  end

  private

  def resume_lines
    (1..PEOPLE).map { |index| "Pessoa #{index},1198765000#{index},Alfa,Ouro" }
  end

  def spreadsheet_content
    "Nome,Celular,Empresa,Plano\n#{resume_lines.join("\n")}\n"
  end

  def spreadsheet_mapping
    { 'name' => 0, 'phone' => 1, 'company' => 2 }
  end

  def validated_contacts_import(account, user)
    validate_contact_import(create_contact_import(account: account, user: user, content: spreadsheet_content), spreadsheet_mapping)
  end

  def validated_audience_import(account, user)
    campaign_import = create_audience_import(account: account, user: user, content: spreadsheet_content)
    campaign_import.update!(schema_resolution: { 'manual_mapping' => spreadsheet_mapping, 'header_row' => 1, 'table_index' => 0 })
    CampaignImports::AudienceValidator.new(campaign_import).perform
    campaign_import
  end

  def validated_campaign_base_import(account, user)
    content = "nome,telefone\n#{(1..PEOPLE).map { |index| "Pessoa #{index},1198765000#{index}" }.join("\n")}\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: 1)
    CampaignImports::Validator.new(campaign_import).perform
    campaign_import
  end
end

RSpec.configure do |config|
  config.include CampaignImportResumeHelpers
end
