require 'rails_helper'

# #1934 (backfill): a foto dos contatos antigos da caixa híbrida, uma vez por caixa, no ritmo da busca ao vivo.
describe WhatsappHybrid::FotoDoContatoBackfillJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-foto-backfill', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current)
  end
  let(:client) { instance_double(Waha::Client) }
  let(:feito) { "#{described_class::FEITO}#{inbox.id}" }

  around do |example|
    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s, WHATSAPP_HYBRID_FOTO_BACKFILL_INBOX_IDS: "999, #{inbox.id}") { example.run }
  end

  before do
    Redis::Alfred.scan_each(match: 'whatsapp_hybrid:foto_do_contato:*') { |key| Redis::Alfred.delete(key) }
    account.enable_features!(WhatsappHybrid::FotoDoContato::FLAG)
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING' })
  end

  def agendados
    enqueued_jobs.select { |job| job['job_class'] == 'WhatsappHybrid::FotoDoContatoJob' }.map { |job| job['arguments'].first }
  end

  def contato_com_conversa(phone, ultima_atividade = 1.hour.ago)
    contato = create(:contact, account: account, phone_number: phone)
    create(:conversation, account: account, inbox: inbox, contact: contato, last_activity_at: ultima_atividade)
    contato
  end

  it 'agenda os contatos sem foto da caixa, do mais novo para o mais antigo, com pelo menos 1 minuto entre eles' do
    antigo = contato_com_conversa('+5511900000001')
    novo = contato_com_conversa('+5511900000002')

    described_class.perform_now

    jobs = enqueued_jobs.select { |job| job['job_class'] == 'WhatsappHybrid::FotoDoContatoJob' }
    expect(agendados).to eq([novo.id, antigo.id])
    expect(jobs.last['scheduled_at'].to_time - jobs.first['scheduled_at'].to_time).to be >= 60
  end

  it 'caixa fora da lista do backfill não entra' do
    contato_com_conversa('+5511900000009')

    with_modified_env(WHATSAPP_HYBRID_FOTO_BACKFILL_INBOX_IDS: '') { described_class.perform_now }
    with_modified_env(WHATSAPP_HYBRID_FOTO_BACKFILL_INBOX_IDS: '999') { described_class.perform_now }

    expect(agendados).to be_empty
  end

  it 'continua de onde parou e não dá a caixa por feita enquanto houver contato sem marca adiante' do
    stub_const("#{described_class}::LOTE", 2)
    contatos = Array.new(9) { |i| contato_com_conversa("+55119000001#{i.to_s.rjust(2, '0')}") }
    contatos.last(8).each { |c| Redis::Alfred.setex(WhatsappHybrid::FotoDoContato.chave_do_contato(c.id), 1, 60) }

    described_class.perform_now

    expect(agendados).to eq([contatos.first.id])
    expect(Redis::Alfred.exists?(feito)).to be(false)
  end

  it 'cada rodada pega os próximos, sem repetir os já agendados' do
    stub_const("#{described_class}::LOTE", 2)
    a, b, c = Array.new(3) { |i| contato_com_conversa("+55119000002#{i}") }

    described_class.perform_now
    primeira = agendados
    described_class.perform_now

    expect(primeira).to eq([c.id, b.id])
    expect(agendados).to eq([c.id, b.id, a.id])
  end

  it 'deixa de fora contato com foto, sem telefone, já tentado ou de outra caixa' do
    valido = contato_com_conversa('+5511900000010')
    com_foto = contato_com_conversa('+5511900000003', 1.hour.ago)
    com_foto.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
    contato_com_conversa(nil, 1.hour.ago).update!(email: 'sem@telefone.com')
    tentado = contato_com_conversa('+5511900000004', 1.hour.ago)
    Redis::Alfred.setex(WhatsappHybrid::FotoDoContato.chave_do_contato(tentado.id), 1, 60)
    create(:conversation, account: account, contact: create(:contact, account: account, phone_number: '+5511900000005'))

    described_class.perform_now

    expect(agendados).to eq([valido.id])
  end

  it 'dá duas voltas e só então marca a caixa como feita e não volta a ela' do
    described_class.perform_now
    expect(Redis::Alfred.exists?(feito)).to be(false)
    described_class.perform_now
    contato_com_conversa('+5511900000006', 1.hour.ago)

    expect(Redis::Alfred.exists?(feito)).to be(true)
    expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappHybrid::FotoDoContatoJob)
  end

  it 'no máximo LOTE por rodada e nunca além do teto do dia' do
    5.times { |i| contato_com_conversa("+551190000001#{i}") }
    Redis::Alfred.set(WhatsappHybrid::FotoDoContato.chave_do_dia(connection.session_name), described_class::TETO_DO_BACKFILL - 1)

    described_class.perform_now
    expect(agendados.size).to eq(1)

    Redis::Alfred.delete(WhatsappHybrid::FotoDoContato.chave_do_dia(connection.session_name))
    described_class.perform_now
    expect(agendados.size).to eq(1 + described_class::LOTE)
  end

  it 'não roda sem a flag, com a sessão fora de uso, caída no motor ou com a cota do backfill gasta' do
    contato_com_conversa('+5511900000007', 1.hour.ago)
    cenarios = [
      -> { account.disable_features!(WhatsappHybrid::FotoDoContato::FLAG) },
      -> { connection.update!(paused_at: Time.current) },
      -> { allow(client).to receive(:get_session).and_return({ 'status' => 'STARTING' }) },
      -> { Redis::Alfred.set(WhatsappHybrid::FotoDoContato.chave_do_dia(connection.session_name), described_class::TETO_DO_BACKFILL) }
    ]

    cenarios.each do |cenario|
      account.enable_features!(WhatsappHybrid::FotoDoContato::FLAG)
      connection.update!(paused_at: nil)
      allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING' })
      Redis::Alfred.delete(WhatsappHybrid::FotoDoContato.chave_do_dia(connection.session_name))
      cenario.call

      expect { described_class.perform_now }.not_to have_enqueued_job(WhatsappHybrid::FotoDoContatoJob)
    end
    expect(Redis::Alfred.exists?(feito)).to be(false)
  end

  it 'erro numa caixa não para as outras e não marca como feita' do
    allow(client).to receive(:get_session).and_raise(Waha::Client::Timeout, 'sem resposta')
    contato_com_conversa('+5511900000008', 1.hour.ago)

    expect { described_class.perform_now }.not_to raise_error
    expect(Redis::Alfred.exists?(feito)).to be(false)
  end
end
