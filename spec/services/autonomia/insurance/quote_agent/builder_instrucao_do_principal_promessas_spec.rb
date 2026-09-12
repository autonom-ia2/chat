require 'rails_helper'

# A INSTRUÇÃO DA LIA NÃO PROMETE O QUE O CÓDIGO NÃO TEM — entrega 9, no molde da entrega 3
# (`builder_instrucao_do_especialista_spec`), agora para o principal.
#
# O que a entrega 9 acrescentou ao texto é a regra da DÚVIDA DURANTE A COTAÇÃO (§7.1): pergunta de
# cobertura sozinha, com os preços ainda correndo, não aciona o especialista e não recota — ela é
# respondida por `consultar_condicoes_gerais`, e a cotação em andamento segue. Cada uma dessas
# frases só pode existir no texto porque algo no código a sustenta; a frase some, o exemplo reprova;
# a capacidade some, o exemplo reprova.
#
# O FATO QUE ORIGINOU A ENTREGA: a ferramenta JÁ ESTAVA LIGADA no principal (`TOOLS_DO_PRINCIPAL`) e
# no agente 24 em produção — o plano dizia o contrário. O que faltava era prova e guarda, e é isso
# que está aqui e no spec de integração (`answerer_duvida_durante_cotacao_spec`).
module ManualDoPrincipal
  ARQUIVO = Autonomia::Insurance::QuoteAgent::Builder::INSTRUCOES.join('principal.md')
  CONDICOES_GERAIS = Autonomia::Agents::Tools::Native::InsuranceGeneralConditions
  COTACAO = Autonomia::Agents::Tools::Native::InsuranceQuote

  module_function

  def principal
    Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_PRINCIPAL
  end

  # CADA PROMESSA NOVA DA §7.1, PELA FRASE EXATA, E O QUE A SUSTENTA.
  PROMESSAS = {
    # Responder a dúvida sem passar pelo especialista só é possível porque a ferramenta é DO
    # PRINCIPAL: se ela estivesse reservada por um especialista, o `Answerer` a esconderia do
    # principal (`enabled_agent_tools`) e a frase seria uma ordem impossível.
    'Dúvida sozinha não é pedido de cotação' => lambda {
      principal.include?('consultar_condicoes_gerais') &&
        Autonomia::Agents::Tools::Registry.find('consultar_condicoes_gerais') == CONDICOES_GERAIS &&
        Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_ESPECIALISTA.exclude?('consultar_condicoes_gerais')
    },
    # A cotação continuar correndo NÃO é promessa de conduta do modelo: é consequência de a consulta
    # ser SÍNCRONA. Só ferramenta assíncrona abre execução (`Bound#accept_async`), e é a abertura que
    # supersedia a execução viva da conversa (`ToolRun.open!`). Ferramenta síncrona não toca em
    # `autonomia_agent_tool_runs` — a cotação em andamento sobrevive ao turno da dúvida.
    'a cotação continua correndo' => -> { !CONDICOES_GERAIS.async? && COTACAO.async? },
    # Perguntar de qual seguradora é a dúvida não é capricho: o parâmetro é obrigatório no schema, e
    # sem ele a ferramenta recusa antes de consultar (`condicoes_sem_seguradora`).
    'Se ela não disse de qual seguradora' => lambda {
      CONDICOES_GERAIS.openai_schema[:parameters][:required].include?('seguradora') &&
        CONDICOES_GERAIS.params.find { |p| p['name'] == 'seguradora' }['required'] != false
    },
    # Voltar ao especialista quando o dado muda é o que o código faz: a abertura compara a identidade
    # do pedido (`ToolRun::PEDIDO`, gravada na abertura) e barra o repetido (entrega 10) — dado
    # diferente abre execução nova, dado igual não. Sem essa comparação, mandar o agente só voltar
    # "quando o dado mudar" não teria nada por baixo.
    'muda um dado ou pede outra configuração' => lambda {
      Autonomia::Agents::ToolRun.respond_to?(:abrir_ou_repetida) &&
        Autonomia::Agents::ToolRun.const_defined?(:PEDIDO) &&
        Autonomia::Agents::Tools::Bound.private_instance_methods.include?(:recusar_pela_repeticao) &&
        Autonomia::Agents::Tools::PedidoRepetido::MOTIVO.present?
    }
  }.freeze
