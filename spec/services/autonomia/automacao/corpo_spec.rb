require 'rails_helper'

# Valor calculado no corpo da ação (G16 do fechamento do #2414): três formas fechadas, lidas na hora da execução.
RSpec.describe Autonomia::Automacao::Corpo do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:valores) { Autonomia::Automacao::Valores.new(alvo: conversa, quem: nil) }

  def montar(corpo) = described_class.new(corpo, valores: valores, conta: account).montar

  def data(origem, valor = nil, unidade = nil)
    { '$data' => { 'de' => origem, 'mais' => (valor && { 'valor' => valor, 'unidade' => unidade }) }.compact }
  end

  describe '#montar' do
    it 'copia o valor do alvo, monta o texto e deixa o literal como está, também dentro de custom_attributes' do
      corpo = { 'merge' => true, 'custom_attributes' => { 'quem' => { '$valor' => 'contato.nome' },
                                                          'nota' => { '$texto' => ['indicado por ', { '$valor' => 'contato.nome' }] },
                                                          'fixo' => 'site' } }

      expect(montar(corpo).corpo).to eq('merge' => true, 'custom_attributes' => { 'quem' => 'Maria', 'nota' => 'indicado por Maria',
                                                                                  'fixo' => 'site' })
    end

    it 'corpo sem valor calculado sai igual' do
      expect(montar({ 'priority' => 'urgent' }).corpo).to eq('priority' => 'urgent')
    end

    it '"hoje" é o dia da execução no fuso da conta, nunca o de UTC', :aggregate_failures do
      account.update!(custom_attributes: { 'timezone' => 'America/Sao_Paulo' })

      travel_to(Time.utc(2026, 11, 5, 1, 30)) do # 22h30 do dia 4 em São Paulo
        expect(montar({ 'd' => data('hoje') }).corpo).to eq('d' => '2026-11-04')
        expect(montar({ 'd' => data('hoje', 6, 'meses') }).corpo).to eq('d' => '2027-05-04')
      end
    end

    it 'soma pelo calendário: fim de mês, semanas, anos e N negativo', :aggregate_failures do
      travel_to(Time.utc(2027, 1, 31, 15)) do
        expect(montar({ 'd' => data('hoje', 1, 'meses') }).corpo).to eq('d' => '2027-02-28')
        expect(montar({ 'd' => data('hoje', 2, 'semanas') }).corpo).to eq('d' => '2027-02-14')
        expect(montar({ 'd' => data('hoje', 1, 'anos') }).corpo).to eq('d' => '2028-01-31')
        expect(montar({ 'd' => data('hoje', -31, 'dias') }).corpo).to eq('d' => '2026-12-31')
      end
    end

    # #2705: "até o fim do mês" (exemplo 6, passos 5 e 10). O fim vem depois da soma: hoje + 1 mês, no fim do mês, é o
    # último dia do mês que vem.
    it 'fim do mês: o último dia do mês da data, depois da soma, nos meses de 28, 29, 30 e 31 dias', :aggregate_failures do
      fim = ->(forma) { forma.merge('$data' => forma['$data'].merge('fim_do' => 'mes')) }

      travel_to(Time.utc(2027, 1, 10, 15)) do
        expect(montar({ 'd' => fim.call(data('hoje')) }).corpo).to eq('d' => '2027-01-31')
        expect(montar({ 'd' => fim.call(data('hoje', 1, 'meses')) }).corpo).to eq('d' => '2027-02-28')
        expect(montar({ 'd' => fim.call(data('hoje', 3, 'meses')) }).corpo).to eq('d' => '2027-04-30')
        expect(montar({ 'd' => fim.call(data('hoje', -1, 'meses')) }).corpo).to eq('d' => '2026-12-31')
      end
      travel_to(Time.utc(2028, 2, 3, 15)) { expect(montar({ 'd' => fim.call(data('hoje')) }).corpo).to eq('d' => '2028-02-29') }

      conversa.update!(custom_attributes: { 'entrega' => '2026-03-15' })
      expect(montar({ 'd' => fim.call(data({ '$valor' => 'conversa.atributos.entrega' }, 2, 'semanas')) }).corpo).to eq('d' => '2026-03-31')
    end

    it 'fim do mês no fuso da conta: às 22h30 do dia 31 em São Paulo ainda é o mês que acaba' do
      account.update!(custom_attributes: { 'timezone' => 'America/Sao_Paulo' })
      forma = { '$data' => { 'de' => 'hoje', 'fim_do' => 'mes' } }

      travel_to(Time.utc(2026, 11, 1, 1, 30)) { expect(montar({ 'd' => forma }).corpo).to eq('d' => '2026-10-31') }
    end

    it 'parte de um atributo de data, gravado como a tela grava ou com a hora', :aggregate_failures do
      conversa.update!(custom_attributes: { 'entrega' => '2026-03-31' })
      expect(montar({ 'd' => data({ '$valor' => 'conversa.atributos.entrega' }, 1, 'meses') }).corpo).to eq('d' => '2026-04-30')

      conversa.update!(custom_attributes: { 'entrega' => '2026-03-31T00:00:00.000Z' })
      expect(montar({ 'd' => data({ '$valor' => 'conversa.atributos.entrega' }) }).corpo).to eq('d' => '2026-03-31')
    end

    it 'valor vazio não deixa o corpo sair: nunca "indicado por " pela metade', :aggregate_failures do
      contato.update!(name: '')

      montado = montar({ 'nota' => { '$texto' => ['indicado por ', { '$valor' => 'contato.nome' }] }, 'fixo' => 'site' })
      expect([montado.corpo, montado.motivo]).to eq([nil, 'faltou_valor'])
      expect(montar({ 'quem' => { '$valor' => 'contato.nome' } }).motivo).to eq('faltou_valor')
      expect(montar({ 'd' => data({ '$valor' => 'conversa.atributos.entrega' }) }).motivo).to eq('faltou_valor')
    end

    it 'resolve dentro de listas, na posição de cada item' do
      corpo = { 'por' => [{ '$valor' => 'contato.nome' }, 'fixo'] }

      expect([montar(corpo).corpo, described_class.lugares(corpo).map(&:first)]).to eq([{ 'por' => %w[Maria fixo] }, [['por', 0]]])
    end

    it 'a data gravada com espaço antes da hora vale pelo dia escrito' do
      conversa.update!(custom_attributes: { 'entrega' => '2026-03-31 08:00:00' })

      expect(montar({ 'd' => data({ '$valor' => 'conversa.atributos.entrega' }) }).corpo).to eq('d' => '2026-03-31')
    end

    it 'dentro do $texto, false segue a regra do texto da mensagem: vazio, e a ação pula' do
      conversa.update!(custom_attributes: { 'vip' => false })

      expect(montar({ 'nota' => { '$texto' => ['VIP: ', { '$valor' => 'conversa.atributos.vip' }] } }).motivo).to eq('faltou_valor')
    end

    it 'false é valor (sim/não desmarcado), não vazio' do
      conversa.update!(custom_attributes: { 'vip' => false })

      expect(montar({ 'vip' => { '$valor' => 'conversa.atributos.vip' } }).corpo).to eq('vip' => false)
    end

    it 'a data lida que não é data pula com o motivo próprio' do
      conversa.update!(custom_attributes: { 'entrega' => 'semana que vem' })

      expect(montar({ 'd' => data({ '$valor' => 'conversa.atributos.entrega' }) }).motivo).to eq('data_invalida')
    end
  end

  describe '.exemplo' do
    it 'troca o calculado por um exemplo que o campo de destino aceita: a primeira opção da lista, ou o tipo dele' do
      corpo = { 'card' => { 'priority' => { '$valor' => 'conversa.atributos.nivel' }, 'score' => { '$valor' => 'card.id' },
                            'title' => { '$texto' => ['Pedido de ', { '$valor' => 'contato.nome' }] },
                            'custom_attributes' => { 'revisao' => data('hoje', 6, 'meses') } } }

      exemplo = described_class.exemplo('PATCH crm/cards/:id', corpo)

      expect(exemplo).to eq('card' => { 'priority' => 'low', 'score' => 1, 'title' => 'texto',
                                        'custom_attributes' => { 'revisao' => Date.current.iso8601 } })
    end
  end

  describe '.caminhos e .datas' do
    it 'lista o que o corpo lê, e o "de" das datas que não são "hoje"', :aggregate_failures do
      corpo = { 'a' => { '$valor' => 'contato.nome' }, 'b' => [{ '$texto' => ['x', { '$valor' => 'contato.email' }] }],
                'c' => data({ '$valor' => 'conversa.atributos.entrega' }, 1, 'dias'), 'd' => data('hoje') }

      expect(described_class.caminhos(corpo)).to eq(%w[contato.nome contato.email conversa.atributos.entrega])
      expect(described_class.datas(corpo)).to eq(%w[conversa.atributos.entrega])
    end
  end
end
