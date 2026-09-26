require 'rails_helper'

# O RAMO QUE A CORRETORA TRABALHA E A IA NÃO COTA (conversa 7150, 26/09/2026). A pessoa perguntou por seguro de vida, e
# a Lia disse que a corretora trabalhava com ele "com opções em 8 seguradoras" e que cotava. Decisão do CEO (opção 1):
# a Lia diz que a corretora trabalha com o seguro e encaminha para a equipe; como cotação na hora, só oferece o que tem
# especialista nesta conta.
#
# Cada frase nova do manual da Lia só existe porque algo no código a sustenta, EXERCITADO aqui: a lista separada de
# `consultar_produtos_cotacao`, o parâmetro que anota o ramo, a guarda de `cotar_seguro` e a nota da equipe. A frase
# some, o exemplo reprova; a capacidade some, também. O bloco da ferramenta na §5 é assinado por md5 (a frase-âncora
# não vê texto novo ao lado dela); o bloco dos especialistas já é, em `builder_instrucao_do_principal_promessas_spec`.
module ManualDoRamoSemEspecialista
  ARQUIVO = Autonomia::Insurance::QuoteAgent::Builder::INSTRUCOES.join('principal.md')
  # Do subtítulo da ferramenta até o próximo subtítulo.
  SECAO_PRODUTOS = /### consultar_produtos_cotacao\n.*?(?=\n### )/m
  SECAO_ESPECIALISTAS = /### Os especialistas de ramo.*?(?=\n## \d)/m
  SECAO_HUMANO = /## 10\. Quando passar para um humano.*?(?=\n## \d)/m
  CAPACIDADES = Autonomia::Agents::Tools::Native::InsuranceCapabilities
  COTACAO = Autonomia::Agents::Tools::Native::InsuranceQuote
  NOTA = Autonomia::Agents::NotaDoEncaminhamento

  # Frase do bloco da ferramenta -> o que a sustenta. Roda no contexto do exemplo (`instance_exec`).
  PROMESSAS_DA_FERRAMENTA = {
    'em duas listas: os ramos que você cota na hora' => lambda {
      saida = CAPACIDADES.new(agent: lia).call
      saida.start_with?('A IA cota na hora, nesta conta: Auto') && saida.include?('que a IA não cota e ficam com a equipe da corretora: Vida.')
    },
    'escreva o código dele em ramo_pedido' => lambda {
      CAPACIDADES.new(agent: lia, params: { 'ramo_pedido' => 'vida' }, delivery: turno).call
      CAPACIDADES.openai_schema(lia)[:parameters][:properties]['ramo_pedido']['enum'] == ['vida', nil] &&
        Autonomia::Agents::Tools::RecusasRecentes.retirar(conversation.id) == ['ramo_pedido:vida']
    },
    'mande ramo_pedido nulo' => lambda {
      CAPACIDADES.openai_schema(lia)[:parameters][:required] == ['ramo_pedido'] &&
        CAPACIDADES.openai_schema(lia)[:parameters][:properties]['ramo_pedido']['type'] == %w[string null]
    }
  }.freeze

  # Frase do bloco dos especialistas e da §10 -> o que a sustenta.
  PROMESSAS_DA_CONDUTA = {
    # A guarda no código: mesmo que o modelo tente, a cotação de vida não abre.
    'cota, não pede dados para cotar e não dá a entender que vai cotar.' => lambda {
      COTACAO.new(agent: lia, params: { 'item' => 'Vida', 'produto' => 'vida', 'dados' => '{}' }).precheck.motivo ==
        'ramo_sem_especialista'
    },
    # O encaminhamento é o handoff do CRM, disparado pela fala da Lia. O que é nosso é a nota: ela diz o ramo.
    'que vai encaminhar para alguém da equipe, que cuida dele.' => lambda {
      COTACAO.new(agent: lia, params: { 'item' => 'Vida', 'produto' => 'vida', 'dados' => '{}' }, delivery: turno).precheck
      NOTA.postar(conversation)&.content.to_s.include?('- cotar vida: a pessoa pediu este seguro')
    },
    # Fora das duas listas é o que a conexão não traz, ou traz desligado: a ferramenta não o cita em lista nenhuma, e
    # ele não é valor aceito em ramo_pedido.
    'Fora das duas listas: diga que a corretora não atende esse seguro' => lambda {
      saida = CAPACIDADES.new(agent: lia).call
      enum = CAPACIDADES.openai_schema(lia)[:parameters][:properties]['ramo_pedido']['enum']
      saida.exclude?('Celular') && saida.exclude?('Bike') && enum.exclude?('celular') && enum.exclude?('bike')
    },
    'o que você oferece como cotação na hora é só a lista' => lambda {
      CAPACIDADES.new(agent: lia).call.start_with?('A IA cota na hora, nesta conta: Auto (2 seguradoras).')
    },
    # Mesmo quando a recusa só aparece no envio, o evento que a Lia recebe manda encaminhar: exercitado pelo envio.
    'Ela quer um seguro que a corretora trabalha e você não cota na hora (seção 5).' => lambda {
      cotacao = COTACAO.new(agent: lia, params: { 'item' => 'Vida', 'produto' => 'vida', 'dados' => '{}' })
      handle = cotacao.start
      evento = cotacao.poll(handle: handle, attempt: 0).evento
      evento == 'falhou' &&
        COTACAO.fatos_do_evento(evento, Autonomia::Agents::ToolRun.new(handle: handle)).include?('vai encaminhar para alguém da equipe')
    }
  }.freeze
