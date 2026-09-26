require 'rails_helper'

# AS FRASES NOVAS DA VOZ DA LIA NÃO PROMETEM O QUE O CÓDIGO NÃO TEM (itens 9, 6 e 5A, 26/09/2026), no molde de
# `builder_instrucao_do_principal_promessas_spec`: cada frase está no manual, e o que a sustenta é exercitado. A frase
# some, o exemplo reprova; a capacidade some, o exemplo reprova. As assinaturas por md5 dos blocos continuam onde
# estavam (`builder_instrucao_do_principal_promessas_spec` e `builder_instrucao_do_especialista_spec`).
module PromessasDaVozDaLia
  INSTRUCOES = Autonomia::Insurance::QuoteAgent::Builder::INSTRUCOES
  PRINCIPAL = INSTRUCOES.join('principal.md')
  COMUM = INSTRUCOES.join('comum_especialista.md')
  RETORNO = Autonomia::Insurance::QuoteAgent::RetornoDoEspecialista
  COTACAO = Autonomia::Agents::Tools::Native::InsuranceQuote
  FAIXA = Autonomia::Insurance::Faixa

  module_function

  def especialista_mantido
    Autonomia::Agents::Specialist.new(slug: 'cotacao_residencial', agent: Autonomia::Agents::Agent.new(agent_type: 'insurance_quote'))
  end

  def fatos_de(tipo, handle: {}, arguments: {})
    run = Autonomia::Agents::ToolRun.new(faixa: 'residencial:apto', handle: handle, arguments: { 'item' => 'apto' }.merge(arguments))
    COTACAO.fatos_do_evento(tipo, run)
  end

  # Duas cotações da mesma mensagem da pessoa, a primeira já contada; -> os fatos do aviso da segunda.
  def aviso_com_vizinha_contada
    account = FactoryBot.create(:account)
    inbox = FactoryBot.create(:inbox, account: account)
    conversa = FactoryBot.create(:conversation, account: account, inbox: inbox, assignee: nil)
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                              enabled: true, instruction: 'Atenda.')
    primeira, segunda = %w[casa apto].map do |item|
      Autonomia::Agents::ToolRun.create!(account: account, agent: agente, slug: 'cotar_seguro', status: 'done', origin_message_id: 5,
                                         faixa: FAIXA.de('residencial', item), conversation_id: conversa.id,
                                         execution_key: SecureRandom.uuid, arguments: { 'item' => item },
                                         handle: { Autonomia::Agents::Tools::Evento::FECHO_KEY => 'concluida' })
    end
    FactoryBot.create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :outgoing, content: 'x',
                                content_attributes: { Autonomia::Agents::Tools::Evento::CHAVE => "#{primeira.id}:concluida" })
    COTACAO.fatos_do_evento('concluida', segunda)
  end

  # A FRASE DO MANUAL DA LIA -> o que a sustenta.
  DO_PRINCIPAL = {
    # 5A: o identificador do bem é nosso, e o aviso e a situação dizem como chamar o bem.
    '**Todo bem se chama como a pessoa chama:**' => lambda {
      fatos_de('concluida').include?(FAIXA::NOME_NA_CONVERSA) &&
        FAIXA.descricao(Autonomia::Agents::ToolRun.new(faixa: 'auto:onix', arguments: { 'item' => 'onix' })).include?('bem de identificador onix')
    },
    # 9: o especialista de cotação devolve os fatos, nas partes que a frase enumera.
    'O especialista devolve fatos, não fala' => lambda {
      partes = RETORNO::SCHEMA[:schema][:required]
      runner = Autonomia::Agents::Specialists::Runner.new(specialist: especialista_mantido, request: 'x')
      runner.send(:fatos?) &&
        partes == %w[o_que_fez resultado_lido pedido_que_entrou pedido_que_nao_coube falta_perguntar contexto_da_pessoa]
    },
    'o que não coube e por quê, o que falta perguntar e por quê' => lambda {
      texto = RETORNO.texto({ 'pedido_que_nao_coube' => [{ 'pedido' => 'a', 'motivo' => 'b' }],
                              'falta_perguntar' => [{ 'dado' => 'c', 'por_que' => 'd' }] })
      texto.include?('não coube: a (b).') && texto.include?("#{RETORNO::AINDA_FALTA} c (d).")
    },
    # 6: o aviso traz o que a frase manda dizer.
    'conte que saiu, chamando o bem pelo nome que a pessoa dá a ele.' => -> { fatos_de('concluida').include?(FAIXA::NOME_NA_CONVERSA) },
    'tirado dos fatos do aviso' => lambda {
      nomes = COTACAO.params.pluck('name')
      texto = fatos_de('concluida', arguments: { 'pedido_que_entrou' => 'franquia reduzida', 'pedido_que_nao_coube' => 'vidros' })
      nomes.include?('pedido_que_entrou') && nomes.include?('pedido_que_nao_coube') &&
        texto.include?("#{COTACAO::PEDIDO_AS_SEGURADORAS} franquia reduzida.") &&
        texto.include?('Do pedido da pessoa, não coube: vidros.')
    },
    'trouxeram preço, para quem é.' => lambda {
      fatos_de('concluida', handle: { COTACAO::DELIVERED_KEY => %w[1 2] }).include?('Seguradoras que trouxeram preço: 2.')
    },
    'cotação do mesmo pedido, não repita a forma daquela mensagem.' => -> { aviso_com_vizinha_contada.include?('já contada à pessoa') },
    # Revisão adversarial: o pedido é o que o especialista pediu, não o que cada seguradora cotou.
    'O que foi pedido não é o que cada seguradora cotou' => lambda {
      fatos_de('concluida', arguments: { 'pedido_que_entrou' => 'vidros' }).include?(COTACAO::NEM_SEMPRE_COTADO)
    },
    # A contagem é o único número que vem do aviso, e não de ferramenta.
    'a contagem de seguradoras que trouxeram preço, que vem no próprio aviso.' => lambda {
      fatos_de('concluida', handle: { COTACAO::DELIVERED_KEY => %w[1] }).include?('trouxeram preço: 1.')
    }
  }.freeze

  # A FRASE DO BLOCO COMUM DO ESPECIALISTA -> o que a sustenta.
  DO_COMUM = {
    'você devolve **fatos**' => -> { Autonomia::Agents::Specialists::Runner.new(specialist: especialista_mantido, request: 'x').send(:fatos?) },
    '**O que do pedido não coube**, cada um com o motivo' => lambda {
      RETORNO::SCHEMA.dig(:schema, :properties, :pedido_que_nao_coube, :items, :required) == %w[pedido motivo]
    },
    '**O que falta perguntar**, cada dado pelo nome que o cliente reconhece, e por que ele é preciso.' => lambda {
      RETORNO::SCHEMA.dig(:schema, :properties, :falta_perguntar, :items, :required) == %w[dado por_que]
    },
    '**O que o cliente revelou** de si e do pedido' => -> { RETORNO::SCHEMA.dig(:schema, :properties, :contexto_da_pessoa).present? },
    'ponha a troca no que você fez' => -> { RETORNO.texto({ 'o_que_fez' => 'troquei' }).include?('O que ele fez: troquei') },
    # §H, §I e §L: o que não é dado do cliente vai no que fez, e só o que falta perguntar vira a linha "Ainda falta:".
    'A dúvida vai no que você fez, nunca no que falta perguntar' => lambda {
      RETORNO.texto({ 'o_que_fez' => 'dúvida de vidro, é das condições gerais' }).exclude?(RETORNO::AINDA_FALTA)
    }
  }.freeze
end

RSpec.describe 'As promessas da voz da Lia' do # rubocop:disable RSpec/DescribeClass
  describe 'as frases novas do manual da Lia' do
    PromessasDaVozDaLia::DO_PRINCIPAL.each do |frase, sustenta|
      it "«#{frase}» tem o que a sustenta" do
        expect(PromessasDaVozDaLia::PRINCIPAL.read).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end
  end

  describe 'as frases novas do bloco comum do especialista' do
    PromessasDaVozDaLia::DO_COMUM.each do |frase, sustenta|
      it "«#{frase}» tem o que a sustenta" do
        expect(PromessasDaVozDaLia::COMUM.read).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end
  end

  # O QUE SAIU E NÃO PODE VOLTAR: o especialista escrevendo texto pronto para ser parafraseado.
  it 'nenhum dos dois manuais manda o especialista devolver texto pronto nem o principal parafrasear' do
    [PromessasDaVozDaLia::PRINCIPAL.read, PromessasDaVozDaLia::COMUM.read].each do |texto|
      expect(texto).not_to include('texto pronto', 'parafrase', 'texto corrido')
    end
  end
end
