require 'rails_helper'

# #1984 — Sim / Talvez / Não ao convite de reunião: pela agenda (Microsoft, Google) ou por e-mail iMIP.
RSpec.describe ConversaCanal::RespostaDoConvite do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:channel) do
    create(:channel_email, account: account, email: 'vendas@empresa.example', smtp_enabled: true, smtp_address: 'smtp.empresa.example',
                           smtp_port: 465, smtp_login: 'vendas@empresa.example', smtp_password: 'senha-de-teste',
                           smtp_enable_ssl_tls: true, smtp_authentication: 'login')
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:convite) do
    { 'uid' => 'uid-1@google.com', 'sequencia' => 1, 'metodo' => 'REQUEST', 'titulo' => 'Alinhamento',
      'dia_inteiro' => false, 'inicio' => 2.days.from_now.to_i, 'fim' => (2.days.from_now + 1.hour).to_i,
      'organizador' => { 'nome' => 'Diana', 'email' => 'diana@agencia.example' },
      'convidados' => [{ 'email' => 'diana@agencia.example', 'resposta' => 'ACCEPTED' },
                       { 'email' => 'vendas@empresa.example', 'resposta' => 'NEEDS-ACTION' }] }
  end
  let(:message) do
    create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :incoming,
                     content_attributes: { email: { message_id: 'abc@mail.example', convite: convite } })
  end
  let(:smtp) { instance_double(Mail::SMTP, deliver!: true) }

  before do
    account.enable_features!('convite_da_reuniao')
    # Só o SMTP da caixa do teste vira dublê: o envio padrão global do Mail (criado no primeiro Mail.new do processo)
    # segue real, senão o dublê fica guardado nele e vaza para os specs seguintes.
    allow(Mail::SMTP).to receive(:new).and_call_original
    allow(Mail::SMTP).to receive(:new).with(hash_including(address: 'smtp.empresa.example')).and_return(smtp)
    allow(Mail::SMTP).to receive(:new).with(hash_including(address: 'smtp.gmail.com')).and_return(smtp)
  end

  def responder(resposta = 'aceito')
    described_class.new(message: message, resposta: resposta, user: user).perform
  end

  def token_de(servico, valor)
    allow(servico).to receive(:new).and_return(instance_double(servico, access_token: valor))
  end

  def convite_gravado
    message.reload.content_attributes['email']['convite']
  end

  describe 'caixa sem agenda: e-mail iMIP ao organizador' do
    it 'manda o REPLY com a situação da caixa e grava a resposta', :aggregate_failures do
      responder('talvez')

      expect(Mail::SMTP).to have_received(:new).with(hash_including(address: 'smtp.empresa.example', port: 465, tls: true))
      expect(smtp).to have_received(:deliver!) do |mail|
        expect(mail.to).to eq(['diana@agencia.example'])
        expect(mail.from).to eq(['vendas@empresa.example'])
        expect(mail.mime_type).to eq('multipart/alternative')
        calendario = mail.parts.find { |parte| parte.mime_type == 'text/calendar' }
        expect(calendario.content_type).to include('method=REPLY')
        evento = Icalendar::Calendar.parse(calendario.decoded).first.events.first
        expect([evento.uid.to_s, evento.sequence.to_i]).to eq(['uid-1@google.com', 1])
        expect(evento.attendee.first.to_s).to eq('mailto:vendas@empresa.example')
        expect(evento.attendee.first.ical_params['partstat']).to eq(['TENTATIVE'])
      end
      expect(convite_gravado).to include('minha_resposta' => 'talvez', 'via' => 'email', 'respondida_por' => user.id)
      expect(convite_gravado['uid']).to eq('uid-1@google.com')
    end

    it 'caixa só de encaminhamento não responde e nada é gravado', :aggregate_failures do
      channel.update!(smtp_enabled: false)

      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.sem_envio'))
      expect(convite_gravado).not_to have_key('minha_resposta')
    end

    it 'servidor de e-mail fora: falha no envio e nada é gravado', :aggregate_failures do
      allow(smtp).to receive(:deliver!).and_raise(Net::ReadTimeout)

      expect { responder }.to raise_error(described_class::FalhaNoEnvio)
      expect(convite_gravado).not_to have_key('minha_resposta')
    end
  end

  describe 'Google com a agenda ligada' do
    let(:eventos) { 'https://www.googleapis.com/calendar/v3/calendars/primary/events' }

    before do
      channel.update!(provider: 'google', calendar_enabled: true, imap_login: 'vendas@empresa.example')
      token_de(Google::CalendarAccessTokenService, 'token-google')
    end

    it 'muda só a situação da caixa no evento achado pelo UID', :aggregate_failures do
      stub_request(:get, eventos).with(query: hash_including('iCalUID' => 'uid-1@google.com'))
                                 .to_return(body: { items: [{ id: 'ev/1', status: 'confirmed', organizer: { email: 'Diana@Agencia.example' },
                                                              attendees: [{ email: 'vendas@empresa.example', self: true }] }] }.to_json)
      patch = stub_request(:patch, "#{eventos}/ev%2F1?sendUpdates=all")
              .with(body: { attendeesOmitted: true, attendees: [{ email: 'vendas@empresa.example', responseStatus: 'declined' }] })
              .to_return(body: '{}')

      responder('recusado')

      expect(patch).to have_been_requested
      expect(smtp).not_to have_received(:deliver!)
      expect(convite_gravado).to include('minha_resposta' => 'recusado', 'via' => 'agenda')
    end

    it 'evento fora da agenda: responde por e-mail', :aggregate_failures do
      stub_request(:get, eventos).with(query: hash_including({})).to_return(body: { items: [] }.to_json)
      token_de(Google::RefreshOauthTokenService, 'token-smtp')

      responder

      expect(Mail::SMTP).to have_received(:new).with(hash_including(address: 'smtp.gmail.com', authentication: 'xoauth2'))
      expect(convite_gravado).to include('minha_resposta' => 'aceito', 'via' => 'email')
    end

    it 'evento com o mesmo UID mas de outro organizador não é respondido: vai por e-mail', :aggregate_failures do
      stub_request(:get, eventos).with(query: hash_including('iCalUID' => 'uid-1@google.com'))
                                 .to_return(body: { items: [{ id: 'real', status: 'confirmed',
                                                              organizer: { email: 'chefe@outra.example' } }] }.to_json)
      token_de(Google::RefreshOauthTokenService, 'token-smtp')

      responder

      expect(a_request(:patch, "#{eventos}/real").with(query: hash_including({}))).not_to have_been_made
      expect(convite_gravado).to include('via' => 'email')
    end

    it 'caixa sem marca de própria no evento (convite por grupo): responde por e-mail, sem se acrescentar', :aggregate_failures do
      stub_request(:get, eventos).with(query: hash_including('iCalUID' => 'uid-1@google.com'))
                                 .to_return(body: { items: [{ id: 'ev1', status: 'confirmed', organizer: { email: 'diana@agencia.example' },
                                                              attendees: [{ email: 'equipe@empresa.example' }] }] }.to_json)
      token_de(Google::RefreshOauthTokenService, 'token-smtp')

      responder

      expect(a_request(:patch, "#{eventos}/ev1").with(query: hash_including({}))).not_to have_been_made
      expect(convite_gravado['via']).to eq('email')
    end

    it 'token da agenda revogado: falha no envio (502), não erro 500', :aggregate_failures do
      allow(Google::CalendarAccessTokenService).to receive(:new).and_raise(StandardError, 'invalid_grant')

      expect { responder }.to raise_error(described_class::FalhaNoEnvio)
      expect(convite_gravado).not_to have_key('minha_resposta')
    end

    it 'Google recusou: falha no envio e nada é gravado', :aggregate_failures do
      stub_request(:get, eventos).with(query: hash_including({})).to_return(status: 403, body: '{}')

      expect { responder }.to raise_error(described_class::FalhaNoEnvio)
      expect(convite_gravado).not_to have_key('minha_resposta')
    end
  end

  describe 'Microsoft com a agenda ligada' do
    let(:graph) { 'https://graph.microsoft.com/v1.0/me' }
    let(:da_diana) { { organizer: { emailAddress: { address: 'Diana@Agencia.example' } } } }

    before do
      channel.update!(provider: 'microsoft', calendar_enabled: true)
      token_de(Microsoft::GraphTokenService, 'token-graph')
    end

    def mensagem_do_convite(evento)
      stub_request(:get, "#{graph}/messages")
        .with(query: hash_including('$filter' => "internetMessageId eq '<abc@mail.example>'", '$select' => 'id'))
        .to_return(body: { value: [{ id: 'msg/1' }] }.to_json)
      stub_request(:get, "#{graph}/messages/msg%2F1")
        .with(query: { '$expand' => 'microsoft.graph.eventMessage/event($select=id,organizer)' })
        .to_return(body: { id: 'msg/1', event: evento }.to_json)
    end

    def sem_mensagem_e_eventos(eventos)
      stub_request(:get, "#{graph}/messages").with(query: hash_including('$select' => 'id')).to_return(body: { value: [] }.to_json)
      stub_request(:get, "#{graph}/events").with(query: hash_including('$filter' => "iCalUId eq 'uid-1@google.com'"))
                                           .to_return(body: { value: eventos }.to_json)
    end

    it 'acha o evento pelo e-mail do convite e aceita avisando o organizador', :aggregate_failures do
      mensagem_do_convite(da_diana.merge(id: 'ev-1'))
      aceite = stub_request(:post, "#{graph}/events/ev-1/accept").with(body: { sendResponse: true }).to_return(status: 202)

      responder

      expect(aceite).to have_been_requested
      expect(convite_gravado).to include('minha_resposta' => 'aceito', 'via' => 'agenda')
    end

    it 'sem o e-mail na caixa, acha o evento pelo UID' do
      sem_mensagem_e_eventos([da_diana.merge(id: 'ev-2')])
      talvez = stub_request(:post, "#{graph}/events/ev-2/tentativelyAccept").to_return(status: 202)

      responder('talvez')

      expect(talvez).to have_been_requested
    end

    it 'organizador que não pede resposta: responde sem aviso' do
      mensagem_do_convite(da_diana.merge(id: 'ev-1'))
      stub_request(:post, "#{graph}/events/ev-1/decline").with(body: { sendResponse: true }).to_return(status: 400)
      sem_aviso = stub_request(:post, "#{graph}/events/ev-1/decline").with(body: { sendResponse: false }).to_return(status: 202)

      responder('recusado')

      expect(sem_aviso).to have_been_requested
      expect(convite_gravado['via']).to eq('agenda_sem_aviso')
    end

    it 'evento de outro organizador: responde por e-mail pelo Graph, sem tocar no evento', :aggregate_failures do
      sem_mensagem_e_eventos([{ id: 'real', organizer: { emailAddress: { address: 'x@outra.example' } } }])
      envio = stub_request(:post, "#{graph}/sendMail").to_return(status: 202)

      responder

      expect(envio).to have_been_requested
      expect(a_request(:post, "#{graph}/events/real/accept")).not_to have_been_made
      expect(convite_gravado).to include('via' => 'email')
    end

    it 'ocorrência de série sem o e-mail na caixa: não usa o UID da série', :aggregate_failures do
      convite['ocorrencia'] = convite['inicio']
      stub_request(:get, "#{graph}/messages").with(query: hash_including('$select' => 'id')).to_return(body: { value: [] }.to_json)
      envio = stub_request(:post, "#{graph}/sendMail").to_return(status: 202)

      responder

      expect(envio).to have_been_requested
      expect(a_request(:get, "#{graph}/events").with(query: hash_including({}))).not_to have_been_made
    end

    it 'Graph recusou o aceite: falha no envio e nada é gravado', :aggregate_failures do
      mensagem_do_convite(da_diana.merge(id: 'ev-1'))
      stub_request(:post, "#{graph}/events/ev-1/accept").to_return(status: 403)

      expect { responder }.to raise_error(described_class::FalhaNoEnvio)
      expect(convite_gravado).not_to have_key('minha_resposta')
    end
  end

  describe 'ocorrência de uma série' do
    it 'vai por e-mail com o RECURRENCE-ID, mesmo com a agenda do Google ligada', :aggregate_failures do
      convite['ocorrencia'] = convite['inicio']
      channel.update!(provider: 'google', calendar_enabled: true)
      token_de(Google::RefreshOauthTokenService, 'token-smtp')

      responder

      expect(smtp).to have_received(:deliver!) do |mail|
        evento = Icalendar::Calendar.parse(mail.parts.last.decoded).first.events.first
        expect(evento.recurrence_id.to_time.to_i).to eq(convite['inicio'])
      end
      expect(convite_gravado['via']).to eq('email')
    end

    it 'ocorrência sem fuso volta com o RECURRENCE-ID como veio (#1995)', :aggregate_failures do
      convite['ocorrencia'] = convite['inicio']
      convite['ocorrencia_original'] = { 'valor' => '20261029T130000', 'tzid' => 'Fuso Inventado' }

      responder

      expect(smtp).to have_received(:deliver!) do |mail|
        expect(mail.parts.last.decoded).to include('RECURRENCE-ID;TZID=Fuso Inventado:20261029T130000')
      end
    end
  end

  describe 'uma resposta por vez (#1995)' do
    let(:chave) { format(described_class::CHAVE_DA_TRAVA, message_id: message.id) }

    it 'com outra resposta saindo, recusa e não manda nada', :aggregate_failures do
      Redis::LockManager.new.lock(chave, 60)

      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.em_andamento'))
      expect(smtp).not_to have_received(:deliver!)
    ensure
      Redis::LockManager.new.unlock(chave)
    end

    it 'solta a trava depois de responder, e também depois de uma recusa', :aggregate_failures do
      responder('aceito')
      expect { responder('quem_sabe') }.to raise_error(described_class::Recusa)
      responder('recusado')

      expect(smtp).to have_received(:deliver!).twice
      expect(Redis::LockManager.new.locked?(chave)).to be(false)
    end

    it 'Redis caindo ao soltar a trava não troca a resposta que já saiu', :aggregate_failures do
      trava = instance_double(Redis::LockManager, lock: true)
      allow(trava).to receive(:unlock).and_raise(Redis::CannotConnectError)
      allow(Redis::LockManager).to receive(:new).and_return(trava)

      expect(responder['minha_resposta']).to eq('aceito')
      expect(smtp).to have_received(:deliver!).once
    end

    it 'Redis fora do ar ao pegar a trava: falha no envio (502), nada sai', :aggregate_failures do
      trava = instance_double(Redis::LockManager)
      allow(trava).to receive(:lock).and_raise(Redis::CannotConnectError)
      allow(Redis::LockManager).to receive(:new).and_return(trava)

      expect { responder }.to raise_error(described_class::FalhaNoEnvio)
      expect(smtp).not_to have_received(:deliver!)
    end

    it 'relê a mensagem: a resposta que outro atendente acabou de gravar não sai de novo', :aggregate_failures do
      servico = described_class.new(message: Message.find(message.id), resposta: 'aceito', user: user)
      responder('aceito')

      servico.perform

      expect(smtp).to have_received(:deliver!).once
    end
  end

  describe 'a mesma resposta de novo' do
    it 'não manda outro e-mail' do
      responder
      responder

      expect(smtp).to have_received(:deliver!).once
    end
  end

  describe 'recusas' do
    it 'convite que o organizador mudou ou cancelou num e-mail mais novo (#1995)', :aggregate_failures do
      convite['substituido_por'] = 123

      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.substituido'))
      expect(smtp).not_to have_received(:deliver!)
    end

    it 'série que já acabou (#1995)' do
      convite.merge!('recorrente' => true, 'inicio' => 3.weeks.ago.to_i, 'fim' => (3.weeks.ago + 1.hour).to_i,
                     'fim_da_serie' => 1.day.ago.to_i)
      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.ja_passou'))
    end

    it 'série sem fim segue respondível depois da primeira ocorrência' do
      convite.merge!('recorrente' => true, 'inicio' => 3.weeks.ago.to_i, 'fim' => (3.weeks.ago + 1.hour).to_i)
      expect(responder['minha_resposta']).to eq('aceito')
    end

    it 'reunião que já terminou' do
      convite['inicio'] = 2.hours.ago.to_i
      convite['fim'] = 1.hour.ago.to_i
      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.ja_passou'))
    end

    it 'convite sem organizador válido' do
      convite['organizador'] = { 'nome' => 'Financeiro' }
      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.sem_convite'))
    end

    it 'sem a chave da conta' do
      account.disable_features!('convite_da_reuniao')
      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.sem_chave'))
    end

    it 'resposta fora da lista' do
      expect { responder('quem_sabe') }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.resposta_invalida'))
    end

    it 'convite cancelado' do
      convite['metodo'] = 'CANCEL'
      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.sem_convite'))
    end

    it 'mensagem enviada pela empresa' do
      message.update!(message_type: :outgoing)
      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.sem_convite'))
    end

    it 'caixa fora da lista de convidados (em cópia)', :aggregate_failures do
      convite['convidados'] = [{ 'email' => 'outra@empresa.example' }]

      expect { responder }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.convite.nao_convidada'))
      expect(smtp).not_to have_received(:deliver!)
    end

    it 'convidada pelo endereço da agenda ligada à caixa' do
      channel.update!(calendar_identity: 'agenda@empresa.example')
      convite['convidados'] = [{ 'email' => 'Agenda@Empresa.example' }]

      expect(responder['minha_resposta']).to eq('aceito')
    end
  end
end
