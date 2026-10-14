require 'rails_helper'
require Rails.root.join('db/migrate/20261021100000_recifrar_segredos_legados.rb')

# #1344 — segredo gravado antes das chaves passa a ficar cifrado no banco, sem mudar o que o app lê.
RSpec.describe RecifrarSegredosLegados do
  let(:account) { create(:account) }
  let(:channel_api) { create(:channel_api, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:webhook) { create(:webhook, account: account) }
  let(:hook) { create(:integrations_hook, account: account) }
  let(:channel_email) { create(:channel_email, account: account) }
  let(:telegram) { create(:channel_telegram, account: account) }

  # Os segredos legados, um por coluna, gravados em claro por SQL.
  let(:legado) do
    {
      [channel_api, :secret] => 'segredo-api-legado',
      [agent_bot, :secret] => 'segredo-bot-legado',
      [webhook, :secret] => 'segredo-webhook-legado',
      [hook, :access_token] => 'token-integracao-legado',
      [telegram, :bot_token] => '123456:token-telegram-legado',
      [channel_email, :imap_password] => 'senha-imap-legada'
    }
  end

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  before do
    enable_test_encryption!
    legado.each { |(registro, coluna), valor| gravar_bruto(registro, coluna, valor) }
    gravar_bruto(channel_email, :smtp_password, '')
  end

  # A linha legada de produção, gravada por SQL: não depende de a classe do app ter carregado com ou sem `encrypts`.
  def gravar_bruto(registro, coluna, valor)
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql(["UPDATE #{registro.class.table_name} SET #{coluna} = ? WHERE id = ?", valor, registro.id])
    )
  end

  def valor_bruto(registro, coluna)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql(["SELECT #{coluna} FROM #{registro.class.table_name} WHERE id = ?", registro.id])
    )
  end

  def brutos
    legado.keys.index_with { |registro, coluna| valor_bruto(registro, coluna) }
  end

  def cifrado?(bruto)
    ActiveRecord::Encryption.encryptor.encrypted?(bruto)
  end

  # O model do app como fica em produção, com chaves: a mesma declaração `encrypts`. Se a classe já carregou com
  # chaves neste processo, ela mesma serve; declarar de novo cifraria duas vezes.
  def model_do_app(klass, coluna)
    return klass if Array(klass.encrypted_attributes).include?(coluna)

    deterministic = [Integrations::Hook, Channel::Telegram].include?(klass)
    Class.new(klass) { encrypts coluna, deterministic: deterministic }
  end

  def lido_pelo_app(registro, coluna)
    model_do_app(registro.class, coluna).find(registro.id).public_send(coluna)
  end

  it 'cifra cada coluna em claro e o app lê o mesmo valor', :aggregate_failures do
    expect(brutos.values.map { |bruto| cifrado?(bruto) }).to all(be(false))

    described_class.new.up

    legado.each do |(registro, coluna), valor|
      bruto = valor_bruto(registro, coluna)
      expect(cifrado?(bruto)).to be(true), "#{registro.class.table_name}.#{coluna} continuou em claro"
      expect(bruto).not_to include(valor)
      expect(lido_pelo_app(registro, coluna)).to eq(valor)
    end
  end

  it 'a busca por igualdade nas colunas determinísticas acha a linha recifrada', :aggregate_failures do
    described_class.new.up

    hooks = model_do_app(Integrations::Hook, :access_token)
    expect(hooks.find_by(access_token: 'token-integracao-legado')&.id).to eq(hook.id)
    expect(hooks.find_by(access_token: 'outro-token')).to be_nil
    # O webhook do Telegram acha o canal pelo token (`Webhooks::TelegramEventsJob`).
    telegrams = model_do_app(Channel::Telegram, :bot_token)
    expect(telegrams.find_by(bot_token: '123456:token-telegram-legado')&.id).to eq(telegram.id)
  end

  # Linha mista: uma coluna já cifrada, outra em claro. `encrypt` regrava as duas; o valor lido não muda.
  it 'cifra a coluna em claro de uma linha mista sem mudar a que já estava cifrada', :aggregate_failures do
    gravar_bruto(channel_email, :smtp_password, 'senha-smtp')
    described_class.new.up
    gravar_bruto(channel_email, :imap_password, 'senha-imap-nova')

    described_class.new.up

    expect(cifrado?(valor_bruto(channel_email, :imap_password))).to be(true)
    expect(lido_pelo_app(channel_email, :imap_password)).to eq('senha-imap-nova')
    expect(lido_pelo_app(channel_email, :smtp_password)).to eq('senha-smtp')
  end

  it 'lê vazio como vazio e não cifra coluna em branco' do
    described_class.new.up

    expect(lido_pelo_app(channel_email, :smtp_password)).to eq('')
  end

  it 'não toca linha já cifrada: rodar de novo não muda nada', :aggregate_failures do
    described_class.new.up
    depois_da_primeira = brutos

    expect { described_class.new.up }.not_to(change { brutos })
    expect(brutos).to eq(depois_da_primeira)
  end

  it 'não mexe em updated_at' do
    gravados = legado.keys.map(&:first).index_with { |registro| registro.reload.updated_at }

    described_class.new.up

    expect(gravados.keys.index_with { |registro| registro.reload.updated_at }).to eq(gravados)
  end

  it 'sem chaves, não muda nada' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

    expect { described_class.new.up }.not_to(change { brutos })
  end

  it 'deixa as Ferramentas dos agentes para o #1328' do
    expect(described_class::COLUNAS).not_to have_key('autonomia_agent_tools')
  end

  it 'toda coluna da lista existe no banco' do
    faltando = described_class::COLUNAS.flat_map do |tabela, colunas|
      existentes = ActiveRecord::Base.connection.columns(tabela).map(&:name)
      colunas.reject { |coluna| existentes.include?(coluna.to_s) }.map { |coluna| "#{tabela}.#{coluna}" }
    end

    expect(faltando).to be_empty
  end

  it 'registra só a contagem por coluna, nunca valor nem id', :aggregate_failures do
    mensagens = []
    allow(Rails.logger).to receive(:info).and_wrap_original do |original, *args, &block|
      mensagens << (args.first || block&.call).to_s
      original.call(*args, &block)
    end

    described_class.new.up

    registro = mensagens.find { |mensagem| mensagem.start_with?('[recifrar_segredos]') }
    expect(registro).to include('channel_api.secret=1', 'agent_bots.secret=1', 'webhooks.secret=1',
                                'integrations_hooks.access_token=1', 'channel_telegram.bot_token=1',
                                'channel_email.imap_password=1',
                                'channel_email.smtp_password=0', 'channel_line.line_channel_token=0')
    expect(mensagens.join("\n")).not_to include(*legado.values)
  end
end
