require 'rails_helper'

# O ESPECIALISTA É O DONO DO RESULTADO (chat#585, decisão do CEO em 22/09/2026). Perguntas sobre a cotação — o
# preço de uma seguradora, o andamento ("e aí?"), o que ela cotou, por que veio diferente do pedido — vão ao
# especialista, que confere e responde; a Lia repassa. Até aqui `ver_resultado_da_cotacao` era da Lia e só
# devolvia nome e preço: "por que a Suhai veio sem carro reserva?" não tinha resposta. Agora a oferta traz o
# que a seguradora cotou (adapters#75), o resultado o guarda, e a consulta por seguradora o mostra na mesma
# linha do preço dela — é a linha que a conferência da fala usa para autorizar cada valor. As chaves da cobertura são
# as que o `Connector::Http` entrega (snake_case), e não as do adapter.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuoteResult do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 90) }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:guardar) { Autonomia::Insurance::ResultadoPorSeguradora }
  let(:suhai_cotou) do
    { 'assistance' => 'Assistência 24 horas - Plano 2 - 500km', 'rental_car' => 'Não', 'glass' => 'Não',
      'property_damage' => 500_000, 'bodily_injury' => 500_000, 'moral_damage' => 20_000, 'deductible_type' => 'Reduzida',
      'deductible' => '50% da Obrigatória', 'deductible_amount' => 5795, 'referenced_value_percent' => 100,
      'extra_expenses' => false, 'fora_do_contrato' => 'não viaja' }
  end

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def cotou(code, name, amount, coverage = nil)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' }, 'coverage' => coverage }.compact
  end

  def cotacao_com(ofertas, status: 'done')
    Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: cotacao.slug, status: status,
                                       conversation_id: conversation.id, execution_key: SecureRandom.uuid, arguments: {},
                                       handle: { 'quote_id' => 'q-1:1', cotacao::RESULTADO_KEY => guardar.unir({}, ofertas) })
  end

  def ao_modelo(seguradora)
    described_class.new(agent: agent, params: { 'seguradora' => seguradora }, delivery: delivery).call
  end

  describe 'o que a seguradora cotou' do
    it 'fica guardado junto do preço, só com os campos de cobertura conhecidos' do
      guardado = guardar.unir({}, [cotou('20', 'Suhai', 2890.73, suhai_cotou)])

      expect(guardado['20']['cobertura']).to include('rental_car' => 'Não', 'property_damage' => 500_000)
      expect(guardado['20']['cobertura']).not_to have_key('fora_do_contrato')
    end

    it 'sem cobertura na oferta, a entrada fica como era' do
      guardado = guardar.unir({}, [cotou('20', 'Suhai', 2890.73)])

      expect(guardado['20']).not_to have_key('cobertura')
    end

    it 'a consulta por seguradora mostra o que ela cotou, na mesma linha do preço, com os valores escritos' do
      cotacao_com([cotou('20', 'Suhai', 2890.73, suhai_cotou)])

      linha = ao_modelo('Suhai').lines.find { |l| l.start_with?('Suhai') }

      expect(linha).to include('carro reserva: Não', 'vidros: Não', 'assistência: Assistência 24 horas - Plano 2 - 500km')
      expect(linha).to include('danos materiais: R$ 500.000,00', 'danos morais: R$ 20.000,00', 'franquia: 50% da Obrigatória')
      expect(linha).to include('valor da franquia: R$ 5.795,00', 'tabela FIPE: 100%', 'despesas extraordinárias: não')
      expect(linha).to include('R$ 2.890,73')
    end

    # A conferência autoriza cada valor pela linha da seguradora nos dados do turno: o valor da cobertura
    # que o especialista repassar precisa estar lá, senão a fala volta para reescrever.
    it 'os valores da cobertura entram nos dados que a conferência da fala usa' do
      cotacao_com([cotou('20', 'Suhai', 2890.73, suhai_cotou)])

      ao_modelo('Suhai')

      expect(Autonomia::Agents::ConferenciaDePrecos.valores(delivery.resultado_do_turno.texto)).to include(50_000_000, 289_073)
    end

    it 'a lista geral não carrega a cobertura de todas: ela é da pergunta por seguradora' do
      cotacao_com([cotou('20', 'Suhai', 2890.73, suhai_cotou), cotou('3', 'Mapfre', 3802.99)])

      expect(ao_modelo(nil)).not_to include('carro reserva')
    end
  end
end
