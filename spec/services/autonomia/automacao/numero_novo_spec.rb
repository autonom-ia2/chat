require 'rails_helper'

# G43 (#2700): no WhatsApp e no SMS a conversa fica presa ao número com que nasceu (`ContactInbox.source_id`). Quando o
# número da conversa morreu (a última mensagem da empresa nela falhou, e o cliente não escreveu depois) e o telefone do
# contato é outro, o passo "mensagem" manda no número novo: reaproveita ou abre a conversa dele na mesma caixa, pela
# porta da frente (a mesma da conversa nova, #2680), e os passos seguintes usam essa conversa. Telefone diferente
# sozinho não troca: o contato com dois números continua recebendo no número de onde escreve.
RSpec.describe Autonomia::Automacao::NumeroNovo, :automacao_motor do
  include ActiveJob::TestHelper

  # O SMS não tem janela: aqui o assunto é o número. A janela do WhatsApp oficial no número novo (conversa nova, só com
  # modelo) fica no fechamento do ex. 19.
  let(:account) { create(:account) }
  let(:caixa) { create(:channel_sms, account: account).inbox }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Bruno', phone_number: '+5511937016094') }
  let(:antigo) { create(:contact_inbox, inbox: caixa, contact: contato, source_id: '+5511937016094') }
  let(:conversa) { create(:conversation, inbox: caixa, contact: contato, contact_inbox: antigo, account: account) }
  let(:oi) { mensagem_passo('oi', 'Oi ', { '$valor' => 'contato.nome' }, ', a sua apólice venceu.') }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :incoming, content: 'oi',
                     source_id: 'in-1', created_at: 1.hour.ago)
    falhou_em(conversa)
  end

  # A última mensagem da empresa na conversa, recusada pelo canal: o número morreu.
  def falhou_em(alvo, quando = 30.minutes.ago)
    create(:message, conversation: alvo, account: account, inbox: alvo.inbox, message_type: :outgoing, content: 'Sua apólice',
                     status: :failed, created_at: quando)
  end

  def whatsapp_com(numero)
    canal = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    no_whatsapp = create(:contact_inbox, inbox: canal.inbox, contact: contato, source_id: numero)
    create(:conversation, account: account, inbox: canal.inbox, contact: contato, contact_inbox: no_whatsapp).tap { |nova| falhou_em(nova) }
  end

  after { Current.reset }

  def rodar(passos, alvo = conversa, por: admin)
    automacao = automacao_ligada(account, por, passos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao, alvo) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def dados_do(execucao, passo) = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: passo).dados

  def no_numero_novo = Conversation.joins(:contact_inbox).find_by(contact_inboxes: { source_id: '+5511988880000' })

  describe '.trocou?' do
    it 'o mesmo número não trocou; no WhatsApp, sem o "+" e com o nono dígito do celular a menos, também não', :aggregate_failures do
      expect(described_class.trocou?(conversa)).to be(false)
      expect(described_class.trocou?(whatsapp_com('5511937016094'))).to be(false)

      contato.update!(phone_number: '+5511987654321')
      expect(described_class.trocou?(whatsapp_com('551187654321'))).to be(false)
    end

    # Sem o 9, o 3 do começo é de telefone fixo: é outro número, não o celular antigo.
    it 'o fixo com os mesmos algarismos do celular sem o 9 é outro número' do
      expect(described_class.trocou?(whatsapp_com('551137016094'))).to be(true)
    end

    it 'o telefone do contato diferente do número da conversa trocou', :aggregate_failures do
      contato.update!(phone_number: '+5511988880000')

      expect(described_class.trocou?(conversa.reload)).to be(true)
      expect(described_class.trocou?(whatsapp_com('5511937016094'))).to be(true)
    end

    it 'telefone diferente com o número da conversa vivo não trocou: a última mensagem chegou, ou o cliente escreveu depois',
       :aggregate_failures do
      contato.update!(phone_number: '+5511988880000')
      conversa.messages.outgoing.sole.update!(status: :delivered)
      expect(described_class.trocou?(conversa.reload)).to be(false)

      conversa.messages.outgoing.sole.update!(status: :failed)
      create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :incoming, content: 'oi de novo')
      expect(described_class.trocou?(conversa.reload)).to be(false)
    end

    it 'contato sem telefone, ou caixa que não acha o contato pelo telefone, não trocou', :aggregate_failures do
      contato.update!(phone_number: nil)
      expect(described_class.trocou?(conversa.reload)).to be(false)

      contato.update!(phone_number: '+5511988880000')
      api = create_crm_whatsapp_api_inbox(account: account)
      expect(described_class.trocou?(create(:conversation, account: account, inbox: api, contact: contato))).to be(false)
    end
  end

  describe 'no passo "mensagem"' do
    before { contato.update!(phone_number: '+5511988880000') }

    it 'abre a conversa do número novo na mesma caixa, manda nela, e o registro diz "número novo"', :aggregate_failures do
      execucao = rodar([oi])
      nova = no_numero_novo

      expect(registros(execucao)).to eq([['oi', 'ok', nil]])
      expect(nova).to have_attributes(inbox_id: caixa.id, contact_id: contato.id)
      expect(nova.messages.outgoing.sole.content).to eq('Oi Bruno, a sua apólice venceu.')
      expect(conversa.messages.outgoing.pluck(:status)).to eq(['failed'])
      expect(dados_do(execucao, 'oi')).to include('numero_novo' => true, 'conversa_aberta' => nova.display_id)
    end

    it 'reaproveita a conversa aberta do número novo, sem abrir outra', :aggregate_failures do
      novo = create(:contact_inbox, inbox: caixa, contact: contato, source_id: '+5511988880000')
      existente = create(:conversation, inbox: caixa, contact: contato, contact_inbox: novo, account: account)

      rodar([oi])

      expect(Conversation.where(contact: contato).count).to eq(2)
      expect(existente.messages.outgoing.sole.content).to eq('Oi Bruno, a sua apólice venceu.')
    end

    it 'os passos seguintes (o aviso, a espera) usam a conversa do número novo', :aggregate_failures do
      espera = { 'id' => 'espera', 'tipo' => 'esperar_ate', 'prazo' => { 'valor' => 2, 'unidade' => 'horas' },
                 'condicao' => { 'campo' => { '$valor' => 'conversa.cliente_respondeu' }, 'op' => 'igual', 'valor' => true } }
      execucao = rodar([oi, espera, avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Respondeu no número novo')])
      nova = no_numero_novo
      expect(execucao.reload.estado).to eq('esperando')

      travel(10.minutes) do
        mensagem = create(:message, account: account, conversation: nova, inbox: caixa, message_type: :incoming, content: 'sou eu')
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
          Autonomia::AutomacaoListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: mensagem))
        end
      end

      expect(execucao.reload.estado).to eq('concluida')
      expect(nova.messages.where(private: true).last.content).to include('Respondeu no número novo')
      expect(conversa.messages.where(private: true)).to be_empty
    end

    it 'no card, a conversa do número novo vira a principal, e o registro diz isso', :aggregate_failures do
      with_modified_env(CRM_KANBAN_ENABLED: 'true') do
        funil, etapa = create_crm_pipeline(account: account, user: admin)
        card = account.crm_cards.create!(pipeline: funil, stage: etapa, contact: contato, title: 'Renovação', primary_conversation: conversa)

        execucao = rodar([oi], card)

        expect(card.reload.conversation_id).to eq(no_numero_novo.id)
        expect(dados_do(execucao, 'oi')).to include('numero_novo' => true, 'conversa_principal_do_card' => card.id)
      end
    end

    it 'a mensagem que não sai no número novo desfaz a conversa: nada fica vazio na caixa', :aggregate_failures do
      contato.update!(opted_out_at: Time.current)

      execucao = rodar([oi])

      expect(registros(execucao)).to eq([%w[oi pulado contato_nao_recebe]])
      expect(ContactInbox.where(contact: contato).count).to eq(1)
      expect(Conversation.where(contact: contato).count).to eq(1)
    end

    it 'quem ligou não pode começar conversa na caixa: pausa, sem abrir a conversa do número novo', :aggregate_failures do
      allow(Autonomia::Automacao::Acesso).to receive(:comeca_conversa?).and_return(false)

      execucao = rodar([oi])

      expect(registros(execucao)).to eq([%w[oi falhou quem_ligou_sem_acesso]])
      expect(no_numero_novo).to be_nil
    end

    it 'o número novo já é de outro contato na caixa: pula, e o outro contato fica como estava', :aggregate_failures do
      outro = create(:contact, account: account, name: 'Carla')
      dela = create(:contact_inbox, inbox: caixa, contact: outro, source_id: '+5511988880000')

      execucao = rodar([oi])

      expect(registros(execucao)).to eq([%w[oi pulado numero_de_outro_contato]])
      expect(dela.reload).to have_attributes(contact_id: outro.id, source_id: '+5511988880000')
      expect(Conversation.where(contact: contato).count).to eq(1)
    end

    it 'o ensaio diz o mesmo: o número novo de outro contato pularia, e o caminho segue' do
      create(:contact_inbox, inbox: caixa, contact: create(:contact, account: account, name: 'Carla'), source_id: '+5511988880000')
      receita = { 'gatilho' => { 'tipo' => 'conversa.aberta' }, 'passos' => [oi, esperar_passo('e1')] }

      ensaio = Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: admin, conversa_id: conversa.display_id).resultado

      expect(ensaio[:conversas].first[:passos].pluck(:faria)).to eq(%w[numero_de_outro_contato esperar])
    end

    describe 'no WhatsApp oficial' do
      let(:whatsapp) { whatsapp_com('5511937016094') }

      before do
        create(:message, conversation: whatsapp, account: account, inbox: whatsapp.inbox, message_type: :incoming, content: 'oi',
                         source_id: 'in-2', created_at: 1.hour.ago)
      end

      it 'a conversa do número novo nasce com a janela fechada: sem modelo, para, e nada fica aberto', :aggregate_failures do
        execucao = rodar([oi], whatsapp)

        expect(registros(execucao)).to eq([%w[oi falhou fora_da_janela]])
        expect(ContactInbox.where(contact: contato, inbox: whatsapp.inbox).count).to eq(1)
        expect(whatsapp.messages.outgoing.pluck(:status)).to eq(['failed'])
      end

      it 'o "escrever" confere a janela do número novo antes de chamar a IA', :aggregate_failures do
        account.enable_features!('automacao_ia')
        escrever = { 'id' => 'recado', 'tipo' => 'escrever', 'destino' => 'mensagem', 'instrucao' => 'Retome o contato.' }
        allow(Autonomia::Automacao::PassoDeEscrever).to receive(:consulta).and_call_original

        execucao = rodar([escrever], whatsapp)

        expect(registros(execucao)).to eq([%w[recado falhou fora_da_janela]])
        expect(Autonomia::Automacao::PassoDeEscrever).not_to have_received(:consulta)
      end

      # A janela oficial do número antigo está aberta (o cliente escreveu há 1 hora), então ali o WhatsApp API não responde;
      # no número novo a janela oficial está fechada e o WhatsApp API da caixa híbrida responde. As duas perguntas do
      # "escrever" são do número novo, onde a mensagem vai sair.
      context 'with a caixa híbrida pronta (WAHA)' do
        around { |exemplo| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { exemplo.run } }

        before do
          canal = whatsapp.inbox.channel
          WhatsappHybrid::Connection.create!(
            account: account, inbox: whatsapp.inbox, session_name: "hybrid-#{SecureRandom.hex(3)}", status: 'connected',
            connected_phone: canal.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
          )
          WhatsappHybrid::Config.forget_inbox(whatsapp.inbox.id)
        end

        it 'o "escrever" chama a IA e o texto sai na conversa do número novo', :aggregate_failures do
          account.enable_features!('automacao_ia')
          escrever = { 'id' => 'recado', 'tipo' => 'escrever', 'destino' => 'mensagem', 'instrucao' => 'Retome o contato.' }
          ia = instance_double(Autonomia::Automacao::PassoDeIa, perguntar: [{ 'texto' => 'Oi Bruno, retomando o contato.' }, {}])
          allow(Autonomia::Automacao::PassoDeIa).to receive(:new).and_return(ia)

          execucao = rodar([escrever], whatsapp)
          nova = Conversation.joins(:contact_inbox).find_by!(contact_inboxes: { source_id: '5511988880000' })

          expect(registros(execucao)).to eq([['recado', 'ok', nil]])
          expect(nova.whatsapp_api_reply?).to be(true)
          expect(nova).to have_attributes(inbox_id: whatsapp.inbox.id, contact_id: contato.id)
          expect(nova.messages.outgoing.sole.content).to eq('Oi Bruno, retomando o contato.')
        end
      end
    end

    # O contato com dois números (o merge guardou o outro no telefone) escreve do número da conversa: a resposta volta a ele.
    it 'o contato que escreve do número da conversa recebe nela, mesmo com outro telefone no cadastro', :aggregate_failures do
      create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :incoming, content: 'oi de novo')

      execucao = rodar([oi])

      expect(conversa.messages.outgoing.last.content).to eq('Oi Bruno, a sua apólice venceu.')
      expect(no_numero_novo).to be_nil
      expect(dados_do(execucao, 'oi').keys).not_to include('numero_novo')
    end

    it 'com o mesmo número, manda na conversa de sempre, sem a marca do número novo', :aggregate_failures do
      contato.update!(phone_number: '+5511937016094')

      execucao = rodar([oi])

      expect(conversa.messages.outgoing.last.content).to eq('Oi Bruno, a sua apólice venceu.')
      expect(dados_do(execucao, 'oi').keys).not_to include('numero_novo')
    end
  end
end
