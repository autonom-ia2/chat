require 'rails_helper'

# #3225: a leitura da mensagem que o cliente manda no meio do turno. O que lê (em ordem, a partir da âncora e da rajada),
# onde para (a ilegível, o teto de voltas, o relógio), quando vale (a flag, fora da Lia, com a espera da fala e a fila, fora
# do e-mail) e as duas perguntas que os outros turnos fazem ao banco (`cobre?`, `respondida_junto?`).
RSpec.describe Autonomia::Agents::Operate::LeituraNoTurno do
  let(:account) { create(:account).tap { |conta| conta.enable_features!(described_class::FLAG) } }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { criar_principal(account) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil) }
  let!(:ancora) { recebe('França, 15 a 20/01, 40 anos') }
  let(:linhas) { [] }

  before do
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_including('[autonomia][turno]')) { |linha| linhas << linha }
  end

  def recebe(texto, **extras)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: texto, **extras)
  end

  # O texto de cada mensagem: o conteúdo, ou nil (ilegível) na marcada como tal (o Responder decide de verdade).
  def leitor(rajada: [ancora.id])
    described_class.new(conversation: conversation, agent: agent, delivery: delivery, ancora: ancora.id, rajada: rajada) do |m|
      m.content unless m.content_attributes.to_h['ilegivel']
    end
  end

  def textos(itens)
    itens.map { |item| item[:content].first[:text] }
  end

  describe '#antes_de_enviar' do
    it 'sem nada novo: nada, e nenhuma volta' do
      expect(leitor.antes_de_enviar('{"reply":"rascunho"}')).to eq([])
    end

    it 'com mensagem nova: o rascunho como fala do agente, o aviso e a mensagem, e ela fica com o turno', :aggregate_failures do
      leitura = leitor
      nova = recebe('Conhece lá?')

      itens = leitura.antes_de_enviar('{"reply":"rascunho"}')

      expect(itens.map { |item| item[:role] }).to eq(%w[assistant developer user])
      expect(itens.first).to eq(role: 'assistant', content: [{ type: 'output_text', text: '{"reply":"rascunho"}' }])
      expect(textos(itens)[1]).to include('ainda não foi enviada', 'a mensagem a seguir', 'uma resposta só')
      expect(textos(itens).last).to eq('Conhece lá?')
      expect(delivery.lidas_no_turno).to eq([nova.id])
      expect(linhas.join).to include('mensagem_lida_no_turno', "lida=#{nova.id}", 'etapa=antes_de_enviar')
    end

    it 'duas novas: as duas em ordem, e o aviso no plural' do
      leitura = leitor
      recebe('Conhece lá?')
      recebe('E o seguro cobre esqui?')

      itens = leitura.antes_de_enviar('rascunho')

      expect(textos(itens)[1]).to include('as mensagens a seguir')
      expect(textos(itens).last(2)).to eq(['Conhece lá?', 'E o seguro cobre esqui?'])
    end

    it 'não relê o que já leu' do
      leitura = leitor
      recebe('Conhece lá?')
      leitura.antes_de_enviar('rascunho')

      expect(leitura.antes_de_enviar('rascunho 2')).to eq([])
    end

    it 'relógio esgotado: não lê, e registra a parada' do
      leitura = leitor
      nova = recebe('Conhece lá?')

      expect(leitura.antes_de_enviar('rascunho', esgotado: true)).to eq([])
      expect(delivery.lidas_no_turno).to be_empty
      expect(linhas.join).to include('leitura_parou', "lida=#{nova.id}", 'motivo=relogio')
    end
  end

  describe 'a rajada que já foi na pergunta (#3225 f)' do
    it 'a mensagem maior que a âncora que já entrou na rajada conta como lida, e não é lida de novo', :aggregate_failures do
      junto = recebe('Conhece lá?')
      leitura = leitor(rajada: [ancora.id, junto.id])

      expect(delivery.lidas_no_turno).to eq([junto.id])
      expect(leitura.antes_de_enviar('rascunho')).to eq([])
      expect(leitura.metadata).to eq('lidas_no_turno' => [junto.id], 'voltas' => 0)
    end

    it 'a rajada anterior à âncora não conta como lida' do
      anterior = ancora
      ancora_nova = recebe('e o meu filho?')
      described_class.new(conversation: conversation, agent: agent, delivery: delivery, ancora: ancora_nova.id,
                          rajada: [anterior.id, ancora_nova.id], &:content)

      expect(delivery.lidas_no_turno).to be_empty
    end
  end

  describe 'onde a leitura para' do
    it 'na ilegível: lê a de antes, para nela e não lê nada depois, nem na leitura seguinte', :aggregate_failures do
      leitura = leitor
      primeira = recebe('Conhece lá?')
      ilegivel = recebe('foto', content_attributes: { 'ilegivel' => true })
      recebe('E esqui?')

      expect(textos(leitura.na_rodada)).to eq([Autonomia::Agents::Answerer::AVISO_DE_MENSAGEM_NOVA, 'Conhece lá?'])
      expect(leitura.antes_de_enviar('rascunho')).to eq([])
      expect(delivery.lidas_no_turno).to eq([primeira.id])
      expect(linhas.join).to include('leitura_parou', "lida=#{ilegivel.id}", 'motivo=ilegivel')
    end

    it 'erro ao ler a mensagem conta como ilegível' do
      leitura = described_class.new(conversation: conversation, agent: agent, delivery: delivery, ancora: ancora.id) do |_m|
        raise ArgumentError, 'falhou'
      end
      recebe('Conhece lá?')

      expect(leitura.antes_de_enviar('rascunho')).to eq([])
      expect(delivery.lidas_no_turno).to be_empty
    end

    it 'no teto de voltas: não lê mais, e registra' do
      leitura = leitor
      described_class::MAX_VOLTAS.times { leitura.contar_volta!(:antes_de_enviar) }
      nova = recebe('Conhece lá?')

      expect(leitura.antes_de_enviar('rascunho')).to eq([])
      expect(linhas.join).to include('leitura_parou', "lida=#{nova.id}", 'motivo=teto')
    end

    it 'lê no máximo LIMITE por vez, e o resto na seguinte', :aggregate_failures do
      leitura = leitor
      novas = Array.new(described_class::LIMITE + 2) { |i| recebe("linha #{i}") }

      expect(textos(leitura.na_rodada).size).to eq(described_class::LIMITE + 1)
      expect(textos(leitura.na_rodada).size).to eq(3)
      expect(delivery.lidas_no_turno).to eq(novas.map(&:id))
    end

    it 'mensagem da equipe ou nota não é lida (só o que o cliente mandou)' do
      leitura = leitor
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'oi')
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, private: true,
                       content: 'nota')

      expect(leitura.na_rodada).to eq([])
    end
  end

  describe '.ligada?' do
    it 'com a flag, num agente comum: sim' do
      expect(described_class.ligada?(agent, conversation)).to be(true)
    end

    it 'sem a flag: não' do
      account.disable_features!(described_class::FLAG)
      expect(described_class.ligada?(agent, conversation.reload)).to be(false)
    end

    it 'na Lia: não, mesmo com a flag e as opções gravadas' do
      lia = criar_principal(account, agent_type: 'insurance_quote', config: { 'conversa_em_fila' => true, 'conversa_espera_a_fala' => true })
      expect(described_class.ligada?(lia, conversation)).to be(false)
    end

    it 'sem a fila (P2) ou sem a espera da fala (P1): não', :aggregate_failures do
      desligar_paridade!(agent, 'conversa_em_fila')
      expect(described_class.ligada?(agent, conversation)).to be(false)

      outro = criar_principal(account, nome: 'Outro')
      desligar_paridade!(outro, 'conversa_espera_a_fala')
      expect(described_class.ligada?(outro, conversation)).to be(false)
    end

    it 'na caixa de e-mail: não' do
      email = create(:channel_email, account: account).inbox
      expect(described_class.ligada?(agent, create(:conversation, account: account, inbox: email))).to be(false)
    end
  end

  describe '.cobre? e .respondida_junto?' do
    let(:robo) { create(:agent_bot, account: account) }
    let(:nova) { recebe('Conhece lá?') }

    def responde(reply_to:, lidas: nil, agente: agent)
      atributos = { 'autonomia_agent_id' => agente.id, 'autonomia_reply_to_message_id' => reply_to }
      atributos[described_class::CHAVE] = lidas if lidas
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       sender: robo, content: 'resposta', content_attributes: atributos)
    end

    it 'lida e sem resposta própria: o turno que leu responde por ela' do
      expect(described_class.cobre?(conversation, nova.id, [nova.id])).to be(true)
    end

    it 'lida, mas o turno dela já respondeu: não cobre (o turno que leu fica superado)' do
      responde(reply_to: nova.id)
      expect(described_class.cobre?(conversation, nova.id, [nova.id])).to be(false)
    end

    it 'não lida: não cobre, sem consultar o banco' do
      pendente = nova.id
      allow(conversation).to receive(:messages).and_call_original
      expect(described_class.cobre?(conversation, pendente, [])).to be(false)
      expect(conversation).not_to have_received(:messages)
    end

    it 'respondida junto: a resposta do mesmo agente gravou a lida', :aggregate_failures do
      expect(described_class.respondida_junto?(conversation, nova.id, agent)).to be(false)
      responde(reply_to: ancora.id, lidas: [nova.id])
      expect(described_class.respondida_junto?(conversation, nova.id, agent)).to be(true)
    end

    it 'a resposta que leu é de outro agente (o dono mudou): não é respondida junto' do
      responde(reply_to: ancora.id, lidas: [nova.id], agente: criar_principal(account, nome: 'Outro'))
      expect(described_class.respondida_junto?(conversation, nova.id, agent)).to be(false)
    end

    it 'id que só parece (12 em 123) não casa' do
      responde(reply_to: ancora.id, lidas: [(nova.id * 10) + 3])
      expect(described_class.respondida_junto?(conversation, nova.id, agent)).to be(false)
    end

    it 'sem a flag: não é respondida junto, sem consultar o banco' do
      responde(reply_to: ancora.id, lidas: [nova.id])
      account.disable_features!(described_class::FLAG)
      expect(described_class.respondida_junto?(conversation.reload, nova.id, agent)).to be(false)
    end
  end

  describe '#no_silencio' do
    it 'no turno superado: quem superou e quantos ms depois da última leitura', :aggregate_failures do
      leitura = leitor
      freeze_time do
        leitura.antes_de_enviar('rascunho')
        travel 3.seconds
        nova = recebe('Conhece lá?')
        conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => nova.id } })

        leitura.no_silencio('turno_superado')

        expect(linhas.last).to include('leitura_no_silencio', 'motivo=turno_superado', 'lidas=0', 'voltas=0',
                                       "superou=#{nova.id}", 'depois_da_leitura=true', 'ms=3000')
      end
    end

    it 'noutro silêncio: só as lidas e as voltas' do
      leitor.no_silencio('sinal')
      expect(linhas.last).to include('motivo=sinal', 'lidas=0', 'voltas=0')
      expect(linhas.last).not_to include('superou=')
    end
  end
end
