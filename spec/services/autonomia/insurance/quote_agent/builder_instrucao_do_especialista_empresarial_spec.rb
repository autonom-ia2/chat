require 'rails_helper'

# O MANUAL DO ESPECIALISTA DE EMPRESARIAL NÃO PROMETE O QUE O CÓDIGO NÃO TEM (chat#641), no molde do de residencial.
# Cada frase que depende de uma capacidade aponta para o que a sustenta; a frase some, o exemplo reprova; a
# capacidade some, o exemplo reprova. E o texto é assinado por md5, para que prosa nova seja revisada.
module ManualDoEspecialistaDeEmpresarial
  BUILDER = Autonomia::Insurance::QuoteAgent::Builder
  DADOS = BUILDER::ESPECIALISTAS.find { |e| e[:slug] == 'cotacao_empresarial' }.freeze
  ARQUIVO = BUILDER::INSTRUCOES.join(DADOS.fetch(:arquivo))
  # O formulário que o especialista lê: o schema de empresarial que o adapter devolve, na cópia do mock.
  SCHEMA = Autonomia::Insurance::Connector::Mock::SCHEMA_EMPRESARIAL
  DECLARACAO = Autonomia::Agents::Tools::Native::InsuranceQuote::Declaracao::ClassMethods
  BUSCA = Autonomia::Agents::Tools::Native::AtividadeLookup
  COTACAO = Autonomia::Agents::Tools::Native::InsuranceQuote
  # AS COBERTURAS DO CLIENTE (adapters, commit e3aeb7b): os dez campos que o especialista escreve em reais, pelo pedido
  # do cliente ou pela apólice anterior.
  COBERTURAS = %w[responsabilidadeCivilOperacoes isDanosRoubo isDanosVendaval isDanosEletricos isDanosDespesasFixas vidros
                  isDanosImpactoVeiculo isDanosVazamentoTanquesTubulacoes isDanosAluguel isDanosDesmoronamento]
               .map { |nome| "configuracoes.#{nome}" }.freeze

  module_function

  def campo(nome)
    SCHEMA['campos'].find { |c| c['campo'] == nome }
  end

  def obrigatorios
    SCHEMA['campos'].select { |c| c['obrigatorio'] }.pluck('campo')
  end

  def descricao(nome)
    campo(nome).to_h['descricao'].to_s
  end

  # Cada cobertura existe no formulário, é opcional e é do cliente: sem pedido e sem apólice, fica vazia.
  def coberturas_do_cliente?
    COBERTURAS.all? { |nome| campo(nome).to_h.values_at('obrigatorio', 'origem') == [false, 'cliente'] }
  end

  # A entrada da cotação leva a cobertura como o especialista a escreveu, em configuracoes, onde o adapter a lê.
  def cobertura_chega_a_entrada?
    entrada = Autonomia::Insurance::QuoteInput.new(
      produto: 'empresarial', dados: {}, commission_percent: nil, grupos_do_ramo: %w[segurado configuracoes],
      params: { 'cpf' => '11222333000181', 'configuracoes' => { 'imovelNumero' => '1540', 'isDanosVendaval' => 20_000 } }
    ).to_h
    entrada.dig('configuracoes', 'isDanosVendaval') == 20_000
  end

  def ferramenta?(slug, classe)
    BUILDER.ferramentas_do_especialista(DADOS).include?(slug) && Autonomia::Agents::Tools::Registry.find(slug) == classe
  end

  PROMESSAS = {
    # Os quatro do mínimo: o documento, o número (o CEP chega pelo segurado) e o valor são o que a conferência do
    # adapter cobra; o quarto, a atividade, vai fora do formulário, pela busca.
    'Peça só o mínimo. São quatro coisas:' => lambda {
      obrigatorios.sort == %w[configuracoes.imovelNumero configuracoes.isDanosIncendioRaioExplosao segurado.cpfCnpj].sort &&
        DECLARACAO::RAMOS_COM_ATIVIDADE.include?('empresarial')
    },
    'consulte-o** com consultar_cep' => -> { ferramenta?('consultar_cep', Autonomia::Agents::Tools::Native::CepLookup) },
    'Busque com buscar_atividade' => -> { ferramenta?('buscar_atividade', BUSCA) },
    'com até três termos' => -> { BUSCA.params.first['description'].include?('De 1 a 3 termos') },
    'mande as escolhidas em atividades na cotação' => lambda {
      DECLARACAO::ATIVIDADES['name'] == 'atividades' &&
        DECLARACAO::ATIVIDADES['items']['properties'].pluck('name') == %w[seguradora key value]
    },
    # A regra de escolha também chega ao modelo pela própria busca, no texto que ela devolve.
    'Onde a lista separa térreo de andar superior' => -> { BUSCA::COMO_ESCOLHER.include?('térreo de andar superior') },
    'deixe essa seguradora de fora' => -> { BUSCA::COMO_ESCOLHER.include?('deixe essa seguradora de fora') },
    # A saída do beco chega ao modelo também pela busca, nas duas respostas em que ela pode aparecer.
    'Nenhuma seguradora com a atividade' => lambda {
      [BUSCA::NADA_ACHADO, BUSCA::COMO_ESCOLHER].all? { |texto| texto.include?('encaminhar para alguém da equipe') }
    },
    # Pedido de outro ramo volta com o nome dele, e o principal decide: aciona quem cota, ou diz que a corretora não
    # atende. Sem essa regra no principal, a devolução não teria destino.
    'Se o pedido é de outro ramo, diga qual é o ramo' => lambda {
      BUILDER::INSTRUCOES.join('principal.md').read.include?('Se não há especialista para o ramo que a pessoa quer')
    },
    'Razão social você não pede.' => -> { campo('segurado.nome')['origem'] == 'derivado' },
    'O que o seguro protege também não se pergunta.' => lambda {
      campo('configuracoes.imovelObjetoSegurado').values_at('obrigatorio', 'padrao') == [false, 3]
    },
    'Nada além dos quatro se pergunta por iniciativa própria' => lambda {
      %w[configuracoes.seguradoProprietario configuracoes.imovelConstrucao configuracoes.imovelPossuiAlarme
         configuracoes.zonaRural].all? { |nome| campo(nome)['obrigatorio'] == false }
    },
    # AS COBERTURAS DO CLIENTE (25/09/2026). A leitura da apólice "com os valores" só tem onde escrever desde que o
    # adapter publicou os campos de cobertura, e o valor lido tem de chegar à entrada da cotação.
    'as coberturas com os valores**, cada uma no campo dela (§6)' => -> { coberturas_do_cliente? && cobertura_chega_a_entrada? },
    # Não se pergunta, e a descrição de cada campo diz o mesmo, na ação.
    'Cobertura não se pergunta.' => lambda {
      coberturas_do_cliente? && COBERTURAS.all? { |nome| descricao(nome).include?('Não pergunte por esta cobertura') }
    },
    # O pedido vence a apólice, e zero é tirar: a descrição que o modelo lê diz os dois, campo a campo.
    '**Zero só quando o cliente pedir para tirar a cobertura.**' => lambda {
      COBERTURAS.all? do |nome|
        descricao(nome).include?('o que ele pedir vence a apólice') && descricao(nome).include?('0 só quando ele pedir para tirá-la')
      end
    },
    # As travas medidas pelo adapter chegam ao modelo na descrição do campo; a conferência cobra as mesmas.
    'RC Operações vai até metade do valor a segurar.' => lambda {
      descricao('configuracoes.responsabilidadeCivilOperacoes').include?('até metade do valor a segurar')
    },
    'Despesas fixas vão até 20% do valor a segurar.' => -> { descricao('configuracoes.isDanosDespesasFixas').include?('até 20% do valor a segurar') },
    'Só prédio não tem roubo.' => lambda {
      descricao('configuracoes.isDanosRoubo').include?('Não existe em seguro só do prédio') &&
        campo('configuracoes.imovelObjetoSegurado')['valores']['1'] == 'Prédio'
    },
    # O limite volta ao modelo dentro do turno, pela conferência, com o texto que o adapter escreveu.
    '**Quando a conferência devolver o limite, leve a pergunta ao cliente:**' => lambda {
      motivo = 'despesas fixas passa do máximo aceito, que é 20% do valor a segurar. Pergunte ao cliente.'
      texto = COTACAO.allocate.conferencia_para_o_modelo([{ 'campo' => 'configuracoes.isDanosDespesasFixas', 'motivo' => motivo }])
      COTACAO.instance_methods.include?(:precheck) && texto.include?(motivo)
    }
  }.freeze