end

RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:texto) { ManualDoPrincipal::ARQUIVO.read }
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:condicoes_gerais) { ManualDoPrincipal::CONDICOES_GERAIS }

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def construir
    described_class.new(account: account, nome_agente: 'Lia', nome_corretora: 'Seguros do Vale').call
  end

  describe 'promessa e capacidade da §7.1 (dúvida durante a cotação)' do
    ManualDoPrincipal::PROMESSAS.each do |frase, sustenta|
      it "«#{frase.tr("\n", ' ')}» tem o que a sustenta" do
        expect(texto).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end

    # A frase sobre recotar existe porque a §7.1 proíbe as DUAS coisas — acionar o especialista e
    # mandar cotar de novo. Sem ela o texto proibiria só metade.
    it 'proíbe as duas coisas: acionar o especialista e recotar' do
      expect(texto).to include('não acione o especialista e não mande cotar de novo')
    end
  end

  # QUALQUER FERRAMENTA CITADA NO TEXTO É DO PRINCIPAL E EXISTE NO CATÁLOGO. O espelho da guarda do
  # especialista ("não cita ferramenta que não é dele"): citar `cotar_seguro` aqui seria mandar o
  # principal chamar o que o `Answerer` esconde dele; citar um slug que não existe seria pior — o
  # `Registry` descarta em silêncio e o agente nunca reclama.
  describe 'ferramenta citada é ferramenta que ele tem' do
    it 'todo slug do catálogo que aparece no texto está em TOOLS_DO_PRINCIPAL' do
      citadas = Autonomia::Agents::Tools::Registry.slugs.select { |slug| texto.include?(slug) }

      expect(citadas).to include('consultar_condicoes_gerais')
      expect(citadas - described_class::TOOLS_DO_PRINCIPAL).to be_empty
    end

    it 'toda ferramenta de TOOLS_DO_PRINCIPAL citada existe no Registry' do
      described_class::TOOLS_DO_PRINCIPAL.select { |slug| texto.include?(slug) }.each do |slug|
        expect(Autonomia::Agents::Tools::Registry.find(slug)).to be_present
      end
    end
  end

  # TERMO 3 — HABILITADA NOS AGENTES QUE JÁ EXISTEM. A consulta às condições gerais NÃO depende de
  # conexão com o portal: explicar cobertura vale antes de existir qualquer cotação, e um agente de
  # corretora que ainda não conectou (ou cuja conexão caiu) continua respondendo dúvida. O contraste
  # com a cotação, no mesmo agente e no mesmo estado, é o que dá sentido à afirmação.
  describe 'a ferramenta chega ao agente sem conexão com o portal (termo 3)' do
    it 'available_for? é verdadeiro com o módulo ligado e sem conexão AGGER' do
      agente = construir

      expect(Autonomia::Insurance::Connection.for_account(account)).to be_empty
      expect(condicoes_gerais.available_for?(agente)).to be(true)
      expect(ManualDoPrincipal::COTACAO.available_for?(agente)).to be(false)
    end

    it 'entra no catálogo do turno do agente de cotação, sem conexão nenhuma' do
      agente = construir

      expect(Autonomia::Agents::Tools::Bound.for_agent(agente).map(&:slug))
        .to include('consultar_condicoes_gerais')
    end

    it 'nenhum especialista a reserva — ela continua visível para o principal' do
      agente = construir

      expect(agente.specialists.flat_map(&:tool_slugs)).not_to include('consultar_condicoes_gerais')
    end

    it 'sai do prompt quando o módulo de seguros está desligado' do
      agente = construir
      account.update!(internal_attributes: { 'autonomia_insurance_enabled' => false })

      expect(condicoes_gerais.available_for?(agente.reload)).to be(false)
    end
  end

  # O ARQUIVO É LIDO COM AS ESCOLHAS SUBSTITUÍDAS (#380): a §7.1 não pode trazer marcador novo.
  it 'a seção nova não introduz variável para substituir' do
    expect(texto[/### 7\.1.*?\n## 8/m].to_s.scan(/\$[a-zA-Z]+/)).to be_empty
  end
end
