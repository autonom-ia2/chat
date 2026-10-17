require 'rails_helper'

RSpec.describe Crm::Memoria::Origem do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, name: 'Ana') }
  let(:config) { Crm::Memoria.config(account) }

  def origem(message, cfg = config)
    described_class.classificar(message, config: cfg)
  end

  describe '.classificar (autor e entrega)' do
    it 'o cliente é cliente e a mensagem dele não "foi ao cliente"' do
      resultado = origem(mensagem!(conversation, :incoming, content: 'oi'))

      expect(resultado).to have_attributes(autor_tipo: 'cliente', foi_ao_cliente: false, regra: 'entrada')
    end

    it 'a pessoa pelo painel foi ao cliente; a nota privada dela não; a que falhou no envio também não (A1)' do
      publica = mensagem!(conversation, :outgoing, sender: ana, content: 'Olá, sou a Ana')
      nota = mensagem!(conversation, :outgoing, sender: ana, content: 'cotação: R$ 900', private: true)
      falhou = mensagem!(conversation, :outgoing, sender: ana, content: 'fora da janela', status: :failed)

      expect(origem(publica)).to have_attributes(autor_tipo: 'pessoa_painel', foi_ao_cliente: true, autor_ref_type: 'User', autor_ref_id: ana.id)
      expect(origem(nota)).to have_attributes(autor_tipo: 'pessoa_painel', foi_ao_cliente: false, regra: 'nota')
      expect(origem(falhou)).to have_attributes(autor_tipo: 'pessoa_painel', foi_ao_cliente: false)
    end

    it 'envio automático em nome da Ana não é pessoa: follow-up é follow_up_nosso; aviso de agendamento e automação são sistema' do
      follow_up = mensagem!(conversation, :outgoing, sender: ana, content: 'Ainda tem interesse?', content_attributes: { crm_follow_up_id: 9 })
      aviso = mensagem!(conversation, :outgoing, sender: ana, content: 'Lembrete da reunião', content_attributes: { crm_booking_notice: 'x' })
      automacao = mensagem!(conversation, :outgoing, sender: ana, content: 'Recebemos', content_attributes: { automation_rule_id: 3 })

      expect(origem(follow_up).autor_tipo).to eq('follow_up_nosso')
      expect(origem(aviso)).to have_attributes(autor_tipo: 'sistema', regra: 'envio_automatico')
      expect(origem(automacao).autor_tipo).to eq('sistema')
    end

    it 'o robô de fora com login de pessoa, declarado pelo admin, é robo_externo (caso "Ana Maciel")' do
      robo = create(:user, account: account, name: 'Ana Maciel')
      cfg = Crm::MemoriaConfig.create!(account: account, usuarios_robo_ids: [robo.id])

      expect(origem(mensagem!(conversation, :outgoing, sender: robo, content: 'Digite 1'), cfg))
        .to have_attributes(autor_tipo: 'robo_externo', regra: 'robo_declarado', foi_ao_cliente: true)
    end

    it 'o espelho de um agente nosso é ia_nossa; outro AgentBot (n8n) é robo_externo' do
      n8n = create(:agent_bot, account: account, name: 'n8n')

      expect(origem(mensagem!(conversation, :outgoing, sender: porta, content: 'Oi, sou a Clara')).autor_tipo).to eq('ia_nossa')
      expect(origem(mensagem!(conversation, :outgoing, sender: n8n, content: 'menu')).autor_tipo).to eq('robo_externo')
    end

    it 'o eco do celular é pessoa_celular; a saída sem remetente e sem eco é sistema; template é sistema' do
      eco = create(:message, :bot_message, conversation: conversation, account: account, inbox: inbox,
                                           content: 'Te ligo já', content_attributes: { external_echo: true })
      saida = create(:message, :bot_message, conversation: conversation, account: account, inbox: inbox, content: 'Fora do horário')
      template = mensagem!(conversation, :template, content: 'Bem-vindo')

      expect(origem(eco)).to have_attributes(autor_tipo: 'pessoa_celular', foi_ao_cliente: true)
      expect(origem(saida)).to have_attributes(autor_tipo: 'sistema', regra: 'saida_sem_remetente')
      expect(origem(template)).to have_attributes(autor_tipo: 'sistema', regra: 'template', foi_ao_cliente: true)
    end
  end

  it 'a mensagem encaminhada (#1702b) é da pessoa que encaminhou, marcada como encaminhada' do
    encaminhada = mensagem!(conversation, :outgoing, sender: ana, content: 'Meu CPF é 999', content_attributes: { forwarded: true })

    expect(origem(encaminhada)).to have_attributes(autor_tipo: 'pessoa_painel', encaminhada: true)
    linha = described_class.gravar!(encaminhada)
    expect(linha).to be_descartavel
    expect(linha.resposta_da_pessoa?).to be(false)
    expect(described_class.gravar!(mensagem!(conversation, :outgoing, sender: ana, content: 'nota', private: true)).resposta_da_pessoa?)
      .to be(false)
    expect(described_class.gravar!(mensagem!(conversation, :outgoing, sender: ana, content: 'Oi!')).resposta_da_pessoa?).to be(true)
  end

  describe '.classificar (conteúdo)' do
    it 'D1: "This message is unavailable" por igualdade exata é indisponível e sem conteúdo; texto parecido não' do
      expect(described_class::TEXTO_INDISPONIVEL).to eq('This message is unavailable')
      expect(origem(mensagem!(conversation, :incoming, content: 'This message is unavailable')))
        .to have_attributes(indisponivel: true, sem_conteudo: true, duplicata_de_message_id: nil)
      expect(origem(mensagem!(conversation, :incoming, content: ' This message is unavailable')).indisponivel).to be(false)
      expect(origem(mensagem!(conversation, :incoming, content: 'Abra no celular', content_attributes: { is_unsupported: true })))
        .to have_attributes(indisponivel: true, sem_conteudo: true)
      expect(origem(mensagem!(conversation, :incoming, content: 'This message is unavailable, sorry')))
        .to have_attributes(indisponivel: false, sem_conteudo: false)
    end

    it 'anexo sem arquivo, sem transcrição e sem legenda é sem conteúdo; com transcrição tem conteúdo' do
      vazio = mensagem!(conversation, :incoming, content: nil)
      vazio.attachments.create!(account: account, file_type: :audio)
      transcrito = mensagem!(conversation, :incoming, content: nil)
      transcrito.attachments.create!(account: account, file_type: :audio, meta: { 'transcribed_text' => 'meu CPF é 123' })

      expect(origem(vazio.reload).sem_conteudo).to be(true)
      expect(origem(transcrito.reload).sem_conteudo).to be(false)
      localizacao = mensagem!(conversation, :incoming, content: nil)
      localizacao.attachments.create!(account: account, file_type: :location, coordinates_lat: -23.5, coordinates_long: -46.6)
      externo = mensagem!(conversation, :incoming, content: nil)
      externo.attachments.create!(account: account, file_type: :image, external_url: 'https://exemplo.com/foto.jpg')
      expect([origem(localizacao.reload).sem_conteudo, origem(externo.reload).sem_conteudo]).to eq([false, false])
    end

    it 'o hash ignora espaços nas pontas e maiúsculas' do
      a = mensagem!(conversation, :incoming, content: ' Oi ')
      b = mensagem!(conversation, :outgoing, sender: ana, content: 'oi')

      expect(origem(a).conteudo_hash).to eq(origem(b).conteudo_hash)
    end
  end

  describe '.classificar (duplicata)' do
    # Sem os templates que a caixa de API manda ao cliente (eles seriam o "outro lado" no meio).
    before do
      hook = instance_double(MessageTemplates::HookExecutionService, perform: nil)
      allow(MessageTemplates::HookExecutionService).to receive(:new).and_return(hook)
    end

    it 'o mesmo source_id de uma anterior é duplicata dela' do
      primeira = mensagem!(conversation, :incoming, content: 'oi', source_id: 'wamid.1')
      segunda = mensagem!(conversation, :incoming, content: 'oi de novo', source_id: 'wamid.1')

      expect(origem(segunda).duplicata_de_message_id).to eq(primeira.id)
    end

    it 'mesmo lado e mesmo texto em até 120 s, sem o outro lado no meio, é duplicata' do
      primeira = mensagem!(conversation, :incoming, content: 'Meu CPF é 123', created_at: 50.seconds.ago)
      segunda = mensagem!(conversation, :incoming, content: 'meu cpf é 123 ', created_at: 10.seconds.ago)

      expect(origem(segunda).duplicata_de_message_id).to eq(primeira.id)
    end

    it 'o 2º "sim" depois de uma pergunta nossa é resposta, não duplicata (M20); nota privada no meio não conta como outro lado' do
      mensagem!(conversation, :incoming, content: 'sim', created_at: 60.seconds.ago)
      mensagem!(conversation, :outgoing, sender: ana, content: 'Confirma a placa?', created_at: 40.seconds.ago)
      resposta = mensagem!(conversation, :incoming, content: 'sim', created_at: 20.seconds.ago)
      mensagem!(conversation, :outgoing, sender: ana, content: 'nota', private: true, created_at: 15.seconds.ago)
      repetida = mensagem!(conversation, :incoming, content: 'sim', created_at: 10.seconds.ago)

      expect(origem(resposta).duplicata_de_message_id).to be_nil
      expect(origem(repetida).duplicata_de_message_id).to eq(resposta.id)
    end

    it 'fora da janela de 120 s não é duplicata' do
      mensagem!(conversation, :incoming, content: 'oi', created_at: 5.minutes.ago)

      expect(origem(mensagem!(conversation, :incoming, content: 'oi')).duplicata_de_message_id).to be_nil
    end
  end

  describe '.gravar!' do
    it 'grava uma linha por mensagem, com a conta, a conversa e o contato da conversa, e regrava ao mudar' do
      message = mensagem!(conversation, :outgoing, sender: ana, content: 'olá')
      linha = described_class.gravar!(message)

      expect(linha).to have_attributes(account_id: account.id, conversation_id: conversation.id, contact_id: contact.id,
                                       autor_tipo: 'pessoa_painel', foi_ao_cliente: true, classificador_versao: 1)
      message.update!(status: :failed)
      expect(described_class.gravar!(message).foi_ao_cliente).to be(false)
      expect(Crm::MensagemOrigem.where(message_id: message.id).count).to eq(1)
    end

    it 'não regrava a linha corrigida por uma pessoa (a correção vence a do código)' do
      message = mensagem!(conversation, :outgoing, sender: ana, content: 'olá')
      described_class.gravar!(message).update!(autor_tipo: 'robo_externo', corrigido_por_user_id: admin.id)

      expect(described_class.gravar!(message).autor_tipo).to eq('robo_externo')
    end

    it '.para lê a linha; sem linha, calcula e grava na hora' do
      message = mensagem!(conversation, :incoming, content: 'oi')

      expect { described_class.para(message) }.to change(Crm::MensagemOrigem, :count).by(1)
      expect { described_class.para(message) }.not_to change(Crm::MensagemOrigem, :count)
    end
  end

  describe 'isolamento e apagamento' do
    it 'apagar o contato apaga a autoria das mensagens dele no banco (FK em cascata), mesmo num delete cru' do
      described_class.gravar!(mensagem!(conversation, :incoming, content: 'oi'))

      expect { Contact.where(id: contact.id).delete_all }.to change(Crm::MensagemOrigem, :count).by(-1)
    end

    it 'o robô declarado precisa ser da conta; a caixa excluída também' do
      de_fora = create(:user, account: create(:account))
      cfg = Crm::MemoriaConfig.new(account: account, usuarios_robo_ids: [de_fora.id], caixas_excluidas: [create(:inbox).id])

      expect(cfg).not_to be_valid
      expect(cfg.errors.attribute_names).to contain_exactly(:usuarios_robo_ids, :caixas_excluidas)
    end
  end
end
