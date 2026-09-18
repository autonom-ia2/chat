require 'rails_helper'

RSpec.describe EmailCampaigns::ReputationSchemaGuards::SchemaLoadHook do
  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }
  let(:other_connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }
  let(:installer) { instance_double(EmailCampaigns::ReputationSchemaGuards, applicable?: true, install!: nil) }
  let(:loader) do
    # Model Rails' shared loader contract without establishing another database.
    loader_class = Class.new do
      attr_reader :migration_connection

      def load_schema(config, _format = :ruby, _file = nil)
        @migration_connection = config.fetch(:connection)
        :loaded
      end

      def schema_dump_path(config, _format)
        config[:schema_dump]
      end
    end
    loader_class.prepend(described_class).new
  end

  it 'installs on each active target connection, not a restored default connection' do
    expect(EmailCampaigns::ReputationSchemaGuards).to receive(:new).with(connection).ordered.and_return(installer)
    expect(installer).to receive(:install!).ordered
    expect(EmailCampaigns::ReputationSchemaGuards).to receive(:new).with(other_connection).ordered.and_return(installer)
    expect(installer).to receive(:install!).ordered
    expect(loader.load_schema({ connection: connection }, :ruby, 'primary_schema.rb')).to eq(:loaded)
    expect(loader.load_schema({ connection: other_connection }, :ruby, 'secondary_schema.rb')).to eq(:loaded)
  end

  it 'does not install when Rails has no schema dump to load' do
    expect(EmailCampaigns::ReputationSchemaGuards).not_to receive(:new)
    expect(loader.load_schema({ connection: connection }, :ruby)).to eq(:loaded)
  end

  it 'uses the configured dump path when there is no explicit file argument' do
    expect(EmailCampaigns::ReputationSchemaGuards).to receive(:new).with(connection).and_return(installer)
    expect(installer).to receive(:install!)
    expect(loader.load_schema({ connection: connection, schema_dump: 'db/schema.rb' }, :ruby)).to eq(:loaded)
  end
end
