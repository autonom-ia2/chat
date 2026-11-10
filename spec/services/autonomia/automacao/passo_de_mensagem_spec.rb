require 'rails_helper'

# O passo "mensagem" nos canais de verdade (#2414 F4): a janela de cada canal, lida como envio automático, e a mensagem
# sem remetente passando pelo envio do canal (SendReplyJob) sem erro.
RSpec.describe Autonomia::Automacao::PassoDeMensagem, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:passo) { mensagem_passo('p1', 'Seu pedido saiu.') }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  after { Current.reset }

  # A automação é salva antes (a Receita confere o modelo ao salvar); o spec pode mudar a caixa depois, como na vida real.
  def rodar(conversa, automacao = automacao_ligada(account, admin, [passo]))
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao, conversa) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def recebida(conversa, quando)
    create(:message, conversation: conversa, account: conversa.account, inbox: conversa.inbox, message_type: :incoming,
                     content: 'oi', source_id: "in-#{SecureRandom.hex(3)}", created_at: quando)
  end

  def mandada(conversa) = conversa.messages.outgoing.where(private: false).last

  describe 'Instagram' do
    let(:canal) { create(:channel_instagram, account: account, instagram_id: 'instagram-123') }
    let(:contato) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contato, inbox: canal.inbox, source_id: 'ig-contato') }
    let(:conversa) { create(:conversation, account: account, contact: contato, inbox: canal.inbox, contact_inbox: contact_inbox) }
    let(:resposta) { instance_double(HTTParty::Response, success?: true, parsed_response: { 'message_id' => 'ig-mid-1' }) }

    before do
      InstallationConfig.where(name: 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT').first_or_create(value: true)
      allow(HTTParty).to receive(:post).and_return(resposta)
    end

    it 'fora das 24 h para com fora_da_janela, mesmo com a tag de agente humano (é envio automático)', :aggregate_failures do
      recebida(conversa, 30.hours.ago)
      execucao = rodar(conversa)

      expect(mandada(conversa)).to be_nil
      expect(registros(execucao)).to eq([%w[p1 falhou fora_da_janela]])
      expect(execucao.reload.estado).to eq('parada')
    end

    it 'dentro da janela, a mensagem sem remetente sai pelo canal sem erro', :aggregate_failures do
      recebida(conversa, 1.hour.ago)
      rodar(conversa)

      mensagem = mandada(conversa)
      expect(mensagem.sender).to be_nil
      SendReplyJob.perform_now(mensagem.id)

      expect(HTTParty).to have_received(:post).at_least(:once)
      expect(mensagem.reload.status).not_to eq('failed')
    end
  end

  # Decisão 5 (#2414): o contato bloqueado não recebe nada da automação, na conversa que já existe. Canal API sem limite
  # de horas: a janela não interfere.
  describe 'contato bloqueado' do
    let(:canal) { create(:channel_api, account: account) }
    let(:contato) { create(:contact, account: account) }
    let(:conversa) { create(:conversation, account: account, contact: contato, inbox: canal.inbox) }

    it 'contato normal recebe a mensagem', :aggregate_failures do
      execucao = rodar(conversa)

      expect(registros(execucao)).to eq([['p1', 'ok', nil]])
      expect(mandada(conversa).content).to eq('Seu pedido saiu.')
    end

    it 'contato bloqueado não recebe: pula com contato_bloqueado e a automação segue', :aggregate_failures do
      contato.update!(blocked: true)
      execucao = rodar(conversa)

      expect(mandada(conversa)).to be_nil
      expect(registros(execucao)).to eq([%w[p1 pulado contato_bloqueado]])
      expect(execucao.reload.estado).to eq('concluida')
    end
  end

  # O canal API só tem janela quando o dono da caixa põe um limite de horas (agent_reply_time_window); sem ele, responde
  # a qualquer hora. Ele não tem modelo da Meta: com o limite vencido, o modelo do passo não se aplica, e o histórico diz
  # que o limite é da caixa, para não parecer defeito (#2468).
  describe 'Canal API' do
    let(:limite) { { 'agent_reply_time_window' => '24' } }
    let(:canal) { create(:channel_api, account: account, additional_attributes: limite) }
    let(:contato) { create(:contact, account: account, name: 'Ana') }
    let(:conversa) { create(:conversation, account: account, contact: contato, inbox: canal.inbox) }
    let(:passo) do
      mensagem_passo('p1', 'Seu pedido saiu.').merge('modelo' => { 'nome' => 'pedido_saiu', 'idioma' => 'pt_BR', 'variaveis' => [] })
    end

    # O modelo existe numa caixa oficial da conta (a Receita aceita); a conversa é do canal API.
    before do
      oficial = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                          validate_provider_config: false)
      oficial.update!(message_templates: [{ 'name' => 'pedido_saiu', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
                                            'components' => [{ 'type' => 'BODY', 'text' => 'Seu pedido saiu.' }] }])
    end

    it 'com o limite do dono vencido, mesmo com modelo no passo: para com limite_da_caixa', :aggregate_failures do
      recebida(conversa, 30.hours.ago)
      execucao = rodar(conversa)

      expect(mandada(conversa)).to be_nil
      expect(registros(execucao)).to eq([%w[p1 falhou limite_da_caixa]])
      expect(execucao.reload.estado).to eq('parada')
    end

    context 'with a caixa sem limite de horas' do
      let(:limite) { {} }

      it 'depois de 24 h, o texto livre sai normalmente', :aggregate_failures do
        recebida(conversa, 30.hours.ago)
        execucao = rodar(conversa)

        expect(registros(execucao)).to eq([['p1', 'ok', nil]])
        expect(mandada(conversa).content).to eq('Seu pedido saiu.')
      end
    end
  end

  describe 'WhatsApp Cloud' do
    let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:account) { canal.account }
    let(:contato) { create(:contact, account: account, phone_number: '+5511937016094') }
    let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: contato, source_id: '5511937016094') }
    let(:conversa) { create(:conversation, inbox: canal.inbox, contact: contato, contact_inbox: contact_inbox, account: account) }

    # O receptor da Graph grava cada pedido, para o spec ler o modelo que saiu (#2468).
    let(:pedidos) { [] }
    let(:modelo_aprovado) do
      { 'name' => 'pedido_saiu', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu pedido {{2}} saiu.' }] }
    end
    let(:modelo) do
      { 'nome' => 'pedido_saiu', 'idioma' => 'pt_BR', 'variaveis' => [[{ '$valor' => 'contato.nome' }], ['nº 42']] }
    end
    let(:passo) { mensagem_passo('p1', 'Seu pedido saiu.').merge('modelo' => modelo) }

    before do
      stub_request(:post, ->(uri) { uri.host == 'graph.facebook.com' }).to_return do |pedido|
        pedidos << JSON.parse(pedido.body)
        { status: 200, body: { messages: [{ id: 'wamid.AUTOMACAO' }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
      contato.update!(name: 'Ana')
      com_modelos(modelo_aprovado)
    end

    def com_modelos(*itens) = canal.update!(message_templates: itens)

    def saiu_pela_graph(conversa)
      SendReplyJob.perform_now(mandada(conversa).id)
      pedidos.last
    end

    it 'dentro da janela, a mensagem sem remetente sai pela Cloud sem erro', :aggregate_failures do
      recebida(conversa, 1.hour.ago)
      rodar(conversa)

      mensagem = mandada(conversa)
      SendReplyJob.perform_now(mensagem.id)

      expect(mensagem.reload.source_id).to eq('wamid.AUTOMACAO')
      expect(mensagem.status).not_to eq('failed')
    end

    it 'fora da janela, sem modelo no passo: para (#2573)', :aggregate_failures do
      passo.delete('modelo')
      recebida(conversa, 30.hours.ago)
      execucao = rodar(conversa)

      expect(mandada(conversa)).to be_nil
      expect(registros(execucao)).to eq([%w[p1 falhou fora_da_janela]])
      expect(execucao.reload.estado).to eq('parada')
    end

    describe 'o modelo aprovado fora da janela (#2468)' do
      it 'janela fechada: sai o modelo, com os valores da conversa em cada variável, até a Graph', :aggregate_failures do
        recebida(conversa, 30.hours.ago)
        execucao = rodar(conversa)

        expect(registros(execucao)).to eq([['p1', 'ok', nil]])
        expect(mandada(conversa).content).to eq('Oi Ana, seu pedido nº 42 saiu.')
        corpo = saiu_pela_graph(conversa)
        expect(corpo['type']).to eq('template')
        expect(corpo.dig('template', 'name')).to eq('pedido_saiu')
        expect(corpo.dig('template', 'language', 'code')).to eq('pt_BR')
        parametros = corpo.dig('template', 'components').find { |parte| parte['type'] == 'body' }['parameters']
        expect(parametros.pluck('text')).to eq(['Ana', 'nº 42'])
        expect(mandada(conversa).reload.status).not_to eq('failed')
      end

      # #2597: as variáveis do modelo leem com as permissões de quem ligou, como o texto.
      it 'janela fechada: as variáveis do modelo leem com as permissões de quem ligou' do
        automacao = automacao_ligada(account, admin, [passo])
        recebida(conversa, 30.hours.ago)
        lidos = []
        allow(Autonomia::Automacao::ModeloWhatsapp).to receive(:new).and_wrap_original do |original, modelo, alvo, valores|
          lidos << valores
          original.call(modelo, alvo, valores)
        end

        rodar(conversa, automacao)

        expect(lidos.map { |valores| valores.send(:account_user)&.user }).to eq([admin])
      end

      it 'janela fechada com texto só de espaços: o modelo sai mesmo assim (ele não usa o texto)', :aggregate_failures do
        passo['texto'] = ['   ']
        recebida(conversa, 30.hours.ago)
        execucao = rodar(conversa)

        expect(registros(execucao)).to eq([['p1', 'ok', nil]])
        expect(saiu_pela_graph(conversa)['type']).to eq('template')
      end

      # A Meta recusa variável com quebra de linha, tab ou espaços seguidos (132018), e a recusa só chega depois do "ok".
      {
        'quebra de linha' => "Ana\nSouza",
        'tab' => "Ana\tSouza",
        'cinco espaços seguidos' => 'Ana     Souza',
        'tudo junto, nas pontas também' => " Ana\r\n\t  Souza  "
      }.each do |caso, nome|
        it "#{caso} na variável vira um espaço, no envio e no painel", :aggregate_failures do
          contato.update!(name: nome)
          recebida(conversa, 30.hours.ago)
          rodar(conversa)

          expect(mandada(conversa).content).to eq('Oi Ana Souza, seu pedido nº 42 saiu.')
          parametros = saiu_pela_graph(conversa).dig('template', 'components').find { |parte| parte['type'] == 'body' }['parameters']
          expect(parametros.pluck('text')).to eq(['Ana Souza', 'nº 42'])
        end
      end

      it 'variável que só tem quebra, tab e espaço: para com modelo_faltou_valor (#2573)', :aggregate_failures do
        contato.update!(name: " \n\t ")
        recebida(conversa, 30.hours.ago)
        execucao = rodar(conversa)

        expect(mandada(conversa)).to be_nil
        expect(registros(execucao)).to eq([%w[p1 falhou modelo_faltou_valor]])
        expect(execucao.reload.estado).to eq('parada')
        expect(pedidos).to be_empty
      end

      it 'janela aberta: sai o texto livre, nunca o modelo', :aggregate_failures do
        recebida(conversa, 1.hour.ago)
        rodar(conversa)

        expect(mandada(conversa).content).to eq('Seu pedido saiu.')
        expect(saiu_pela_graph(conversa)['type']).to eq('text')
      end

      it 'o contato que pediu para não receber pula antes do modelo' do
        contato.update!(opted_out_at: 1.day.ago)
        recebida(conversa, 30.hours.ago)
        execucao = rodar(conversa)

        expect(mandada(conversa)).to be_nil
        expect(registros(execucao)).to eq([%w[p1 pulado contato_nao_recebe]])
      end

      it 'valor vazio numa variável: para com modelo_faltou_valor (#2573)', :aggregate_failures do
        contato.update!(name: '')
        recebida(conversa, 30.hours.ago)
        execucao = rodar(conversa)

        expect(mandada(conversa)).to be_nil
        expect(registros(execucao)).to eq([%w[p1 falhou modelo_faltou_valor]])
        expect(execucao.reload.estado).to eq('parada')
      end

      it 'robô do outro lado: o modelo para pela mesma trava do texto, sem mandar nada', :aggregate_failures do
        anti_laco = instance_double(Autonomia::Automacao::AntiLaco, robo_do_outro_lado?: true, avisar_parada: nil)
        allow(Autonomia::Automacao::AntiLaco).to receive(:new).and_return(anti_laco)
        recebida(conversa, 30.hours.ago)
        execucao = rodar(conversa)

        expect(mandada(conversa)).to be_nil
        expect(registros(execucao)).to eq([%w[p1 falhou laco_suspeito]])
        expect(anti_laco).to have_received(:avisar_parada).with(execucao, 'p1')
        expect(pedidos).to be_empty
      end

      {
        'a caixa não tem o modelo' => [{ 'name' => 'outro' }, 'modelo_fora_da_caixa'],
        'o modelo não está aprovado' => [{ 'status' => 'PENDING' }, 'modelo_nao_aprovado'],
        'o modelo é de autenticação' => [{ 'category' => 'AUTHENTICATION' }, 'modelo_de_categoria_fora'],
        'o modelo pede outras variáveis' => [{ 'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}.' }] }, 'modelo_mudou'],
        'o modelo pede imagem no topo' => [{ 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' },
                                                              { 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}.' }] }, 'modelo_mudou']
      }.each do |caso, (troca, motivo)|
        it "#{caso} depois de salvar: para com #{motivo}, sem mandar nada (#2573)", :aggregate_failures do
          automacao = automacao_ligada(account, admin, [passo])
          com_modelos(modelo_aprovado.merge(troca))
          recebida(conversa, 30.hours.ago)
          execucao = rodar(conversa, automacao)

          expect(mandada(conversa)).to be_nil
          expect(registros(execucao)).to eq([['p1', 'falhou', motivo]])
          expect(execucao.reload.estado).to eq('parada')
          expect(pedidos).to be_empty
        end
      end
    end

    context 'with a caixa híbrida pronta (WAHA)' do
      around { |exemplo| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { exemplo.run } }

      before do
        WhatsappHybrid::Connection.create!(
          account: account, inbox: canal.inbox, session_name: "hybrid-#{SecureRandom.hex(3)}", status: 'connected',
          connected_phone: canal.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
        )
        WhatsappHybrid::Config.forget_inbox(canal.inbox.id)
      end

      it 'fora da janela oficial, manda: a resposta sai pelo WhatsApp API', :aggregate_failures do
        recebida(conversa, 30.hours.ago)
        execucao = rodar(conversa)

        expect(conversa.whatsapp_api_reply?).to be(true)
        expect(mandada(conversa).content).to eq('Seu pedido saiu.')
        expect(registros(execucao)).to eq([['p1', 'ok', nil]])
      end

      it 'com modelo no passo, o Híbrido pronto continua mandando texto: modelo só onde a janela bloqueia', :aggregate_failures do
        recebida(conversa, 30.hours.ago)
        rodar(conversa)

        expect(mandada(conversa).content).to eq('Seu pedido saiu.')
        expect(mandada(conversa).additional_attributes.to_h['template_params']).to be_nil
      end
    end
  end
end
