require 'rails_helper'

# A RENOVAÇÃO EM RESIDENCIAL E EMPRESARIAL NO BLOCO COMUM (§D.2, 25/09/2026). A regra é a mesma nos dois ramos de
# imóvel, e por isso mora no comum, com a ressalva explícita de que auto segue a seção dele. Cada frase que depende
# de uma capacidade aponta para o que a sustenta, no molde de `PromessaDoSegurado`: a âncora é o ARQUIVO do bloco
# comum; a frase some, o exemplo reprova; a capacidade some, o exemplo reprova. A assinatura md5 do bloco comum mora
# em `builder_instrucao_do_especialista_spec`.
module PromessaDaRenovacaoDosRamos
  MOCK = Autonomia::Insurance::Connector::Mock
  SCHEMAS = { 'residencial' => MOCK::SCHEMA_RESIDENCIAL, 'empresarial' => MOCK::SCHEMA_EMPRESARIAL }.freeze
  CAMPOS = %w[seguradoraAnterior bonus sinistros numeroApolice fimVigencia].map { |nome| "renovacao.#{nome}" }.freeze
  BUILDER = Autonomia::Insurance::QuoteAgent::Builder
  COTACAO = Autonomia::Agents::Tools::Native::InsuranceQuote

  module_function

  def campo(ramo, nome)
    SCHEMAS.fetch(ramo)['campos'].find { |c| c['campo'] == nome }.to_h
  end

  def grupo_no_formulario(ramo)
    Autonomia::Insurance::Parametros.do_ramo(SCHEMAS.fetch(ramo)).find { |g| g['name'] == 'renovacao' }.to_h
  end

  # Os cinco campos existem nos dois ramos, são do cliente e opcionais: a conferência do adapter cobra os que a
  # renovação exige, e só quando o grupo vem.
  def campos_do_cliente_e_opcionais?
    SCHEMAS.keys.product(CAMPOS).all? { |ramo, nome| campo(ramo, nome).values_at('origem', 'obrigatorio') == ['cliente', false] }
  end

  def entrada(ramo, renovacao)
    Autonomia::Insurance::QuoteInput.new(produto: ramo, params: { 'renovacao' => renovacao }, dados: {}, commission_percent: nil,
                                         grupos_do_ramo: Autonomia::Insurance::Parametros.new(SCHEMAS.fetch(ramo), ramo: true)
                                                                                     .nomes_dos_grupos).to_h
  end

  # A descrição que o modelo lê no campo, como o adapter a escreveu.
  def descricao(ramo, nome)
    campo(ramo, nome)['descricao'].to_s
  end

  # O PDF que o cliente manda chega ao especialista, cercado como dado, com o texto dele.
  def apolice_chega_ao_especialista?
    Autonomia::Agents::Specialists::Materia.instance_method(:initialize).parameters.include?(%i[key documents]) &&
      Autonomia::Agents::PromptParts::Documentos.mensagem([{ name: 'apolice.pdf', text: 'Classe de bônus: 5' }])
                                                .dig(:content, 0, :text).to_s.include?('Classe de bônus: 5')
  end

  # O texto da conferência chega ao modelo como o adapter o escreveu.
  def conferencia_chega_como_veio?(motivo)
    COTACAO.instance_methods.include?(:precheck) &&
      COTACAO.allocate.conferencia_para_o_modelo([{ 'campo' => 'renovacao.seguradoraAnterior', 'motivo' => motivo }]).include?(motivo)
  end

  PROMESSAS = {
    # Auto tem a renovação dele no grupo `quotation`, e nenhum campo `renovacao`; o manual de auto guarda a seção.
    '**Auto não segue esta subseção:**' => lambda {
      MOCK::SCHEMA_AUTO['campos'].none? { |c| c['campo'].start_with?('renovacao.') } &&
        Autonomia::Insurance::QuoteInput::GRUPOS_DE_AUTO.include?('quotation') &&
        BUILDER::INSTRUCOES.join('especialista_auto.md').read.include?('### 4.2 Renovação')
    },
    'cada um no seu campo do grupo da renovação' => lambda {
      campos_do_cliente_e_opcionais? &&
        SCHEMAS.keys.all? { |ramo| grupo_no_formulario(ramo)['properties'].to_a.size == CAMPOS.size }
    },
    # O modelo escolhe da lista que o formulário publica; o adapter traduz o nome no código.
    '**A seguradora vai pelo nome que está na apólice**' => lambda {
      SCHEMAS.keys.all? do |ramo|
        nomes = campo(ramo, 'renovacao.seguradoraAnterior')['valores'].to_h.keys
        folha = grupo_no_formulario(ramo)['properties'].find { |p| p['name'] == 'seguradoraAnterior' }
        nomes.size > 1 && folha['enum'] == nomes
      end
    },
    '**ofereça ler a apólice**' => -> { apolice_chega_ao_especialista? },
    # A descrição do campo diz o mesmo: vem da apólice, nunca chutada.
    '**Nunca chute a seguradora anterior:**' => lambda {
      SCHEMAS.keys.all? { |ramo| descricao(ramo, 'renovacao.seguradoraAnterior').include?('nunca chute a seguradora') }
    },
    # Campo em branco é aceito (opcional), e a descrição do campo não manda perguntar: quem pergunta é a conferência.
    # Até o b7c08cc do adapter ela dizia "leia da apólice ou pergunte ao cliente", o contrário desta frase.
    '**Nada disso se pergunta por iniciativa própria.**' => lambda {
      campos_do_cliente_e_opcionais? &&
        SCHEMAS.keys.product(CAMPOS).none? { |ramo, nome| descricao(ramo, nome).include?('pergunte ao cliente') } &&
        SCHEMAS.keys.product(%w[bonus sinistros fimVigencia]).all? do |ramo, nome|
          descricao(ramo, "renovacao.#{nome}").include?('a ferramenta avisa o que perguntar')
        end
    },
    'o número da apólice ela não cobra' => lambda {
      SCHEMAS.keys.all? { |ramo| campo(ramo, 'renovacao.numeroApolice')['obrigatorio'] == false }
    },
    # Nulo é seguro novo: o grupo é opcional no formulário, nulo não chega à entrada, a descrição do campo manda o
    # grupo nulo sem a apólice, e cada pergunta de ausência da conferência (adapters 1fbe7ce) dá a mesma saída.
    '**Sem a apólice, o grupo da renovação vai nulo, e a cotação sai como seguro novo.**' => lambda {
      conferencia_chega_como_veio?('Se o cliente não está renovando, ou não tem ou não quer mandar a apólice que vence, ' \
                                   'mande o grupo da renovação nulo: é seguro novo.') &&
        SCHEMAS.keys.all? do |ramo|
          grupo_no_formulario(ramo)['required'] == false && !entrada(ramo, nil).key?('renovacao') &&
            descricao(ramo, 'renovacao.seguradoraAnterior').include?('Sem a apólice')
        end
    },
    # Sem a classe de bônus, seguro novo e nunca 0 (decisão do Rodrigo, 25/09/2026): a descrição do bônus e a pergunta
    # de ausência dele na conferência (adapters 1fbe7ce) dizem o mesmo, e o grupo nulo não chega à entrada.
    '**Sem a classe de bônus, também seguro novo.**' => lambda {
      conferencia_chega_como_veio?('Sem a classe na apólice nem com o cliente, mande todo o grupo da renovação nulo: ' \
                                   'sai como seguro novo. Não mande 0 no lugar da classe que falta.') &&
        SCHEMAS.keys.all? do |ramo|
          descricao(ramo, 'renovacao.bonus').include?('Sem a classe na apólice nem com o cliente, deixe todo o grupo da ' \
                                                      'renovação nulo: sai como seguro novo. Não mande 0 no lugar da classe ' \
                                                      'que falta.') && !entrada(ramo, nil).key?('renovacao')
        end
    },
    # A conferência do adapter manda cotar como seguro novo e avisar o cliente; o texto chega ao modelo como veio.
    '**Se a conferência disser que a seguradora anterior não tem tradução**' => lambda {
      conferencia_chega_como_veio?('se a seguradora do cliente não está na lista, mande sem o grupo da renovação e ' \
                                   'diga a ele que a cotação sai como seguro novo.') &&
        SCHEMAS.keys.all? { |ramo| !entrada(ramo, nil).key?('renovacao') }
    }
  }.freeze

  # SÓ INSTRUÇÃO, SEM CÓDIGO QUE A SUSTENTE. Que a cotação sem apólice, ou sem a classe de bônus, sai como seguro novo
  # está acima; o aviso ao cliente, uma vez, de que saiu sem o bônus e que com a apólice ou a classe se refaz, é o
  # especialista quem escreve. Nada no código o emite nem conta quantas vezes foi dito. A frase fica guardada aqui só
  # para não sumir do texto.
  SO_INSTRUCAO = [
    '**Quando ele disse que renova e a cotação saiu como seguro novo, avise uma vez**'
  ].freeze
