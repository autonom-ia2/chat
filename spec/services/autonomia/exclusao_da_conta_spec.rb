require 'rails_helper'

# #2133: a lista do Autonomia::ExclusaoDaConta precisa acompanhar o banco. Este spec lê as chaves estrangeiras, os
# índices e as colunas do próprio Postgres, então pega tabela nova que alguém criar depois e que barraria a exclusão da
# conta, ficaria com linha de conta apagada, levaria anexo pela cascata ou deixaria a cascata sem índice.
RSpec.describe Autonomia::ExclusaoDaConta do
  # O pré-apagar do upstream no DeleteObjectJob, que roda entre `antes_do_pre_apagar` e `perform`: conversas, contatos e caixas
  # (com as mensagens, que saem num job delas) e eventos de relatório.
  let(:pre_apagadas) { %w[conversations contacts contact_inboxes inboxes messages reporting_events] }
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

  # [filha, coluna, mãe, ação]. Ação: 'a' NO ACTION, 'r' RESTRICT, 'c' CASCADE, 'n' SET NULL.
  def chaves
    @chaves ||= ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT c.conrelid::regclass::text, a.attname, c.confrelid::regclass::text, c.confdeltype
      FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
      WHERE c.contype = 'f'
    SQL
  end

  def chaves_que_barram
    chaves.filter_map { |filha, _coluna, mae, acao| [filha, mae] if %w[a r].include?(acao) }
  end

  # Tabelas que saem pela cascata a partir de `origens`, direta ou passando por outra que sai.
  def alcancadas_pela_cascata(origens)
    alcancadas = origens.dup
    loop do
      novas = chaves.filter_map { |filha, _c, mae, acao| filha if acao == 'c' && alcancadas.include?(mae) && alcancadas.exclude?(filha) }.uniq
      break alcancadas if novas.empty?

      alcancadas.concat(novas)
    end
  end

  # Quem apaga as linhas da conta: a lista do serviço, as associações da conta que apagam (antes ou depois do commit;
  # `nullify` não conta) e a cascata do banco.
  def tabelas_cobertas
    que_apagam = %i[destroy destroy_async delete_all delete]
    apagam = Account.reflect_on_all_associations.select { |assoc| que_apagam.include?(assoc.options[:dependent]) }
    alcancadas_pela_cascata(described_class.tabelas + apagam.map { |assoc| assoc.klass.table_name } + ['accounts'])
  end

  # Índice que serve a `WHERE coluna = $1` do gatilho da chave: começa pela coluna e não é parcial (ou o filtro é só
  # `coluna IS NOT NULL`, que o `=` já garante).
  def indexadas
    ActiveRecord::Base.connection.select_rows(<<~SQL.squish).to_set
      SELECT i.indrelid::regclass::text, a.attname
      FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
      WHERE i.indpred IS NULL OR pg_get_expr(i.indpred, i.indrelid) = '(' || a.attname || ' IS NOT NULL)'
    SQL
  end

  it 'apaga toda tabela que aponta para a conta, com ou sem cascata, para o DELETE da conta não levar nada junto' do
    filhas_da_conta = chaves.filter_map { |filha, _coluna, mae, acao| filha if mae == 'accounts' && %w[a r c].include?(acao) }

    expect(filhas_da_conta.uniq - described_class.tabelas - described_class.tabelas_que_saem_com_a_conta).to eq([])
  end

  it 'apaga cada tabela antes das que ela referencia sem cascata, inclusive as do pré-apagar' do
    ordem = described_class.tabelas
    fora_de_ordem = chaves_que_barram.filter_map do |filha, mae|
      next if filha == mae

      if pre_apagadas.include?(mae)
        next "#{filha} -> #{mae} (#{filha} não sai antes do pré-apagar)" if described_class.tabelas_antes_do_pre_apagar.exclude?(filha)

        next
      end
      next unless ordem.include?(mae)
      next "#{filha} -> #{mae} (#{filha} não é apagada)" unless ordem.include?(filha)

      "#{filha} -> #{mae}" if ordem.index(filha) > ordem.index(mae)
    end

    expect(fora_de_ordem.uniq).to eq([])
  end

  it 'tem índice em toda chave que o gatilho procura ao apagar as tabelas da conta' do
    apagadas = described_class.tabelas + pre_apagadas
    sem_indice = chaves.filter_map do |filha, coluna, mae, _acao|
      "#{filha}.#{coluna} -> #{mae}" if apagadas.include?(mae) && indexadas.exclude?([filha, coluna])
    end

    expect(sem_indice.uniq).to eq([])
  end

  it 'não deixa tabela com account_id sem quem a apague' do
    conexao = ActiveRecord::Base.connection
    com_conta = conexao.tables.select { |tabela| conexao.column_exists?(tabela, :account_id) }

    expect(com_conta - tabelas_cobertas - fora.keys).to eq([])
  end

  it 'não deixa modelo com anexo sair pela cascata, que não apaga o arquivo' do
    Rails.application.eager_load!
    origens = described_class.tabelas + pre_apagadas + ['accounts']
    pela_cascata = alcancadas_pela_cascata(origens) - origens
    com_anexo = ApplicationRecord.descendants.select { |modelo| modelo.table_name && modelo.reflect_on_all_attachments.any? }

    expect(com_anexo.select { |modelo| pela_cascata.include?(modelo.table_name) }.map(&:name)).to eq([])
  end

  it 'apaga o anexo do que sai em lote, que não roda callback, e só manda apagar o arquivo que ninguém mais usa' do
    account = create(:account)
    agora = Time.current
    # Linhas cruas: o que importa é a linha e o anexo existirem, não o fluxo de criar o agente.
    # rubocop:disable Rails/SkipsModelValidations
    agente = Autonomia::Agents::Agent.insert!({ account_id: account.id, name: 'Atendente', created_at: agora, updated_at: agora },
                                              returning: :id).rows.first.first
    fontes = Array.new(2) do
      Autonomia::Agents::Source.insert!({ account_id: account.id, autonomia_agent_id: agente, source_type: 'file',
                                          created_at: agora, updated_at: agora }, returning: :id).rows.first.first
    end
    # rubocop:enable Rails/SkipsModelValidations
    sozinho = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('tabela de preços'), filename: 'precos.txt')
    compartilhado = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('logo'), filename: 'logo.png')
    ActiveStorage::Attachment.create!(record_type: 'Autonomia::Agents::Source', record_id: fontes.first, name: 'file', blob: sozinho)
    ActiveStorage::Attachment.create!(record_type: 'Autonomia::Agents::Source', record_id: fontes.last, name: 'file', blob: compartilhado)
    ActiveStorage::Attachment.create!(record: create(:user), name: 'avatar', blob: compartilhado)

    um_so = have_enqueued_job(ActiveStorage::PurgeJob).exactly(:once)
    expect { described_class.new(account).perform }.to um_so.and have_enqueued_job(ActiveStorage::PurgeJob).with(sozinho)

    expect(ActiveStorage::Attachment.where(record_type: 'Autonomia::Agents::Source')).to be_empty
    expect(Autonomia::Agents::Source.unscoped.where(id: fontes)).to be_empty
    expect(compartilhado.reload.attachments.count).to eq(1)
  end

  it 'para a conta: suspende e cancela as campanhas agendadas dela, sem tocar as de outra conta' do
    account = create(:account)
    outra = create(:account)
    remetente = EmailSenderIdentity.insert!({ account_id: account.id, domain: 'exemplo.invalid', created_at: Time.current, # rubocop:disable Rails/SkipsModelValidations
                                              updated_at: Time.current }, returning: :id).rows.first.first
    campanhas = [account, outra].map do |dona|
      EmailCampaign.insert!({ account_id: dona.id, name: 'Novidades', sender_identity_id: remetente, status: EmailCampaign.statuses[:scheduled], # rubocop:disable Rails/SkipsModelValidations
                              created_at: Time.current, updated_at: Time.current }, returning: :id).rows.first.first
    end

    described_class.new(account).parar_a_conta

    expect([account.reload.status, outra.reload.status]).to eq(%w[suspended active])
    expect(EmailCampaign.where(id: campanhas).order(:account_id).pluck(:status)).to eq(%w[canceled scheduled])
  end

  it 'registra no log a etapa que falhou, sem dado da linha, e deixa o erro subir' do
    account = create(:account)
    allow(Crm::Card).to receive(:unscoped).and_raise(ActiveRecord::QueryCanceled, 'canceling statement due to statement timeout')
    allow(Rails.logger).to receive(:error)

    expect { described_class.new(account).perform }.to raise_error(ActiveRecord::QueryCanceled)
    expect(Rails.logger).to have_received(:error).with("[ExclusaoDaConta] conta=#{account.id} etapa=Crm::Card falhou: ActiveRecord::QueryCanceled")
  end
end
