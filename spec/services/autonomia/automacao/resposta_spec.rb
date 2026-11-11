require 'rails_helper'

# G11 do fechamento do #2414: "esperar até o cliente responder" e "esperar até a equipe responder", com prazo. Os dois
# valores dizem se a resposta chegou DURANTE a espera; a mensagem acorda o "esperar até" na hora, também o do card.
RSpec.describe Autonomia::Automacao::Resposta, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:atendente) { create(:user, account: account, role: :agent) }
  let(:conversa) { create(:conversation, account: account, status: :open) }

  before { ligar_motor(account) }

  after { Current.reset }

  def respondeu(quem) = { 'campo' => { '$valor' => "conversa.#{quem}_respondeu" }, 'op' => 'igual', 'valor' => true }

  def esperar_resposta(quem, prazo = 30, unidade = 'minutos')
    { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => respondeu(quem), 'prazo' => { 'valor' => prazo, 'unidade' => unidade },
      'se_vencer' => [prioridade_passo('sem_resposta', 'high'), { 'id' => 'fim', 'tipo' => 'parar' }] }
  end

  def comecar_e_rodar(definicao, alvo = conversa)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, alvo) }.reload
  end

  def evento(nome, **dados) = Events::Base.new(nome, Time.zone.now, dados)

  # A mensagem gravada e o evento dela na escuta, com as rodadas que ele acorda.
  # Sem remetente de verdade (eco do celular, a própria automação), pelo trait: a factory põe uma pessoa no lugar do nil.
  def escreve(*traits, **atributos)
    mensagem = create(:message, *traits, account: account, conversation: conversa, inbox: conversa.inbox, **atributos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
    mensagem
  end

  def passos(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado)

  describe 'até o cliente responder' do
    let(:definicao) { automacao_ligada(account, admin, [esperar_resposta('cliente', 2, 'horas'), prioridade_passo('respondeu', 'low')]) }

    it 'o cliente responde durante a espera: segue na hora, sem esperar o prazo', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      expect(execucao.estado).to eq('esperando')

      travel(10.minutes) { escreve(message_type: :incoming) }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
      expect(passos(execucao)).to eq([%w[espera ok], %w[espera ok], %w[respondeu ok]])
    end

    # O começo da espera sai do prazo gravado: acordar sem resposta (outra mudança na conversa) não o move.
    it 'acordada por outra mudança, volta a esperar com o mesmo prazo, e a resposta depois ainda conta', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      prazo = execucao.due_at

      travel(20.minutes) do
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
          listener.conversation_updated(evento('conversation.updated', conversation: conversa))
        end
      end
      expect([execucao.reload.estado, execucao.due_at]).to eq(['esperando', prazo])

      travel(90.minutes) { escreve(message_type: :incoming) }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end

    # Quem já começou termina na versão em que entrou: o prazo novo de uma edição não desloca o começo da espera.
    it 'depois de editar o prazo, a espera aberta conta a resposta pelo prazo da versão em que começou', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      curta = [esperar_resposta('cliente', 10, 'minutos'), prioridade_passo('respondeu', 'low')]
      definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => curta }, autor: admin)
      expect(definicao.reload.versao_ativa_id).not_to eq(execucao.versao_id)

      travel(30.minutes) { escreve(message_type: :incoming) }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end

    it 'sem resposta no prazo: segue pelo "se vencer"', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)

      travel(2.hours + 1.minute) { varrer }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('high')
    end

    it 'a mensagem de antes da espera não conta como resposta' do
      travel(-1.minute) { create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming) }

      expect(comecar_e_rodar(definicao).estado).to eq('esperando')
    end

    it 'a resposta da equipe e a nota não acordam a espera do cliente', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)

      travel(5.minutes) do
        escreve(message_type: :outgoing, sender: atendente)
        escreve(message_type: :outgoing, sender: atendente, private: true)
      end

      expect(execucao.reload.estado).to eq('esperando')
      expect(conversa.reload.priority).to be_nil
    end

    # Prazo vencido e a varredura ainda não passou: a resposta acorda a espera pela escuta, mas já não conta.
    it 'a resposta depois do prazo, antes da varredura, não conta: segue pelo "se vencer"', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)

      travel(2.hours + 1.minute) { escreve(message_type: :incoming) }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('high')
      expect(passos(execucao).map(&:first)).to eq(%w[espera espera sem_resposta fim])
    end

    # Sem a escuta (o evento se perdeu), quem confere é a varredura no prazo: a resposta de dentro da janela conta.
    it 'a resposta que só a varredura vê, dentro do prazo, conta', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      travel(30.minutes) { create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming) }

      travel(2.hours + 1.minute) { varrer }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end
  end

  # Exemplo 10, passo 6: "Espera a Fernanda responder, por até 30 minutos. Sem resposta: avisa o dono."
  describe 'até a equipe responder' do
    let(:definicao) { automacao_ligada(account, admin, [esperar_resposta('equipe'), prioridade_passo('respondeu', 'low')]) }

    it 'a atendente responde ao cliente: segue na hora', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)

      travel(5.minutes) { escreve(message_type: :outgoing, sender: atendente) }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end

    it 'a equipe respondendo pelo app do celular (eco) conta como resposta' do
      execucao = comecar_e_rodar(definicao)

      travel(5.minutes) do
        escreve(:bot_message, content_attributes: { 'external_echo' => true }, source_id: 'wamid.do-celular')
      end

      expect(execucao.reload.estado).to eq('concluida')
    end

    # O eco da mensagem que nós mesmos mandamos (a IA ou a automação), que nasceu como mensagem nova porque chegou antes
    # de a bolha ter o id: não é a gerente respondendo.
    it 'o eco de uma mensagem nossa não conta: nem no Híbrido (id físico no wamid) nem na Cloud (mesmo wamid)', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      robo = create(:agent_bot, account: account)
      fisico = '3EB0A1B2C3D4E5F6'
      wamid = "wamid.#{Base64.strict_encode64([0x18, fisico.size].pack('C*') + fisico)}"
      eco = { content_attributes: { 'external_echo' => true } }

      travel(5.minutes) do
        create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :outgoing, sender: robo,
                         source_id: fisico)
        escreve(:bot_message, **eco, source_id: wamid)
        create(:message, :bot_message, account: account, conversation: conversa, inbox: conversa.inbox,
                                       content_attributes: { 'automacao_id' => definicao.id }, source_id: 'wamid.da-cloud')
        escreve(:bot_message, **eco, source_id: 'wamid.da-cloud')
      end

      expect(execucao.reload.estado).to eq('esperando')
    end

    it 'não contam: o cliente, a nota, o robô, o envio automático, a mensagem da automação e a que falhou', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      robo = create(:agent_bot, account: account)

      travel(5.minutes) do
        escreve(message_type: :incoming)
        escreve(message_type: :outgoing, sender: atendente, private: true)
        escreve(message_type: :outgoing, sender: robo)
        escreve(message_type: :outgoing, sender: atendente, content_attributes: { 'crm_follow_up_id' => 1 })
        escreve(message_type: :outgoing, sender: atendente, content_attributes: { 'automacao_id' => definicao.id })
        escreve(:bot_message, content_attributes: { 'automacao_id' => definicao.id })
        escreve(message_type: :outgoing, sender: atendente, status: :failed)
      end

      expect(execucao.reload.estado).to eq('esperando')
    end

    it 'sem resposta em 30 minutos: segue pelo "se vencer"', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)

      travel(31.minutes) { varrer }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('high')
    end
  end

  # O padrão do G11 (exemplo 10): a automação manda a mensagem e espera a equipe. Na caixa Híbrida, o eco dessa mensagem
  # volta pela Meta e passa pelo reconciliador de verdade (WhatsappHybrid::EchoReconcilerExtension).
  describe 'na caixa Híbrida, o eco da mensagem da automação' do
    let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:account) { canal.account }
    let(:cliente) { '5511900000001' }
    let(:fisico) { '3EB0C0FFEE000001' }
    let(:wamid) { "wamid.#{Base64.strict_encode64([0x18, fisico.size].pack('C*') + fisico)}" }
    let(:conversa) { chegou_do_cliente.conversation }
    let(:definicao) { automacao_ligada(account, admin, [esperar_resposta('equipe')]) }

    around { |exemplo| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { exemplo.run } }

    before { allow(WhatsappHybrid::Config).to receive(:hybrid_inbox?).and_return(true) }

    after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |chave| Redis::Alfred.delete(chave) } }

    def webhook(valor, eco: false)
      params = { object: 'whatsapp_business_account', phone_number: canal.phone_number,
                 entry: [{ changes: [{ field: eco ? 'smb_message_echoes' : 'messages', value: valor }] }] }.with_indifferent_access
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: canal.inbox, params: params, outgoing_echo: eco).perform
    end

    def chegou_do_cliente
      webhook({ contacts: [{ profile: { name: 'Paulo' }, wa_id: cliente }],
                messages: [{ from: cliente, id: 'wamid.do-cliente', timestamp: '1760371920', type: 'text', text: { body: 'oi' } }] })
      Message.find_by!(source_id: 'wamid.do-cliente')
    end

    def eco_da_meta
      webhook({ message_echoes: [{ from: canal.phone_number.delete('+'), to: cliente, id: wamid, timestamp: '1760371980',
                                   type: 'text', text: { body: 'A Fernanda já está vendo seu caso' } }] }, eco: true)
    end

    # A mensagem da automação como o envio pelo WhatsApp API a deixa: sem remetente, com a marca, e o id físico.
    def acalmar(source_id)
      create(:message, :bot_message, account: account, conversation: conversa, inbox: conversa.inbox,
                                     content_attributes: { 'automacao_id' => definicao.id }, source_id: source_id)
    end

    def acordar_pelas_mensagens_novas(desde)
      conversa.messages.where('id > ?', desde).find_each do |mensagem|
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
      end
    end

    it 'o reconciliador casa o eco na bolha: nada novo, a equipe não respondeu, e no prazo segue pelo "se vencer"', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      bolha = acalmar(fisico)

      travel(5.minutes) { expect { eco_da_meta }.not_to change(Message, :count) }

      expect(bolha.reload.source_id).to eq(wamid)
      expect(execucao.reload.estado).to eq('esperando')
      travel(31.minutes) { varrer }
      expect(conversa.reload.priority).to eq('high')
    end

    # A ordem real da corrida: o eco vira mensagem nova porque a bolha ainda não tem o id, e é no message_created dele
    # que a espera acorda. Com uma mensagem nossa ainda sem id antes dele, o eco é ambíguo e não conta agora; no prazo,
    # a varredura confere de novo, já com o id gravado, e o descarta.
    it 'o eco que chega antes de a bolha ter o id é ambíguo: não conta agora, e no prazo é descartado pelo id', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      bolha = acalmar(nil)
      ultima = conversa.messages.maximum(:id)

      travel(5.minutes) do
        expect { eco_da_meta }.to change(Message, :count).by(1)
        acordar_pelas_mensagens_novas(ultima)
      end
      expect(execucao.reload.estado).to eq('esperando')

      travel(6.minutes) { bolha.update!(source_id: fisico) }
      travel(31.minutes) { varrer }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('high')
    end

    # A pessoa respondeu de verdade pelo celular enquanto a mensagem nossa ainda não tinha o id: conta no prazo, atrasada.
    it 'o eco de uma pessoa, ambíguo na hora, conta no prazo quando a mensagem nossa já tem o id', :aggregate_failures do
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [esperar_resposta('equipe'), prioridade_passo('respondeu', 'low')]))
      bolha = acalmar(nil)

      travel(5.minutes) do
        webhook({ message_echoes: [{ from: canal.phone_number.delete('+'), to: cliente, id: 'wamid.da-pessoa', timestamp: '1760371990',
                                     type: 'text', text: { body: 'Oi, Paulo, sou a Fernanda' } }] }, eco: true)
        acordar_pelas_mensagens_novas(bolha.id)
      end
      expect(execucao.reload.estado).to eq('esperando')

      travel(6.minutes) { bolha.update!(source_id: fisico) }
      travel(31.minutes) { varrer }

      expect(conversa.reload.priority).to eq('low')
    end
  end

  describe 'no card' do
    let(:funil) { create_crm_pipeline(account: account, user: admin) }
    let(:card) do
      Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Seguro auto', currency: 'BRL',
                        primary_conversation: conversa, contact: conversa.contact)
    end
    let(:definicao) { automacao_ligada(account, admin, [esperar_resposta('cliente', 2, 'horas')]) }

    it 'a resposta na conversa principal acorda a execução do card na hora' do
      execucao = comecar_e_rodar(definicao, card)
      expect(execucao.estado).to eq('esperando')

      travel(10.minutes) { escreve(message_type: :incoming) }

      expect(execucao.reload.estado).to eq('concluida')
    end

    # #2680: o e-mail da automação abre outra conversa do mesmo contato, e a resposta chega nela.
    it 'a resposta do mesmo contato em outra conversa acorda o card na hora' do
      execucao = comecar_e_rodar(definicao, card)
      outra = create(:conversation, account: account, inbox: conversa.inbox, contact: conversa.contact)

      travel(10.minutes) do
        mensagem = create(:message, account: account, conversation: outra, inbox: outra.inbox, message_type: :incoming)
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
      end

      expect(execucao.reload.estado).to eq('concluida')
    end

    it 'a mensagem de outro contato não acorda o card' do
      execucao = comecar_e_rodar(definicao, card)
      outra = create(:conversation, account: account, inbox: conversa.inbox)

      travel(10.minutes) do
        mensagem = create(:message, account: account, conversation: outra, inbox: outra.inbox, message_type: :incoming)
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
      end

      expect(execucao.reload.estado).to eq('esperando')
    end
  end

  # Parecer da Funções no #2689: a resposta numa caixa que quem ligou não abre não decide o ramo.
  describe 'nas conversas que quem ligou vê' do
    let(:espera) { 1.hour.ago.. }
    let(:outra_caixa) { create(:inbox, account: account) }

    before do
      conversa.inbox.add_members([atendente.id])
      outra = create(:conversation, account: account, inbox: outra_caixa, contact: conversa.contact)
      create(:message, account: account, conversation: outra, inbox: outra_caixa, message_type: :incoming)
    end

    it 'a resposta na caixa que ele não abre não conta; para o administrador, conta', :aggregate_failures do
      expect(described_class.cliente?(conversa.contact, espera, atendente)).to be(false)
      expect(described_class.cliente?(conversa.contact, espera, admin)).to be(true)
    end

    it 'a resposta na caixa dele conta' do
      create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming)

      expect(described_class.cliente?(conversa.contact, espera, atendente)).to be(true)
    end

    it 'sem quem ligou, nunca respondeu' do
      expect(described_class.cliente?(conversa.contact, espera, nil)).to be(false)
    end
  end

  describe 'o salvar' do
    def problemas(passos)
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    it 'aceita a resposta na condição do "esperar até"' do
      expect(problemas([esperar_resposta('cliente')])).to be_empty
    end

    it 'recusa a resposta fora do "esperar até", com a frase', :aggregate_failures do
      no_se = [{ 'id' => 's1', 'tipo' => 'se', 'condicao' => respondeu('equipe'), 'entao' => [prioridade_passo('a1')] }]
      no_caminho = [prioridade_passo('a1', conversa_id: { '$valor' => 'conversa.cliente_respondeu' })]
      no_filtro = Autonomia::Automacao::Receita.new(
        { 'gatilho' => { 'tipo' => 'conversa.resolvida', 'filtros' => [respondeu('cliente')] }, 'passos' => [prioridade_passo('a1')] },
        conta: account, account_user: nil
      ).problemas

      expect(problemas(no_se)).to include(a_string_including('conversa.equipe_respondeu', '"wait until"'))
      expect(problemas(no_caminho)).to include(a_string_including('conversa.cliente_respondeu', '"wait until"'))
      expect(no_filtro).to include(a_string_including('conversa.cliente_respondeu', '"wait until"'))
    end

    it 'recusa valor que não seja sim ou não' do
      condicao = respondeu('cliente').merge('valor' => 'sim')
      expect(problemas([esperar_resposta('cliente').merge('condicao' => condicao)])).to include(a_string_including('true, false'))
    end
  end

  it 'fora da espera, e no card sem conversa, o valor lê false (nunca "respondeu")', :aggregate_failures do
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming)
    funil = create_crm_pipeline(account: account, user: admin)
    sem_conversa = Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Avulso', currency: 'BRL')
    valores = Autonomia::Automacao::Valores

    expect(valores.new(alvo: conversa, quem: nil).ler('conversa.cliente_respondeu')).to be(false)
    expect(valores.new(alvo: sem_conversa, quem: nil, espera: (1.hour.ago..)).ler('conversa.equipe_respondeu')).to be(false)
  end

  # G31 (#2800): o marco do "decidir" que decide de novo. O último id e os da margem saem da mesma leitura.
  describe '.marco' do
    it 'o último id e os ids da margem saem de uma consulta só às mensagens', :aggregate_failures do
      antiga = create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, created_at: 1.hour.ago)
      recente = create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming)
      consultas = []
      contar = ->(*, dados) { consultas << dados[:sql] if dados[:sql].include?('FROM "messages"') }

      marco = ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') { described_class.marco(conversa.contact, admin) }

      expect(consultas.size).to eq(1)
      expect(marco).to include('lido_ate' => recente.id, 'lidas_na_margem' => [recente.id])
      expect(marco['lidas_na_margem']).not_to include(antiga.id)
    end

    it 'sem mensagem do cliente, o marco é zero e a margem vazia' do
      expect(described_class.marco(conversa.contact, admin)).to include('lido_ate' => 0, 'lidas_na_margem' => [])
    end
  end
end