end

RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:comum) { described_class::INSTRUCOES.join(described_class::ARQUIVO_COMUM_DO_ESPECIALISTA).read }

  describe 'a renovação dos ramos, no bloco comum (§D.2)' do
    PromessaDaRenovacaoDosRamos::PROMESSAS.each do |frase, sustenta|
      it "«#{frase}» está no bloco comum e tem o que a sustenta" do
        expect(comum).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end

    PromessaDaRenovacaoDosRamos::SO_INSTRUCAO.each do |frase|
      it "«#{frase}» está no bloco comum (só instrução)" do
        expect(comum).to include(frase)
      end
    end

    it 'chega aos dois ramos de imóvel, e nenhum manual de ramo repete a regra' do
      frase = '### D.2 A renovação em residencial e empresarial'
      manuais = %w[cotacao_residencial cotacao_empresarial cotacao_auto].map do |slug|
        [slug, described_class.instrucao_do_especialista(described_class::ESPECIALISTAS.find { |e| e[:slug] == slug }.fetch(:arquivo))]
      end

      expect(manuais.map { |_, texto| texto.scan(frase).size }).to all(eq(1))
      %w[especialista_residencial.md especialista_empresarial.md especialista_auto.md].each do |arquivo|
        expect(described_class::INSTRUCOES.join(arquivo).read).not_to include('grupo da renovação')
      end
    end
  end
end
