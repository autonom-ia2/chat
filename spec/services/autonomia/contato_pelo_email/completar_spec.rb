require 'rails_helper'

RSpec.describe Autonomia::ContatoPeloEmail::Completar do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:inbox) { create(:inbox, :with_email, account: account) }
  let(:contact) { create(:contact, account: account, name: 'maria.souza@cliente.com.br', email: 'maria.souza@cliente.com.br') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:corpo) do
    <<~TEXT
      Olá, gostaria de uma cotação de seguro para a minha frota.

      Atenciosamente,
      Maria Souza
      Gerente de Frota
      (11) 98765-4321

      Em seg., 13 de out. de 2026 às 10:00, Corretora <contato@corretora.com.br> escreveu:
      > Prezada, segue a proposta.
      > João Lima - (21) 99999-0000
    TEXT
  end
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:credencial) { { api_key: 'k' } }
  let(:message) { email! }

  def email!(content: corpo, from: 'maria.souza@cliente.com.br', subject: 'Cotação frota', email_extra: {})
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, message_type: :incoming,
                     content_type: 'incoming_email', content: content,
                     content_attributes: { email: { from: Array(from), subject: subject, text_content: { reply: content } }.merge(email_extra) })
  end

  def responde(tipo: 'pessoa', nome: nil, email: nil, telefone: nil)
    allow(cliente).to receive(:create).and_return(text: { tipo: tipo, nome: nome, email: email, telefone: telefone }.to_json)
  end

  def entrada
    args = nil
    expect(cliente).to have_received(:create) { |**recebidos| args = recebidos }
    JSON.parse(args[:input])
  end

  def chave(tipo, id)
    "#{Autonomia::ContatoPeloEmail::Freios::PREFIXO}:#{tipo}:#{id}"
  end

  before do
    Redis::Alfred.scan_each(match: "#{Autonomia::ContatoPeloEmail::Freios::PREFIXO}:*") { |key| Redis::Alfred.delete(key) }
    account.enable_features!(Autonomia::ContatoPeloEmail::FLAG)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  # Pega: o caminho principal quebrar (nome do e-mail inteiro trocado, telefone normalizado).
  it 'e-mail de pessoa com assinatura: o contato com o e-mail no nome ganha nome e telefone (+55)', :aggregate_failures do
    responde(nome: 'Maria Souza', email: 'maria.souza@cliente.com.br', telefone: '(11) 98765-4321')

    described_class.new(message).perform

    expect(contact.reload).to have_attributes(name: 'Maria Souza', phone_number: '+5511987654321', email: 'maria.souza@cliente.com.br')
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'contato_pelo_email', account: account))
  end

  # Pega: a flag desligada entre o enfileirar e o rodar ainda pagar a IA.
  it 'conta sem a flag: o próprio Completar não chama a IA' do
    account.disable_features!(Autonomia::ContatoPeloEmail::FLAG)

    described_class.new(message).perform

    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  # Pega: a resposta de quem está em cópia (gravada em nome do contato pelo MailboxSanitizer) virar dado do dono.
  it 'From que não é do contato (pessoa em cópia): não chama a IA nem grava', :aggregate_failures do
    responde(nome: 'Ana Prado', telefone: '(11) 91111-2222')

    described_class.new(email!(from: 'ana@familia.com.br')).perform

    expect(Crm::Ai::CredentialResolver).not_to have_received(:new)
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    expect(contact.reload).to have_attributes(name: 'maria.souza@cliente.com.br', phone_number: nil)
  end

  # Pega: encaminhamento sem nada escrito pagar a IA para ler o e-mail de outra pessoa.
  it 'texto novo vazio (só histórico citado): não chama a IA' do
    so_citado = "Em seg., 13 de out. de 2026 às 10:00, João <joao@x.com> escreveu:\n> meu telefone é (21) 99999-0000"

    described_class.new(email!(content: so_citado)).perform

    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  # Pega: encaminhamento puro (só o marcador sobra depois do corte) pagar a IA, contar como automático e pausar o
  # contato (backteste da conta 1 da Autonom.ia, 18/10).
  it 'encaminhado sem nada escrito por cima: não chama a IA nem conta para a pausa', :aggregate_failures do
    encaminhado = <<~TEXT
      ---------- Forwarded message ---------
      De: Lead Facebook <leads@facebookmail.com>
      Date: seg., 13 de out. de 2026 às 10:00
      Subject: Novo lead
      To: <maria.souza@cliente.com.br>

      Nome: João Lima
      Telefone: (21) 99999-0000
    TEXT

    3.times { described_class.new(email!(content: encaminhado)).perform }

    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    expect(Redis::Alfred.exists?(chave('pausa', contact.id))).to be(false)
  end

  # Pega: o endereço do contato ir ao modelo (decisão de 03/10), o assunto sem teto e o histórico citado junto.
  it 'manda ao modelo do resumo só subject e body: sem from, assunto em 300, com a assinatura, sem o citado', :aggregate_failures do
    responde
    described_class.new(email!(subject: 'A' * 400)).perform

    expect(cliente).to have_received(:create) do |**args|
      expect(args[:model]).to eq(Crm::Ai::Config::MODEL_SUMMARY)
      expect(args[:timeout]).to eq(Autonomia::ContatoPeloEmail::Leitor::TIMEOUT)
      expect(args[:schema][:schema][:required]).to eq(%w[tipo nome email telefone])
      expect(args[:schema][:schema][:properties]['tipo'][:enum]).to eq(%w[pessoa formulario automatico])
    end
    expect(entrada.keys).to eq(%w[subject body])
    expect(entrada['subject']).to eq('A' * 300)
    expect(entrada['body']).to include('(11) 98765-4321', 'Gerente de Frota')
    expect(entrada['body']).not_to include('99999-0000', 'maria.souza@cliente.com.br')
  end

  # Pega: e-mail que só tem HTML ficar sem leitura.
  it 'e-mail só HTML: o texto do HTML (o content do recebimento) vai ao modelo' do
    html = "Bom dia, quero cotar.\n\nMaria Souza\n(11) 98765-4321"
    mensagem = create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, message_type: :incoming,
                                content_type: 'incoming_email', content: html,
                                content_attributes: { email: { from: ['maria.souza@cliente.com.br'], subject: 'Cotação',
                                                               html_content: { full: "<p>#{html}</p>", reply: html } } })
    responde(telefone: '(11) 98765-4321')

    described_class.new(mensagem).perform

    expect(entrada['body']).to include('Bom dia, quero cotar.', '(11) 98765-4321')
    expect(contact.reload.phone_number).to eq('+5511987654321')
  end

  # Pega: o telefone da assinatura não ser gravado direto (decisão do Rodrigo: grava, sem "Confirmar").
  it 'telefone da assinatura: grava direto no contato sem telefone' do
    contact.update!(name: 'Maria S.')
    responde(nome: 'Maria Souza', telefone: '(11) 98765-4321')

    described_class.new(message).perform

    expect(contact.reload).to have_attributes(name: 'Maria S.', phone_number: '+5511987654321')
  end

  # Pega: o lead do formulário do site, que o Chatwoot cria com o nome igual ao começo do e-mail, ficar sem o nome
  # que o formulário traz.
  it 'nome igual ao começo do e-mail é trocado', :aggregate_failures do
    contact.update!(name: 'maria.souza')
    responde(nome: 'Maria Souza', telefone: '(11) 98765-4321')

    described_class.new(message).perform

    expect(contact.reload).to have_attributes(name: 'Maria Souza', phone_number: '+5511987654321')
  end

  # Pega: um nome de verdade, digitado pelo atendente, ser trocado pelo que a IA leu.
  it 'nome que não é provisório fica' do
    contact.update!(name: 'Maria (diretora)')
    responde(nome: 'Maria Souza', telefone: '(11) 98765-4321')

    described_class.new(message).perform

    expect(contact.reload.name).to eq('Maria (diretora)')
  end

  # Pega: o nome que é o telefone (posto pela plataforma) não ser trocado; e nome sem teto.
  it 'nome que é o telefone é trocado, com no máximo 120 caracteres' do
    contact.update!(name: '+5511911112222', phone_number: '+5511911112222')
    responde(nome: 'M' * 200)

    described_class.new(message).perform

    expect(contact.reload.name).to eq('M' * 120)
  end

  it 'nunca troca o e-mail do contato, mesmo que a assinatura traga outro' do
    responde(nome: 'Maria Souza', email: 'outra@cliente.com.br')

    described_class.new(message).perform

    expect(contact.reload).to have_attributes(name: 'Maria Souza', email: 'maria.souza@cliente.com.br', phone_number: nil)
  end

  it 'contato que já tem nome e telefone: nada muda e a IA nem é chamada', :aggregate_failures do
    contact.update!(name: 'Maria S.', phone_number: '+5511911112222')

    described_class.new(message).perform

    expect(Crm::Ai::CredentialResolver).not_to have_received(:new)
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    expect(contact.reload).to have_attributes(name: 'Maria S.', phone_number: '+5511911112222')
  end

  describe 'formulário de site' do
    # Pega: o endereço fixo do site juntar vários clientes num contato só.
    it 'com o e-mail de outra pessoa: não grava nada, loga só o motivo e pausa', :aggregate_failures do
      responde(tipo: 'formulario', nome: 'Carlos Lima', email: 'carlos@outro.com', telefone: '(21) 97777-6666')
      allow(Rails.logger).to receive(:info)

      described_class.new(message).perform

      expect(contact.reload).to have_attributes(name: 'maria.souza@cliente.com.br', phone_number: nil)
      expect(Rails.logger).to have_received(:info).with(include('motivo=formulario_de_outro_endereco'))
      expect(Redis::Alfred.ttl(chave('pausa', contact.id))).to be_within(60).of(24.hours.to_i)
    end

    # Pega (item 34): formulário em que a IA não achou e-mail nenhum gravar o lead no contato do site.
    it 'sem e-mail lido: não grava nada' do
      responde(tipo: 'formulario', nome: 'Carlos Lima', telefone: '(21) 97777-6666')

      described_class.new(message).perform

      expect(contact.reload).to have_attributes(name: 'maria.souza@cliente.com.br', phone_number: nil)
    end

    # Pega: o formulário que o próprio contato preencheu (com o e-mail dele) ser descartado; e caixa/espaço no e-mail.
    it 'com o e-mail do contato: grava nome e telefone' do
      responde(tipo: 'formulario', nome: 'Maria Souza', email: ' Maria.Souza@Cliente.com.br ', telefone: '(11) 98765-4321')

      described_class.new(message).perform

      expect(contact.reload).to have_attributes(name: 'Maria Souza', phone_number: '+5511987654321')
    end
  end

  describe 'automáticos' do
    before { responde(tipo: 'automatico', nome: 'Loja X', telefone: '(11) 4000-0000') }

    # Pega: newsletter gravar dado; e a 3ª leitura seguida não pausar.
    it 'três seguidos pausam o contato por 30 dias, sem gravar nada', :aggregate_failures do
      allow(Autonomia::Decisores::Aplicador).to receive(:new).and_call_original
      3.times { described_class.new(email!).perform }
      described_class.new(email!).perform

      expect(cliente).to have_received(:create).exactly(3).times
      expect(Autonomia::Decisores::Aplicador).not_to have_received(:new)
      expect(contact.reload).to have_attributes(name: 'maria.souza@cliente.com.br', phone_number: nil)
      expect(Redis::Alfred.ttl(chave('pausa', contact.id))).to be_within(60).of(30.days.to_i)
      expect(Redis::Alfred.exists?(chave('automaticos', contact.id))).to be(false)
    end

    # Pega: o contador não zerar com uma leitura de pessoa no meio (pausa indevida de quem escreve de verdade).
    it 'uma leitura de pessoa no meio zera o contador', :aggregate_failures do
      2.times { described_class.new(email!).perform }
      expect(Redis::Alfred.get(chave('automaticos', contact.id))).to eq('2')
      expect(Redis::Alfred.ttl(chave('automaticos', contact.id))).to be_within(60).of(30.days.to_i)

      responde(tipo: 'pessoa', telefone: '(11) 98765-4321')
      described_class.new(email!).perform
      expect(Redis::Alfred.exists?(chave('automaticos', contact.id))).to be(false)

      contact.update!(phone_number: nil)
      responde(tipo: 'automatico')
      2.times { described_class.new(email!).perform }
      expect(Redis::Alfred.exists?(chave('pausa', contact.id))).to be(false)
    end
  end

  # Pega: o contato sem nada novo pagar a IA a cada e-mail.
  it 'leu e nada foi gravado: 24 horas sem IA para o contato', :aggregate_failures do
    responde(tipo: 'pessoa')

    described_class.new(message).perform
    described_class.new(email!).perform

    expect(cliente).to have_received(:create).once
    expect(Redis::Alfred.ttl(chave('pausa', contact.id))).to be_within(60).of(24.hours.to_i)
  end

  # Pega: dois e-mails ao mesmo tempo pagarem duas leituras; o segundo e-mail se perder; e a trava ficar presa.
  it 'com a trava do contato tomada, não chama a IA e volta para a fila; a própria trava é solta no fim', :aggregate_failures do
    responde(telefone: '(11) 98765-4321')
    Redis::Alfred.set(chave('trava', contact.id), 'outro', nx: true, ex: 60)

    expect { described_class.new(message).perform }
      .to have_enqueued_job(Autonomia::ContatoPeloEmailJob).with(message.id).at(a_value_within(5.seconds).of(1.minute.from_now))
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)

    Redis::Alfred.delete(chave('trava', contact.id))
    described_class.new(message).perform
    expect(cliente).to have_received(:create).once
    expect(Redis::Alfred.exists?(chave('trava', contact.id))).to be(false)
  end

  # Pega: a nova tentativa HTTP pagar a IA de novo fora do teto diário.
  it 'chama a IA sem novas tentativas HTTP' do
    responde(telefone: '(11) 98765-4321')

    described_class.new(message).perform

    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(max_retries: 0))
  end

  # Pega: a nova tentativa do job pagar a IA de novo pelo mesmo e-mail.
  it 'a mesma mensagem não é lida duas vezes' do
    responde(tipo: 'automatico')

    2.times { described_class.new(message).perform }

    expect(cliente).to have_received(:create).once
  end

  # Pega: uma conta gastar sem limite.
  it 'passou do teto diário da conta: não chama a IA e loga', :aggregate_failures do
    responde(telefone: '(11) 98765-4321')
    allow(Rails.logger).to receive(:warn)
    dia = Time.now.utc.to_date.iso8601
    Redis::Alfred.set(chave('teto', "#{account.id}:#{dia}"), Autonomia::ContatoPeloEmail::Freios::TETO_DIARIO, ex: 60)

    described_class.new(message).perform

    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    expect(Rails.logger).to have_received(:warn).with(include('motivo=teto_diario'))
  end

  # Pega: nome, telefone ou e-mail do cliente no log.
  it 'o log leva só chaves e motivos, nunca os valores', :aggregate_failures do
    logs = []
    allow(Rails.logger).to receive(:info) { |texto| logs << texto }
    outro = create(:contact, account: account, phone_number: '+5511987654321')
    responde(nome: 'Maria Souza', email: 'maria.souza@cliente.com.br', telefone: '(11) 98765-4321')

    described_class.new(message).perform

    linha = logs.find { |texto| texto.to_s.include?('[autonomia][contato_pelo_email]') }
    expect(linha).to include('tipo=pessoa', 'gravados=nome', 'recusados=email,telefone')
    expect(logs.map(&:to_s).join("\n")).not_to include('Maria', 'maria.souza', '98765', '5511987654321', "##{outro.id}")
  end

  # Pega (revisão do #1813, item 32): o erro depois da marca "lido" sumir sem chegar ao Sentry, porque a nova tentativa
  # sai como ja_lido; e a nova tentativa pagar a IA de novo.
  it 'erro depois da leitura (deadlock no Aplicador): vai ao rastreador, sobe, e a nova tentativa não paga a IA', :aggregate_failures do
    responde(nome: 'Maria Souza', telefone: '(11) 98765-4321')
    aplicador = instance_double(Autonomia::Decisores::Aplicador)
    allow(aplicador).to receive(:aplicar).and_raise(ActiveRecord::Deadlocked)
    allow(Autonomia::Decisores::Aplicador).to receive(:new).and_return(aplicador)
    rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)

    expect { described_class.new(message).perform }.to raise_error(ActiveRecord::Deadlocked)
    expect(ChatwootExceptionTracker).to have_received(:new).with(kind_of(ActiveRecord::Deadlocked), account: account)
    expect(rastreador).to have_received(:capture_exception).once

    expect { described_class.new(message).perform }.not_to raise_error
    expect(cliente).to have_received(:create).once
    expect(Redis::Alfred.exists?(chave('trava', contact.id))).to be(false)
  end

  # Pega (item 32): o e-mail barrado pelo teto ficar marcado como lido sem ter sido.
  it 'barrado pelo teto diário: o e-mail não fica marcado como lido' do
    dia = Time.now.utc.to_date.iso8601
    Redis::Alfred.set(chave('teto', "#{account.id}:#{dia}"), Autonomia::ContatoPeloEmail::Freios::TETO_DIARIO, ex: 60)

    described_class.new(message).perform

    expect(Redis::Alfred.exists?(chave('lido', message.id))).to be(false)
  end

  # Pega (item 33): a IA ler o mesmo nome provisório que já está no contato, isso contar como "gravado" e cada e-mail
  # pagar uma leitura, sem a pausa de 24 horas.
  it 'leu só o valor que o contato já tinha: conta como nada novo e pausa 24 horas', :aggregate_failures do
    contact.update!(name: 'maria.souza')
    responde(nome: 'maria.souza')

    described_class.new(message).perform
    described_class.new(email!).perform

    expect(cliente).to have_received(:create).once
    expect(contact.reload.name).to eq('maria.souza')
    expect(Redis::Alfred.ttl(chave('pausa', contact.id))).to be_within(60).of(24.hours.to_i)
  end

  # Pega (item 34, decisão): travar todo e-mail cuja assinatura traz outro endereço perderia o telefone de quem escreve
  # do próprio e-mail e assina com o da empresa — caso comum. Só o formulário trava pelo e-mail lido.
  it 'pessoa que assina com outro e-mail (o da empresa): grava nome e telefone, sem trocar o e-mail', :aggregate_failures do
    responde(nome: 'Maria Souza', email: 'comercial@empresa.com.br', telefone: '(11) 98765-4321')

    described_class.new(message).perform

    expect(contact.reload).to have_attributes(name: 'Maria Souza', phone_number: '+5511987654321', email: 'maria.souza@cliente.com.br')
  end

  # Pega (revisão final): o e-mail da assinatura gravado no contato sem e-mail passaria a contar como do cliente na
  # Autoria, e o de outra pessoa (ou plantado no corpo) deixaria de ter o aviso "escrito por outra pessoa".
  it 'contato sem e-mail: o e-mail da assinatura que não é do cliente não é gravado', :aggregate_failures do
    contact.update!(email: nil, name: 'Maria S.')
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'maria.souza@cliente.com.br')
    responde(email: 'comercial@empresa.com.br', telefone: '(11) 98765-4321')

    described_class.new(message).perform

    expect(contact.reload).to have_attributes(phone_number: '+5511987654321', email: nil)
  end

  it 'contato sem e-mail: o e-mail que já é do cliente nesta caixa é gravado' do
    contact.update!(email: nil)
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'maria.souza@cliente.com.br')
    responde(email: 'Maria.Souza@cliente.com.br')

    described_class.new(message).perform

    expect(contact.reload.email).to eq('maria.souza@cliente.com.br')
  end

  # Pega (revisão final): a chave da instalação paga por todas as contas; o teto por conta sozinho não freia o total.
  it 'com a chave da instalação, passou do teto da instalação: não chama a IA', :aggregate_failures do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: :system }))
    responde(telefone: '(11) 98765-4321')
    dia = Time.now.utc.to_date.iso8601
    Redis::Alfred.set(chave('teto_instalacao', dia), Autonomia::ContatoPeloEmail::Freios::TETO_DIARIO_DA_INSTALACAO, ex: 60)

    described_class.new(message).perform

    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    expect(contact.reload.phone_number).to be_blank
  end

  it 'com a chave da própria conta, o teto da instalação não se aplica' do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', source: :hook }))
    responde(telefone: '(11) 98765-4321')
    dia = Time.now.utc.to_date.iso8601
    Redis::Alfred.set(chave('teto_instalacao', dia), Autonomia::ContatoPeloEmail::Freios::TETO_DIARIO_DA_INSTALACAO, ex: 60)

    described_class.new(message).perform

    expect(contact.reload.phone_number).to eq('+5511987654321')
  end

  # Pega (LOW do #1813): o segundo e-mail do lead, que chegou enquanto o primeiro era lido, cair na pausa que o primeiro
  # pôs — e ele pode ser justamente o que traz o telefone. O e-mail que chega depois da pausa continua barrado.
  it 'a pausa vale para o e-mail que chega depois dela, não para o que já estava na fila', :aggregate_failures do
    segundo = email!
    segundo.update!(created_at: 10.seconds.ago)
    responde(tipo: 'pessoa')
    described_class.new(message).perform
    expect(Redis::Alfred.exists?(chave('pausa', contact.id))).to be(true)

    responde(telefone: '(11) 98765-4321')
    described_class.new(segundo).perform
    expect(contact.reload.phone_number).to eq('+5511987654321')
    expect(cliente).to have_received(:create).twice
  end

  # Pega (LOW): o recurso aparecer em "Outros" na Gestão de IA.
  it 'o gasto aparece com o nome do recurso na Gestão de IA' do
    expect(Crm::Reports::AiUsage.resource_for_feature(Autonomia::ContatoPeloEmail::Leitor::FEATURE)).to eq('Contato pelo e-mail')
  end

  context 'without an AI credential' do
    let(:credencial) { nil }

    it 'não faz nada e não dá erro', :aggregate_failures do
      expect { described_class.new(message).perform }.not_to raise_error

      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(contact.reload.name).to eq('maria.souza@cliente.com.br')
    end
  end

  it 'falha da IA ou tipo fora do esquema: não sobe erro nem grava nada', :aggregate_failures do
    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')
    expect { described_class.new(message).perform }.not_to raise_error

    allow(cliente).to receive(:create).and_return(text: { tipo: 'outro', nome: 'X', email: nil, telefone: nil }.to_json)
    expect { described_class.new(email!).perform }.not_to raise_error

    expect(contact.reload.name).to eq('maria.souza@cliente.com.br')
  end

  it 'telefone que já é de outro contato: segue o Aplicador (vai para a biografia)', :aggregate_failures do
    outro = create(:contact, account: account, phone_number: '+5511987654321')
    responde(nome: 'Maria Souza', telefone: '(11) 98765-4321')

    described_class.new(message).perform

    contact.reload
    expect(contact.phone_number).to be_nil
    expect(contact.additional_attributes['description']).to include('+5511987654321', "##{outro.id}")
  end

  it 'e-mail longo vai com o começo e o fim, para a assinatura não se perder', :aggregate_failures do
    responde
    longo = "#{'Texto do pedido. ' * 600}\nMaria Souza\n(11) 98765-4321"

    described_class.new(email!(content: longo)).perform

    expect(entrada['body'].length).to be <= Autonomia::ContatoPeloEmail::Leitor::MAX_TEXTO + 10
    expect(entrada['body']).to include('(11) 98765-4321')
  end
end