end

RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:do_ramo) { ManualDoEspecialistaDeEmpresarial::ARQUIVO.read }
  let(:texto) { described_class.instrucao_do_especialista(ManualDoEspecialistaDeEmpresarial::DADOS.fetch(:arquivo)) }

  describe 'promessa e capacidade' do
    ManualDoEspecialistaDeEmpresarial::PROMESSAS.each do |frase, sustenta|
      it "«#{frase}» tem o que a sustenta" do
        expect(do_ramo).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end

    it 'o comparativo e a escolha vêm do bloco comum, como em auto e residencial' do
      expect(texto).to include('## K. O comparativo', '## L. Quando o cliente escolhe')
      expect(do_ramo).not_to include('## K.', '## L.')
    end

    it 'não cita ferramenta que não é dele' do
      proprias = described_class.ferramentas_do_especialista(ManualDoEspecialistaDeEmpresarial::DADOS)
      alheias = Autonomia::Agents::Tools::Registry.slugs - proprias

      expect(alheias.select { |slug| texto.include?(slug) }).to be_empty
    end
  end

  describe 'o texto' do
    it 'não escreve valor em reais, crase, travessão nem variável' do
      expect(do_ramo).not_to include('R$', '`', '—', '–')
      expect(texto).not_to include('$')
    end

    # Escrito em 24/09/2026 (chat#641): o manual de residencial como molde, com o mínimo de empresarial e a escolha
    # da atividade por seguradora (opção C do Rodrigo: casar por seguradora, deixar de fora a ambígua).
    # Revisão da chat#654 (`288d8321…` -> `aed6c14c…`): nenhuma seguradora com a atividade encaminha para a equipe, em
    # vez de perguntar de novo o que a empresa faz.
    # Pela paridade da jornada (`aed6c14c…` -> `92573c6a…`, 25/09/2026): mais de um local deixa de ser recusa (§2 e o
    # item do que nunca faz), porque o bloco comum manda cotar cada bem em paralelo; entra o "cote direto" da §3, só
    # com a atividade já escolhida; e o que nunca faz ganha o item do segurado, que a §D.1 do bloco comum sustenta.
    # Pelas coberturas do cliente (`92573c6a…` -> `45780295…`, 25/09/2026): entra a §6, com a regra das
    # coberturas (não se pergunta; o pedido vence a apólice; vazio sem os dois; zero só para tirar), as travas de RC
    # Operações, despesas fixas e roubo em só prédio, e o limite da conferência levado ao cliente. A §5.1 aponta para
    # os campos de cobertura, as coberturas da apólice deste local valem em outro nome, a lapidação cita tirar vidros,
    # o que nunca faz ganha o zero não pedido e passa a ser a §7.
    it 'é o texto revisado — mudou? revise PROMESSAS e assine aqui' do
      expect(Digest::MD5.hexdigest(ManualDoEspecialistaDeEmpresarial::ARQUIVO.binread)).to eq('457802955a512d3cb803ac33be27baff')
    end
  end
end
