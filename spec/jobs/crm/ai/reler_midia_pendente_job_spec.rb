require 'rails_helper'

# #2109: a varredura relê, pelo job da chegada, o áudio e a foto sem texto dos últimos 2 dias, sem falha definitiva.
RSpec.describe Crm::Ai::RelerMidiaPendenteJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account)) }
  let(:credencial) { { api_key: 'k', source: 'teste' } }

  def mensagem(idade: 1.hour, privada: false, caixa: inbox, conversa: conversation)
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, private: privada,
                     created_at: idade.ago)
  end

  def enfileiradas = enqueued_jobs.select { |job| job['job_class'] == 'Crm::Ai::LerMidiaJob' }.map { |job| job['arguments'].first }

  before do
    limpar_redis_do_leitor
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true,
                                                                                                                resolve: credencial))
    account.enable_features!(Crm::Ai::LeitorDeMidia::FLAG)
    account.crm_inbox_settings.find_or_initialize_by(inbox: inbox).update!(crm_enabled: true)
    clear_enqueued_jobs
  end

  it 'dentro da janela de 48 h: relê o pendente, o que venceu a espera e o marcado sem texto antes do #2109', :aggregate_failures do
    pendente = anexar_audio(mensagem).message
    venceu = anexar_audio(mensagem, meta: { 'crm_ai_midia_tentativas' => 2, 'crm_ai_midia_proxima_em' => 1.minute.ago.iso8601 }).message
    antes_do_pr = anexar_audio(mensagem(idade: 40.hours), meta: { 'crm_ai_audio_done' => true }).message

    described_class.perform_now

    expect(enfileiradas).to contain_exactly(pendente.id, venceu.id, antes_do_pr.id)
  end

  it 'fora da janela (mais de 48 h e a margem), não relê' do
    anexar_audio(mensagem(idade: 3.days), meta: { 'crm_ai_audio_done' => true })
    anexar_audio(mensagem(idade: 3.days))

    described_class.perform_now

    expect(enfileiradas).to be_empty
  end

  it 'não relê o lido, a falha definitiva, o expirado, o que espera a próxima tentativa, o recente, o privado e o PDF', :aggregate_failures do
    anexar_audio(mensagem, meta: { 'transcribed_text' => 'já lido' })
    (Crm::Ai::FalhaDaMidia::FALHAS_DEFINITIVAS + ['expirado']).each do |falha|
      anexar_audio(mensagem, meta: { 'crm_ai_audio_done' => true, 'crm_ai_midia_falha' => falha })
    end
    anexar_audio(mensagem, meta: { 'crm_ai_midia_tentativas' => 1, 'crm_ai_midia_proxima_em' => 10.minutes.from_now.iso8601 })
    anexar_audio(mensagem(idade: 5.minutes))
    anexar_audio(mensagem(privada: true))
    anexar_pdf(mensagem, 'Texto')

    described_class.perform_now

    expect(enfileiradas).to be_empty
  end

  it 'caixa sem CRM, conta sem a flag ou sem credencial: não enfileira', :aggregate_failures do
    outra = create(:inbox, account: account)
    anexar_audio(mensagem(caixa: outra, conversa: create(:conversation, account: account, inbox: outra)))
    described_class.perform_now
    expect(enfileiradas).to be_empty

    anexar_audio(mensagem)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, configured?: false))
    described_class.perform_now
    expect(enfileiradas).to be_empty

    account.disable_features!(Crm::Ai::LeitorDeMidia::FLAG)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true))
    described_class.perform_now
    expect(enfileiradas).to be_empty
  end

  it 'enfileira no modo varredura e não relê o expirado que está na mesma mensagem de um pendente', :aggregate_failures do
    allow(Crm::Ai::TranscriptionClient).to receive(:new).and_return(instance_double(Crm::Ai::TranscriptionClient, transcribe: 'texto'))
    chegada = mensagem
    pendente = anexar_audio(chegada)
    expirado = anexar_audio(chegada, meta: { 'crm_ai_audio_done' => true, 'crm_ai_midia_falha' => 'expirado' })

    described_class.perform_now
    expect(enqueued_jobs.last['arguments']).to eq([chegada.id, 'varredura'])
    perform_enqueued_jobs(only: Crm::Ai::LerMidiaJob)

    expect(pendente.reload.meta['transcribed_text']).to eq('texto')
    expect(expirado.reload.meta).not_to have_key('transcribed_text')
  end

  it 'mensagem cujo áudio sem texto passa do teto por mensagem não ocupa vaga da rodada' do
    stub_const("#{described_class}::MAX_MENSAGENS_POR_CONTA", 1)
    stub_const("#{described_class}::LOTE", 1)
    pendente = anexar_audio(mensagem(idade: 2.hours)).message
    cheia = mensagem
    Array.new(3) { anexar_audio(cheia, meta: { 'transcribed_text' => 'lido' }) }
    anexar_audio(cheia)

    described_class.perform_now

    expect(enfileiradas).to eq([pendente.id])
  end

  it 'dentro do lote, também as mais novas primeiro (o default_scope de Message ordena crescente)' do
    stub_const("#{described_class}::MAX_MENSAGENS_POR_CONTA", 1)
    anexar_audio(mensagem(idade: 3.hours))
    nova = anexar_audio(mensagem(idade: 1.hour)).message

    described_class.perform_now

    expect(enfileiradas).to eq([nova.id])
  end

  it 'enfileira na fila low e não enfileira de novo a mesma mensagem enquanto a anterior pode estar na fila', :aggregate_failures do
    pendente = anexar_audio(mensagem).message

    described_class.perform_now
    described_class.perform_now

    expect(Crm::Ai::LerMidiaJob).to have_been_enqueued.with(pendente.id, 'varredura').on_queue('low').once
  end

  it 'conta que já gastou a fração do teto do dia reservada à releitura: não enfileira' do
    anexar_audio(mensagem)
    usado = (Crm::Ai::LeitorDeMidia::MAX_LEITURAS_POR_DIA * described_class::FRACAO_DO_TETO).floor
    usado.times { Crm::Ai::TetoDaMidia.new(account).somar }

    described_class.perform_now

    expect(enfileiradas).to be_empty
  end

  it 'só a mensagem de entrada: a mídia que a equipe mandou não é relida' do
    anexar_audio(create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                  created_at: 1.hour.ago))

    described_class.perform_now

    expect(enfileiradas).to be_empty
  end

  # Pega: conta grande cuja janela não cabe nos MAX_LOTES lotes ficar sem leitura sem ninguém saber.
  describe 'quando os lotes acabam' do
    before do
      stub_const("#{described_class}::LOTE", 2)
      stub_const("#{described_class}::MAX_LOTES", 2)
      allow(Rails.logger).to receive(:warn)
    end

    it 'antes do fim da janela: avisa no log com a conta e a data até onde chegou' do
      Array.new(5) { |i| mensagem(idade: (i + 1).hours) }

      described_class.perform_now

      expect(Rails.logger).to have_received(:warn).with(a_string_including("varredura_cortada conta=#{account.id} lotes=2 ate="))
    end

    # 4 = LOTE x MAX_LOTES: a última página vem cheia, mas a janela acabou junto (pega o falso aviso na borda).
    [3, 4].each do |total|
      it "com o fim da janela (#{total} mensagens): não avisa" do
        Array.new(total) { |i| mensagem(idade: (i + 1).hours) }

        described_class.perform_now

        expect(Rails.logger).not_to have_received(:warn).with(a_string_including('varredura_cortada'))
      end
    end
  end

  # Pega: uma conta com erro derrubar a rodada inteira (as outras ficariam sem releitura) ou o erro sumir sem log.
  describe 'quando uma conta falha' do
    let(:outra) { create(:account) }
    let(:da_outra) do
      caixa = create_crm_inbox(account: outra)
      outra.crm_inbox_settings.find_or_initialize_by(inbox: caixa).update!(crm_enabled: true)
      conversa = create_crm_conversation(account: outra, inbox: caixa, contact: create(:contact, account: outra))
      anexar_audio(create(:message, account: outra, inbox: caixa, conversation: conversa, message_type: :incoming,
                                    created_at: 1.hour.ago)).message
    end
    let!(:minha) { anexar_audio(mensagem).message }

    before do
      outra.enable_features!(Crm::Ai::LeitorDeMidia::FLAG)
      da_outra
      allow(Rails.logger).to receive(:warn)
    end

    it 'consulta que estoura o tempo: pula a conta, avisa e segue nas outras', :aggregate_failures do
      allow(Crm::Ai::TetoDaMidia).to receive(:new).and_call_original
      allow(Crm::Ai::TetoDaMidia).to receive(:new).with(account).and_raise(ActiveRecord::QueryCanceled, 'statement timeout')

      expect { described_class.perform_now }.not_to raise_error
      expect(enfileiradas).to eq([da_outra.id])
      expect(Rails.logger).to have_received(:warn).with("[crm][midia] varredura_pulou conta=#{account.id} erro=ActiveRecord::QueryCanceled")
    end

    it 'Redis fora: pula a conta, avisa e segue nas outras', :aggregate_failures do
      allow(Crm::Ai::LerMidiaJob).to receive(:reler).and_call_original
      allow(Crm::Ai::LerMidiaJob).to receive(:reler).with(minha.id, 'varredura').and_raise(Redis::CannotConnectError)

      expect { described_class.perform_now }.not_to raise_error
      expect(enfileiradas).to eq([da_outra.id])
      expect(Rails.logger).to have_received(:warn).with("[crm][midia] varredura_pulou conta=#{account.id} erro=Redis::CannotConnectError")
    end

    it 'erro fora da lista (de programação) sobe: não é engolido' do
      allow(Crm::Ai::TetoDaMidia).to receive(:new).and_raise(NoMethodError)

      expect { described_class.perform_now }.to raise_error(NoMethodError)
    end
  end

  it 'respeita o teto de mensagens por conta em cada rodada' do
    stub_const("#{described_class}::MAX_MENSAGENS_POR_CONTA", 2)
    Array.new(3) { anexar_audio(mensagem) }

    described_class.perform_now

    expect(enfileiradas.size).to eq(2)
  end

  it 'a releitura enfileirada transcreve o marcado sem texto antes do #2109 (ponta a ponta)', :aggregate_failures do
    allow(Crm::Ai::TranscriptionClient).to receive(:new).and_return(instance_double(Crm::Ai::TranscriptionClient, transcribe: 'texto'))
    audio = anexar_audio(mensagem, meta: { 'crm_ai_audio_done' => true })

    perform_enqueued_jobs { described_class.perform_now }

    expect(audio.reload.meta).to include('transcribed_text' => 'texto', 'crm_ai_audio_done' => true)
  end
end
