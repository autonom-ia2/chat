require 'rails_helper'

# #1807, ponta a ponta: e-mail de verdade (.eml) entrando pelos dois caminhos de recebimento (ReplyMailbox e IMAP) até o
# que as IAs leem. João pede a cotação com a esposa Ana em cópia; Ana responde com o CPF dela; João responde citando.
RSpec.describe Crm::Email::Autoria do
  include ActionMailbox::TestHelper

  let(:uuid) { '6bdc3f4d-0bec-4515-a284-5d916fd18070' }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_email, account: account, email: 'corretora@example.com') }
  let(:inbox) { channel.inbox }
  let(:joao) { create(:contact, account: account, name: 'João Silva', email: 'joao@empresa.com.br') }
  let(:contact_inbox) { create(:contact_inbox, contact: joao, inbox: inbox, source_id: 'joao@empresa.com.br') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: joao, contact_inbox: contact_inbox).tap { |c| c.update!(uuid: uuid) }
  end
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let!(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Seguro auto', contact: joao,
                              primary_conversation: conversation, inbox: inbox, currency: 'BRL')
  end
  let(:cpf_da_ana) { '987.654.321-00' }

  before do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: admin,
                     source_id: 'corretora-1807@example.com', content: 'João, me manda o CPF do condutor principal.')
    account.enable_features!(described_class::FLAG)
  end

  def pela_reply_mailbox(fixture)
    ReplyMailbox.receive(create_inbound_email_from_fixture(fixture))
    conversation.messages.incoming.reorder(:id).last
  end

  def pelo_imap(fixture)
    Imap::ImapMailbox.new.process(create_inbound_email_from_fixture(fixture).mail, channel)
    conversation.messages.incoming.reorder(:id).last
  end

  def para_a_ia
    Crm::Ai::ContextBuilder.new(card: card.reload).perform[:recent_messages].select { |message| message[:role] == 'customer' }
  end

  # Pega: a resposta da Ana em cópia chegar à IA como fala do João, por qualquer um dos dois caminhos de recebimento.
  %i[pela_reply_mailbox pelo_imap].each do |caminho|
    it "#{caminho}: a Ana em cópia chega com o aviso, e a resposta do João citando a Ana chega sem o CPF dela", :aggregate_failures do
      ana = send(caminho, 'email_autoria_ana_em_copia.eml')
      joao_citando = send(caminho, 'email_autoria_joao_cita.eml')

      expect(ana.sender).to eq(joao) # o recebimento não muda: grava em nome do cliente da conversa
      expect(joao_citando.content).to include(cpf_da_ana) # o texto salvo (e a tela) segue com o histórico inteiro
      da_ana, do_joao = para_a_ia

      expect(da_ana[:content]).to start_with('[E-mail de ana.souza@familia.com.br, endereço que não é do cliente')
      expect(da_ana[:content]).to include(cpf_da_ana)
      expect(da_ana[:email_autoria]).to eq('outra_pessoa')
      expect(da_ana[:content]).not_to include('me manda o CPF do condutor') # sem o histórico citado
      expect(do_joao[:content]).to eq('Ok, pode seguir com a cotacao.')
      expect(do_joao).not_to have_key(:email_autoria)
    end
  end

  # Pega: a lista/grupo que põe o cliente no Reply-To virar "outra pessoa" (o recebimento guarda o Reply-To).
  it 'e-mail da lista com o João no Reply-To é do cliente' do
    pela_reply_mailbox('email_autoria_lista_reply_to.eml')

    expect(para_a_ia.sole).to include(content: 'Pode mandar a proposta para o RH tambem.')
    expect(para_a_ia.sole).not_to have_key(:email_autoria)
  end

  # Pega: o follow-up que retoma a pergunta da Ana deixar de passar na trava de citação; o aviso servir de citação.
  it 'a citação do que a Ana escreveu prova a pendência; o aviso, não', :aggregate_failures do
    pela_reply_mailbox('email_autoria_ana_em_copia.eml')
    mensagens = Crm::Ai::ContextBuilder.new(card: card.reload).perform[:recent_messages]
    aviso = mensagens.last[:content].split('] ').first

    expect(Crm::Ai::QuoteVerifier.new(quote: 'Pode usar o meu CPF como condutora', messages: mensagens).verified?).to be(true)
    expect(Crm::Ai::QuoteVerifier.new(quote: aviso, messages: mensagens).verified?).to be(false)
    expect(Crm::Ai::QuoteVerifier.new(quote: 'endereço que não é do cliente', messages: mensagens).verified?).to be(false)
  end

  # Pega: "parem de me copiar" da Ana bloquear o João (opt-out do contato do card). O modelo lê com o aviso e decide;
  # mesmo no "sim" (pode ser o próprio cliente de outro e-mail), a cadência deste card para, mas o contato não é marcado.
  it 'o pedido para parar escrito pela Ana não bloqueia o João', :aggregate_failures do
    ana = pela_reply_mailbox('email_autoria_ana_em_copia.eml')
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'opt_out_decision' => 'pendente', 'stopped_message_id' => ana.id } } })
    cliente_de_ia = instance_double(Crm::Ai::ResponsesClient)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'chave'))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente_de_ia)
    allow(cliente_de_ia).to receive(:create).and_return(text: { pediu_para_parar: 'sim', motivo: 'pedido_explicito_de_parar' }.to_json)

    Crm::FollowUps::OptOutDecision.new(card: card.reload, message: ana).perform

    expect(cliente_de_ia).to have_received(:create).with(hash_including(
                                                           instructions: end_with(described_class::LEGENDA),
                                                           input: include('[E-mail de ana.souza@familia.com.br')
                                                         ))
    expect(joao.reload).not_to be_opted_out
    expect(card.reload.metadata.dig('ai', 'auto_followup_state')).to include('opt_out_decision' => 'sim', 'opted_out' => true)
  end

  # Pega: o pedido para parar do próprio João deixar de bloquear o contato (o guarda só vale para outro endereço).
  it 'o pedido para parar do João, do endereço dele, segue bloqueando o contato' do
    pela_reply_mailbox('email_autoria_ana_em_copia.eml')
    joao_msg = pela_reply_mailbox('email_autoria_joao_cita.eml')
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'opt_out_decision' => 'pendente', 'stopped_message_id' => joao_msg.id } } })
    allow(Rails.cache).to receive(:fetch).and_return({ decision: 'sim', motivo: 'pedido_explicito_de_parar' })

    Crm::FollowUps::OptOutDecision.new(card: card.reload, message: joao_msg).perform

    expect(joao.reload).to be_opted_out
  end

  # Pega: as IAs não saberem o que é o aviso; a legenda no meio do prompt derrubar o cache de quem não tem a flag.
  it 'a legenda vai no fim dos prompts só com a flag', :aggregate_failures do
    legenda = described_class::LEGENDA
    classificador = Crm::Ai::StageClassifier.new(card: card, client: nil, stages: [], context: {}, eligible_agents: [])

    expect(classificador.send(:instructions)).to eq("#{Crm::Ai::ClassifierPrompt::TEXT}\n\n#{legenda}")
    expect(Crm::Ai::ConversationSummarizer.new(card: card).send(:instructions)).to end_with(legenda)
    expect(Crm::Ai::FollowUpComposer.new(card: card, client: nil, context: {}).send(:instructions)).to end_with(legenda)
    expect(Crm::MetaAds::QuoteMessageSuggester.new(card: card, conversation: conversation, language: 'pt-BR').send(:instructions))
      .to end_with(legenda)
  end

  # Pega: a flag desligada mudar o que a IA lê, o prompt ou o opt-out.
  it 'sem a flag, tudo como antes: texto inteiro, sem aviso, prompts iguais', :aggregate_failures do
    account.disable_features!(described_class::FLAG)
    ana = pela_reply_mailbox('email_autoria_ana_em_copia.eml')

    da_ana = para_a_ia.sole
    expect(da_ana).to eq(da_ana.slice(:role, :content, :created_at))
    expect(da_ana[:content]).to eq(ana.content)
    classificador = Crm::Ai::StageClassifier.new(card: card.reload, client: nil, stages: [], context: {}, eligible_agents: [])
    expect(classificador.send(:instructions)).to equal(Crm::Ai::ClassifierPrompt::TEXT)
    expect(Crm::Ai::ConversationSummarizer.new(card: card).send(:instructions)).not_to include('E-MAIL:')
    expect(Crm::Ai::FollowUpComposer.new(card: card, client: nil, context: {}).send(:instructions))
      .to eq(Crm::Ai::FollowUpComposer.new(card: nil, client: nil, context: {}).send(:instructions))
  end

  describe 'memória' do
    before do
      ligar_memoria!(account)
      [%w[cpf contact_attribute CPF], %w[cnpj_empresa card_attribute CNPJ]].each do |chave, modelo, rotulo|
        CustomAttributeDefinition.create!(account: account, attribute_key: chave, attribute_display_name: rotulo,
                                          attribute_display_type: :text, attribute_model: modelo)
      end
      Crm::Memoria::Catalogo.sincronizar!(account)
    end

    def op(grupo, chave, valor, provas)
      { 'op' => 'adicionar', 'grupo' => grupo, 'chave' => chave, 'item_ref' => nil, 'valor' => valor, 'alvo_fato_id' => nil,
        'base_versao' => nil, 'provas' => provas }
    end

    def aplicar(ops, refs)
      classificacao = { memoria_ops: ops, memoria_refs: refs.transform_values(&:id), memoria_token: nil, model_used: 'gpt-6-luna' }
      Crm::Memoria::Pendente.guardar!(card: card.reload, classificacao: classificacao)
      Crm::Memoria::Pendente.aplicar!(card.reload)
    end

    def fatos(**filtro)
      Crm::MemoriaFato.where(account_id: account.id, **filtro)
    end

    # Pega: o CPF da Ana virar CPF do João, pela mensagem dela ou pela resposta dele que a cita.
    it 'nenhum CPF da Ana no João: nem pela mensagem dela, nem pela resposta dele citando', :aggregate_failures do
      ana = pela_reply_mailbox('email_autoria_ana_em_copia.eml')
      joao_citando = pela_reply_mailbox('email_autoria_joao_cita.eml')

      aplicar([op('contato', 'cpf', '98765432100', ['m1']), op('contato', 'cpf', '98765432100', ['m2'])],
              { 'm1' => ana, 'm2' => joao_citando })

      expect(fatos(chave: 'cpf', situacao: 'vigente')).to be_empty
      expect(Crm::Memoria::Normal.texto_da_mensagem(joao_citando)).to eq('Ok, pode seguir com a cotacao.')
    end

    # Pega: o dado do pedido dito por outra pessoa (o CNPJ que o RH mandou) deixar de entrar.
    it 'o CNPJ que a Ana (ou o RH) manda entra no pedido' do
      ana = pela_reply_mailbox('email_autoria_ana_em_copia.eml')

      aplicar([op('pedido', 'cnpj_empresa', '12.345.678/0001-90', ['m1'])], { 'm1' => ana })

      expect(fatos(chave: 'cnpj_empresa').sole).to have_attributes(card_id: card.id, valor: '12.345.678/0001-90', fonte: 'cliente')
    end
  end
end