end

RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:texto) { ManualDoRamoSemEspecialista::ARQUIVO.read }
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:lia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                     enabled: true, instruction: 'Atenda.')
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:turno) do
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: nil)
  end

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    enable_test_encryption!
    create(:agent_bot, account: account).tap do |bot|
      Autonomia::Agents::AgentInbox.create!(agent: lia, inbox: inbox, account: account, agent_bot: bot)
    end
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                    .update!(status: 'ready', capabilities: { 'products' => [
                                               { 'product' => 'auto', 'enabled' => true,
                                                 'insurers' => [{ 'enabled' => true }, { 'enabled' => true }] },
                                               { 'product' => 'vida', 'enabled' => true, 'insurers' => [{ 'enabled' => true }] },
                                               { 'product' => 'celular', 'enabled' => false }
                                             ] })
    Autonomia::Agents::Tools::RecusasRecentes.retirar(conversation.id)
  end

  describe 'o bloco de consultar_produtos_cotacao da §5' do
    let(:secao) { texto[ManualDoRamoSemEspecialista::SECAO_PRODUTOS] }

    ManualDoRamoSemEspecialista::PROMESSAS_DA_FERRAMENTA.each do |frase, sustenta|
      it "«#{frase}» tem o que a sustenta" do
        expect(secao).to include(frase)
        expect(instance_exec(&sustenta)).to be_truthy
      end
    end

    # Conversa 7150 (`971be704…`, novo, 26/09/2026): duas listas, e o ramo da segunda anotado para a equipe em ramo_pedido
    # já na primeira consulta (revisão: os valores aceitos são a própria lista).
    it 'mudou? revise PROMESSAS_DA_FERRAMENTA e assine aqui' do
      expect(secao).to start_with('### consultar_produtos_cotacao')
      expect(Digest::MD5.hexdigest(secao)).to eq('971be7040ed85ba5fd5c93b7a0fcf398')
    end

    it 'não traz frase de exemplo, travessão, crase nem variável' do
      expect(secao).not_to include('*"', '—', '–', '`')
      expect(secao.scan(/\$[a-zA-Z]+/)).to be_empty
    end
  end

  describe 'a conduta no bloco dos especialistas e na §10' do
    let(:blocos) { [texto[ManualDoRamoSemEspecialista::SECAO_ESPECIALISTAS], texto[ManualDoRamoSemEspecialista::SECAO_HUMANO]].join }

    ManualDoRamoSemEspecialista::PROMESSAS_DA_CONDUTA.each do |frase, sustenta|
      it "«#{frase}» tem o que a sustenta" do
        expect(blocos).to include(frase)
        expect(instance_exec(&sustenta)).to be_truthy
      end
    end

    # A regra antiga dizia "a corretora não atende esse seguro" para todo ramo sem especialista: com vida na conexão,
    # isso seria mentira. Ela ficou só para o que está fora das duas listas.
    it 'a regra antiga não vale mais para o ramo que a corretora trabalha' do
      expect(blocos).not_to include('ofereça o que ela atende')
      expect(blocos).not_to include('—', '–', '`')
    end
  end
end
