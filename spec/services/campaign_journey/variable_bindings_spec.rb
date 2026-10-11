require 'rails_helper'

# #1331: the bindings accept a key of the field catalog, and the older sources keep working.
RSpec.describe CampaignJourney::VariableBindings, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:audience) do
    saved_audience(account: account_and_user.first, user: account_and_user.last,
                   content: "Nome,Celular,Vencimento,Valor\nAna Souza,11987654321,2026-10-14,1234.5\nBia Lima,21987654321,,\n")
  end
  let(:ana) { audience.campaign_import_rows.order(:row_number).first }
  let(:types) { { 'Vencimento' => 'data', 'Valor' => 'moeda' } }

  def resolve(bindings, defaults = {}, row = ana)
    described_class.new(bindings, defaults, column_types: types).resolve(row.contact, row.extra_values)
  end

  describe '#validate!' do
    it 'accepts catalog keys an audience fills, next to the older sources' do
      bindings = {
        '1' => { 'source' => 'field', 'value' => 'cliente.primeiro_nome' },
        '2' => { 'source' => 'field', 'value' => 'publico.Vencimento' },
        '3' => { 'source' => 'contact', 'value' => 'company' },
        '4' => { 'source' => 'column', 'value' => 'Valor' },
        '5' => { 'source' => 'fixed', 'value' => 'Equipe' }
      }

      result = described_class.new(bindings, { '2' => 'em breve', '3' => 'sua empresa', '4' => 'a combinar' })
                              .validate!(audience, template_keys: %w[1 2 3 4 5])

      expect(result.included_count).to eq(2)
    end

    it 'refuses a key the audience cannot fill or that does not exist' do
      %w[negocio.valor horario.data_hora atendente.nome fixo cliente.inventado].each do |key|
        expect { described_class.new({ '1' => { 'source' => 'field', 'value' => key } }).validate!(audience, template_keys: ['1']) }
          .to raise_error(described_class::Error, 'invalid_variable_bindings')
      end
    end

    it 'names a spreadsheet column the audience does not have' do
      bindings = { '1' => { 'source' => 'field', 'value' => 'publico.Plano' }, '2' => { 'source' => 'column', 'value' => 'Cor' } }

      expect { described_class.new(bindings).validate!(audience, template_keys: %w[1 2]) }.to raise_error(described_class::Error) do |error|
        expect(error.details).to eq(unknown_columns: %w[Plano Cor])
      end
    end

    it 'checks the coverage of the spreadsheet row for catalog keys' do
      bindings = { '1' => { 'source' => 'field', 'value' => 'publico.Vencimento' } }

      result = described_class.new(bindings).validate!(audience, template_keys: ['1'])

      expect([result.included_count, result.missing_by_variable]).to eq([1, { '1' => 1 }])
    end
  end

  describe '#resolve' do
    it 'reads catalog keys, formatting the column by its type' do
      values, missing = resolve(
        '1' => { 'source' => 'field', 'value' => 'cliente.primeiro_nome' },
        '2' => { 'source' => 'field', 'value' => 'publico.Vencimento' },
        '3' => { 'source' => 'field', 'value' => 'publico.Valor' },
        '4' => { 'source' => 'field', 'value' => 'minha_empresa.nome' }
      )

      expect(values).to eq('1' => 'Ana', '2' => '14/10/2026', '3' => 'R$ 1.234,50', '4' => account.name)
      expect(missing).to eq([])
    end

    it 'keeps the older sources as they were: the column goes raw' do
      values, = resolve(
        '1' => { 'source' => 'contact', 'value' => 'name' },
        '2' => { 'source' => 'contact', 'value' => 'first_name' },
        '3' => { 'source' => 'column', 'value' => 'Vencimento' },
        '4' => { 'source' => 'fixed', 'value' => 'Equipe' }
      )

      expect(values).to eq('1' => 'Ana Souza', '2' => 'Ana', '3' => '2026-10-14', '4' => 'Equipe')
    end

    it 'falls back to the default, or reports the missing variable' do
      bia = audience.campaign_import_rows.order(:row_number).second
      bindings = { '1' => { 'source' => 'field', 'value' => 'publico.Vencimento' }, '2' => { 'source' => 'field', 'value' => 'publico.Valor' } }

      values, missing = resolve(bindings, { '1' => 'em breve' }, bia)

      expect(values).to eq('1' => 'em breve')
      expect(missing).to eq(['2'])
    end

    # Existing campaigns keep sending what they sent: the older contact source is not touched by the new rule.
    it 'keeps the older contact first name as it was, even for a name that is only a phone' do
      ana.contact.update!(name: '+55 11 98765-4321', additional_attributes: { 'company_name' => 'Padaria Sol' })

      values, missing = resolve(
        '1' => { 'source' => 'contact', 'value' => 'first_name' }, '2' => { 'source' => 'contact', 'value' => 'name' },
        '3' => { 'source' => 'contact', 'value' => 'company' }
      )

      expect([values, missing]).to eq([{ '1' => '+55', '2' => '+55 11 98765-4321', '3' => 'Padaria Sol' }, []])
    end

    it 'uses the one first name rule on the catalog key: a name that is only a phone has no first name' do
      ana.contact.update!(name: '+55 11 98765-4321')

      values, missing = resolve('1' => { 'source' => 'field', 'value' => 'cliente.primeiro_nome' })

      expect([values, missing]).to eq([{}, ['1']])
    end

    it 'reads no account or catalog when only older column and fixed bindings exist' do
      allow(TemplateFields::AccountResolver).to receive(:new).and_call_original

      resolve('1' => { 'source' => 'column', 'value' => 'Vencimento' }, '2' => { 'source' => 'fixed', 'value' => 'Equipe' })

      expect(TemplateFields::AccountResolver).not_to have_received(:new)
    end
  end
end
