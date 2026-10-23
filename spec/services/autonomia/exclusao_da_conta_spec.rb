require 'rails_helper'

# #2133: a lista do Autonomia::ExclusaoDaConta precisa acompanhar o banco. Este spec lê as chaves estrangeiras e as
# colunas do próprio Postgres, então pega tabela nova que alguém criar depois e que barraria a exclusão da conta ou
# ficaria com linha de conta apagada.
RSpec.describe Autonomia::ExclusaoDaConta do
  # Tabelas com account_id que não saem por aqui, com o motivo.
  let(:fora) do
    {
      # Registros append-only, que sobrevivem à conta de propósito. Os dois do WhatsApp têm gatilho no banco que recusa
      # DELETE; os dois do e-mail são protegidos só pelo app (`readonly?`, sem dependent).
      'whatsapp_out_of_window_sends' => 'append-only (#1585): prova do envio fora da janela',
      'whatsapp_template_consents' => 'append-only (#1586): autorização do dono para criar modelos da Meta',
      'email_reputation_audits' => 'append-only: auditoria da reputação de envio',
      'email_suppression_events' => 'append-only: histórico de descadastro e devolução',
      # Sai com a caixa, que o job apaga antes; o callback desliga a sessão no WAHA.
      'whatsapp_hybrid_connections' => 'Inbox has_one :whatsapp_hybrid_connection, dependent: :destroy (config/initializers)',
      # Do Chatwoot: saem pelo dependente de outro modelo (mensagem, conversa, assistente, importação, categoria, SLA).
      'attachments' => 'Message has_many :attachments, dependent: :destroy',
      'conversation_participants' => 'Conversation has_many :conversation_participants, dependent: :destroy_async',
      'captain_scenarios' => 'Captain::Assistant has_many :scenarios, dependent: :destroy_async',
      'copilot_messages' => 'CopilotThread has_many :copilot_messages, dependent: :destroy_async',
      'data_import_mappings' => 'DataImport has_many :mappings, dependent: :destroy_async',
      'folders' => 'Category has_many :folders, dependent: :destroy_async',
      'sla_events' => 'AppliedSla/Conversation has_many :sla_events, dependent: :destroy_async',
      # Do Chatwoot, sem dependente no upstream: fora do escopo do #2133.
      'captain_message_reports' => 'upstream',
      'leaves' => 'upstream',
      'reporting_events_rollups' => 'upstream'
    }
  end

  # Chaves que barram o DELETE de quem é referenciado: NO ACTION ('a') e RESTRICT ('r').
  def chaves_que_barram
    ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT conrelid::regclass::text, confrelid::regclass::text
      FROM pg_constraint
      WHERE contype = 'f' AND confdeltype IN ('a', 'r')
    SQL
  end

  # Quem apaga as linhas da conta: a lista do serviço, as associações da conta (antes ou depois do commit) e a cascata
  # do banco, direta ou por uma tabela que já sai.
  def tabelas_cobertas
    cobertas = described_class.tabelas + Account.reflect_on_all_associations.select { |assoc| assoc.options[:dependent] }
                                                .map { |assoc| assoc.klass.table_name }
    cascatas = ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT conrelid::regclass::text, confrelid::regclass::text FROM pg_constraint WHERE contype = 'f' AND confdeltype = 'c'
    SQL
    cobertas << 'accounts'
    loop do
      novas = cascatas.filter_map { |filha, mae| filha if cobertas.include?(mae) && cobertas.exclude?(filha) }.uniq
      break cobertas if novas.empty?

      cobertas.concat(novas)
    end
  end

  it 'apaga toda tabela que aponta para a conta sem cascata' do
    filhas_da_conta = chaves_que_barram.filter_map { |filha, mae| filha if mae == 'accounts' }

    expect(filhas_da_conta.uniq - described_class.tabelas).to eq([])
  end

  it 'apaga cada tabela antes das que ela referencia sem cascata, e toda tabela que referencia uma delas' do
    ordem = described_class.tabelas
    fora_de_ordem = chaves_que_barram.filter_map do |filha, mae|
      next unless ordem.include?(mae)
      next "#{filha} -> #{mae} (#{filha} não é apagada)" unless ordem.include?(filha)

      "#{filha} -> #{mae}" if filha != mae && ordem.index(filha) > ordem.index(mae)
    end

    expect(fora_de_ordem).to eq([])
  end

  it 'não deixa tabela com account_id sem quem a apague' do
    conexao = ActiveRecord::Base.connection
    com_conta = conexao.tables.select { |tabela| conexao.column_exists?(tabela, :account_id) }

    expect(com_conta - tabelas_cobertas - fora.keys).to eq([])
  end

  it 'apaga o anexo do que sai em lote, que não roda callback' do
    account = create(:account)
    agora = Time.current
    # Linhas cruas: o que importa é a linha e o anexo existirem, não o fluxo de criar o agente.
    # rubocop:disable Rails/SkipsModelValidations
    agente = Autonomia::Agents::Agent.insert!({ account_id: account.id, name: 'Atendente', created_at: agora, updated_at: agora },
                                              returning: :id).rows.first.first
    fonte = Autonomia::Agents::Source.insert!({ account_id: account.id, autonomia_agent_id: agente, source_type: 'file',
                                                created_at: agora, updated_at: agora }, returning: :id).rows.first.first
    # rubocop:enable Rails/SkipsModelValidations
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('tabela de preços'), filename: 'precos.txt')
    ActiveStorage::Attachment.create!(record_type: 'Autonomia::Agents::Source', record_id: fonte, name: 'file', blob: blob)

    expect { described_class.new(account).perform }.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob)

    expect(ActiveStorage::Attachment.where(record_type: 'Autonomia::Agents::Source', record_id: fonte)).to be_empty
    expect(Autonomia::Agents::Source.unscoped.where(id: fonte)).to be_empty
  end
end
