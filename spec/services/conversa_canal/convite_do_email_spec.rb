require 'rails_helper'

# #1984 — o convite de reunião que chega como parte text/calendar do e-mail.
RSpec.describe ConversaCanal::ConviteDoEmail do
  def email_com(ics, tipo: 'text/calendar; method=REQUEST; charset=UTF-8')
    mail = Mail.new(from: 'organizador@example.com', to: 'vendas@empresa.example', subject: 'Convite')
    mail.text_part = Mail::Part.new(content_type: 'text/plain; charset=UTF-8', body: 'Você foi convidado.')
    mail.html_part = Mail::Part.new(content_type: 'text/html; charset=UTF-8', body: '<p>Você foi convidado.</p>')
    mail.add_part(Mail::Part.new(content_type: tipo, body: ics))
    mail
  end

  def ics(nome)
    Rails.root.join('spec/fixtures/files/convites', "#{nome}.ics").read
  end

  it 'lê o convite do Outlook com o fuso do Windows e o link do Teams', :aggregate_failures do
    convite = described_class.ler(email_com(ics('outlook_teams')))

    expect(convite[:metodo]).to eq('REQUEST')
    expect(convite[:uid]).to start_with('040000008200E000')
    expect(convite[:sequencia]).to eq(2)
    expect(convite[:titulo]).to eq('CRM - Novo Layout')
    expect(convite[:inicio]).to eq(Time.utc(2026, 10, 21, 19).to_i)
    expect(convite[:fim]).to eq(Time.utc(2026, 10, 21, 19, 30).to_i)
    expect(convite[:dia_inteiro]).to be(false)
    expect(convite[:link]).to eq('https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0')
    expect(convite[:organizador]).to eq(nome: 'Bruna Organizadora', email: 'bruna@corretora.example')
    expect(convite[:convidados]).to eq([
                                         { nome: 'Carlos Cliente', email: 'carlos@cliente.example', resposta: 'NEEDS-ACTION' },
                                         { email: 'comercial@empresa.example', resposta: 'NEEDS-ACTION' }
                                       ])
  end

  it 'lê o convite do Google Agenda com o link do Meet', :aggregate_failures do
    convite = described_class.ler(email_com(ics('google_meet')))

    expect(convite[:uid]).to eq('7kq2abc123def456@google.com')
    expect(convite[:inicio]).to eq(Time.utc(2026, 10, 22, 13).to_i)
    expect(convite[:link]).to eq('https://meet.google.com/abc-defg-hij')
    expect(convite).not_to have_key(:local)
    expect(convite[:convidados].pluck(:email)).to eq(%w[diana@agencia.example vendas@empresa.example])
  end

  it 'lê o cancelamento' do
    expect(described_class.ler(email_com(ics('cancelado'), tipo: 'text/calendar; method=CANCEL'))[:metodo]).to eq('CANCEL')
  end

  it 'guarda o dia inteiro ao meio-dia UTC, para nenhum fuso trocar a data', :aggregate_failures do
    convite = described_class.ler(email_com(ics('dia_inteiro')))

    expect(convite[:dia_inteiro]).to be(true)
    expect(convite[:inicio]).to eq(Time.utc(2026, 11, 5, 12).to_i)
    expect(convite[:fim]).to eq(Time.utc(2026, 11, 6, 12).to_i)
    expect(convite[:local]).to eq('Sala 2')
    expect(convite).not_to have_key(:link)
  end

  it 'acha o convite mandado como anexo application/ics' do
    expect(described_class.ler(email_com(ics('google_meet'), tipo: 'application/ics'))[:uid]).to eq('7kq2abc123def456@google.com')
  end

  it 'ignora a resposta de outra pessoa (REPLY)' do
    expect(described_class.ler(email_com(ics('resposta')))).to be_nil
  end

  it 'e-mail sem convite fica como estava' do
    expect(described_class.ler(Mail.new(from: 'a@example.com', to: 'b@example.com', body: 'Oi'))).to be_nil
  end

  it 'convite ilegível não quebra o recebimento' do
    expect(described_class.ler(email_com("BEGIN:VCALENDAR\nISSO NAO E UM CALENDARIO"))).to be_nil
  end

  it 'convite grande demais fica sem cartão' do
    expect(described_class.ler(email_com(ics('google_meet') + ('X' * 300.kilobytes)))).to be_nil
  end

  it 'link de chamada só de aplicativo conhecido e em https' do
    texto = ics('dia_inteiro').sub('LOCATION:Sala 2', 'LOCATION:http://zoom.us/j/1 https://zoom.us.golpe.example/j/2')
    expect(described_class.ler(email_com(texto))).not_to have_key(:link)
  end

  it 'o campo próprio do link também só vale para aplicativo conhecido' do
    texto = ics('google_meet').sub('X-GOOGLE-CONFERENCE:https://meet.google.com/abc-defg-hij',
                                   'X-GOOGLE-CONFERENCE:https://login-microsoft.example/entrar')
    expect(described_class.ler(email_com(texto))[:link]).to eq('https://meet.google.com/abc-defg-hij')
  end

  it 'organizador com lista ou grupo de endereços fica sem e-mail (a resposta não vira disparo)', :aggregate_failures do
    ['mailto:a@x.example,b@vitima.example', 'mailto:lista: a@x.example, b@vitima.example;'].each do |organizador|
      texto = ics('google_meet').sub('ORGANIZER;CN=Diana Dona:mailto:diana@agencia.example', "ORGANIZER;CN=Financeiro:#{organizador}")
      expect(described_class.ler(email_com(texto))[:organizador]).not_to have_key(:email)
    end
  end

  it 'convidado com endereço inválido fica de fora' do
    texto = ics('dia_inteiro').sub('ATTENDEE;PARTSTAT=NEEDS-ACTION:mailto:vendas@empresa.example',
                                   "ATTENDEE:mailto:a@x.example,b@y.example\nATTENDEE:mailto:vendas@empresa.example")
    expect(described_class.ler(email_com(texto))[:convidados].pluck(:email)).to eq(['vendas@empresa.example'])
  end

  it 'série e ocorrência: marca a série e guarda o RECURRENCE-ID', :aggregate_failures do
    serie = ics('dia_inteiro').sub('SEQUENCE:0', "SEQUENCE:0\nRRULE:FREQ=WEEKLY")
    expect(described_class.ler(email_com(serie))[:recorrente]).to be(true)

    ocorrencia = ics('google_meet').sub('SEQUENCE:0', "SEQUENCE:0\nRECURRENCE-ID:20261029T130000Z")
    expect(described_class.ler(email_com(ocorrencia))[:ocorrencia]).to eq(Time.utc(2026, 10, 29, 13).to_i)
  end

  describe 'fim da série (#1995): limite por cima, sem percorrer as ocorrências' do
    def serie(regra, inicio: 'DTSTART:20261022T130000Z')
      ics('google_meet').sub('DTSTART:20261022T130000Z', inicio).sub('SEQUENCE:0', "SEQUENCE:0\nRRULE:#{regra}")
    end

    def fim_da_serie(regra, **)
      described_class.ler(email_com(serie(regra, **)))[:fim_da_serie]
    end

    it 'COUNT: o começo mais COUNT períodos, e a duração da reunião', :aggregate_failures do
      expect(fim_da_serie('FREQ=DAILY;COUNT=3')).to eq(Time.utc(2026, 10, 25, 14).to_i)
      expect(fim_da_serie('FREQ=WEEKLY;INTERVAL=2;COUNT=2')).to eq(Time.utc(2026, 11, 19, 14).to_i)
      # Quinta 22/10, segunda e quarta, 4 vezes (última em 4/11): duas semanas cheias, mais uma de folga.
      expect(fim_da_serie('FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4')).to eq(Time.utc(2026, 11, 12, 14).to_i)
    end

    it 'UNTIL: até o UNTIL, mais a duração', :aggregate_failures do
      expect(fim_da_serie('FREQ=DAILY;UNTIL=20261025T130000Z')).to eq(Time.utc(2026, 10, 25, 14).to_i)
      # Só com data: o dia todo, até onde ele termina no fuso mais a oeste (UTC-12).
      expect(fim_da_serie('FREQ=WEEKLY;UNTIL=20261029')).to eq(Time.utc(2026, 10, 30, 12, 59, 59).to_i)
      # Sem o Z (flutuante): o horário no fuso mais a oeste.
      expect(fim_da_serie('FREQ=DAILY;UNTIL=20261025T130000')).to eq(Time.utc(2026, 10, 26, 2).to_i)
    end

    it 'dia inteiro com UNTIL no mesmo dia não vira reunião que já passou' do
      texto = ics('dia_inteiro').sub('SEQUENCE:0', "SEQUENCE:0\nRRULE:FREQ=WEEKLY;UNTIL=20261105")
      expect(described_class.ler(email_com(texto))[:fim_da_serie]).to be > Time.utc(2026, 11, 5, 12).to_i
    end

    it 'o limite sai no fuso do convite (VTIMEZONE do Outlook)' do
      # Sexta 23/10 às 22h em São Paulo (sábado 01h UTC), 2 vezes: a última é 30/10; o limite, 06/11 às 22h30 de lá.
      texto = ics('outlook_teams').sub(/^DTSTART;.*$/, 'DTSTART;TZID=E. South America Standard Time:20261023T220000')
                                  .sub(/^DTEND;.*$/, 'DTEND;TZID=E. South America Standard Time:20261023T223000')
                                  .sub('SEQUENCE:2', "SEQUENCE:2\nRRULE:FREQ=WEEKLY;BYDAY=FR;COUNT=2")
      expect(described_class.ler(email_com(texto))[:fim_da_serie]).to eq(Time.utc(2026, 11, 7, 1, 30).to_i)
    end

    it 'UNTIL antes do começo: o próprio DTSTART ainda é uma ocorrência' do
      expect(fim_da_serie('FREQ=DAILY;UNTIL=20261022T030000Z')).to eq(Time.utc(2026, 10, 22, 14).to_i)
    end

    it 'COUNT com horário sem fuso conta até onde ele pode estar (UTC-12)' do
      expect(fim_da_serie('FREQ=HOURLY;COUNT=2', inicio: 'DTSTART:20261022T130000')).to eq(Time.utc(2026, 10, 23, 4).to_i)
    end

    it 'regra de minuto em minuto até 2099 não trava o recebimento' do
      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(fim_da_serie('FREQ=MINUTELY;UNTIL=20991231T000000Z')).to eq(Time.utc(2099, 12, 31, 1).to_i)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < 1
    end

    it 'regra que pode pular períodos, ou série sem fim, fica sem fim_da_serie', :aggregate_failures do
      expect(fim_da_serie('FREQ=WEEKLY')).to be_nil
      expect(fim_da_serie('FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1;COUNT=6')).to be_nil
      expect(fim_da_serie('FREQ=MONTHLY;BYDAY=2TU;COUNT=3')).to be_nil
      expect(fim_da_serie('FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;COUNT=10')).to be_nil
      expect(fim_da_serie('FREQ=MONTHLY;COUNT=3', inicio: 'DTSTART:20261031T130000Z')).to be_nil
      expect(described_class.ler(email_com(serie('FREQ=WEEKLY;COUNT=2')))[:recorrente]).to be(true)
    end
  end

  it 'ocorrência sem fuso guarda o RECURRENCE-ID como veio (#1995)', :aggregate_failures do
    flutuante = ics('google_meet').sub('SEQUENCE:0', "SEQUENCE:0\nRECURRENCE-ID:20261029T130000")
    expect(described_class.ler(email_com(flutuante))[:ocorrencia_original]).to eq(valor: '20261029T130000')

    inventado = ics('google_meet').sub('SEQUENCE:0', "SEQUENCE:0\nRECURRENCE-ID;TZID=Fuso Inventado:20261029T130000")
    expect(described_class.ler(email_com(inventado))[:ocorrencia_original]).to eq(valor: '20261029T130000', tzid: 'Fuso Inventado')

    com_fuso = ics('google_meet').sub('SEQUENCE:0', "SEQUENCE:0\nRECURRENCE-ID:20261029T130000Z")
    expect(described_class.ler(email_com(com_fuso))).not_to have_key(:ocorrencia_original)
  end

  it 'dia inteiro sem DTEND dura o próprio dia' do
    texto = ics('dia_inteiro').sub("DTEND;VALUE=DATE:20261106\n", '')
    expect(described_class.ler(email_com(texto))[:fim]).to eq(Time.utc(2026, 11, 6, 12).to_i)
  end

  it 'sem DTEND, o fim sai da DURATION' do
    texto = ics('google_meet').sub("DTEND:20261022T140000Z\n", "DURATION:PT45M\n")
    expect(described_class.ler(email_com(texto))[:fim]).to eq(Time.utc(2026, 10, 22, 13, 45).to_i)
  end

  it 'horário sem fuso ou com fuso desconhecido fica marcado', :aggregate_failures do
    expect(described_class.ler(email_com(ics('outlook_teams')))).not_to have_key(:fuso_incerto)
    expect(described_class.ler(email_com(ics('google_meet')))).not_to have_key(:fuso_incerto)
    sem_fuso = ics('google_meet').sub('DTSTART:20261022T130000Z', 'DTSTART:20261022T130000')
    expect(described_class.ler(email_com(sem_fuso))[:fuso_incerto]).to be(true)
    inventado = ics('google_meet').sub('DTSTART:20261022T130000Z', 'DTSTART;TZID=Fuso Inventado:20261022T130000')
    expect(described_class.ler(email_com(inventado))[:fuso_incerto]).to be(true)
  end

  it 'convite sem DTSTART fica sem cartão' do
    expect(described_class.ler(email_com(ics('google_meet').sub("DTSTART:20261022T130000Z\n", '')))).to be_nil
  end

  it 'convite dentro de um e-mail encaminhado como anexo não vira cartão' do
    encaminhado = email_com(ics('google_meet'))
    mail = Mail.new(from: 'colega@empresa.example', to: 'vendas@empresa.example', subject: 'Fwd: convite')
    mail.text_part = Mail::Part.new(content_type: 'text/plain; charset=UTF-8', body: 'Veja abaixo.')
    mail.add_part(Mail::Part.new(content_type: 'message/rfc822', body: encaminhado.to_s))
    expect(described_class.ler(Mail.new(mail.to_s))).to be_nil
  end

  describe 'MailPresenter' do
    it 'põe o convite no serialized_data e lê uma vez só', :aggregate_failures do
      presenter = MailPresenter.new(email_com(ics('google_meet')))
      allow(described_class).to receive(:ler).and_call_original

      2.times { expect(presenter.serialized_data[:convite][:uid]).to eq('7kq2abc123def456@google.com') }
      expect(described_class).to have_received(:ler).once
    end

    it 'sem convite, o serialized_data não ganha a chave' do
      expect(MailPresenter.new(Mail.new(from: 'a@example.com', body: 'Oi')).serialized_data).not_to have_key(:convite)
    end
  end
end
