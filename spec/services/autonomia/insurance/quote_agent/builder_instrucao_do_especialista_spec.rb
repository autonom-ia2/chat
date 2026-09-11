require 'rails_helper'

# O MANUAL DO ESPECIALISTA DE AUTO — entrega 3 do Agente de Cotação, termos 2 a 6.
#
# O texto é aprovado pelo PO e vive em `instrucoes/especialista_auto.md`. O que esta spec guarda não
# é o texto: é que ele NÃO PROMETE O QUE O CÓDIGO NÃO TEM. Duas mentiras já rodaram em produção: o
# manual mandava refazer a cotação com outra franquia quando a franquia não tinha por onde viajar, e
# listava valores de cobertura que não batiam com o pacote enviado. Cada promessa do texto está
# amarrada, pela frase exata, ao que a sustenta — a frase some do texto, a tabela reprova; a
# capacidade some do código, a tabela reprova. E o manual que vale é o do DEPLOY: um agente já
# criado o recebe sem ser recriado (termo 5), e um criado do zero nasce com o mesmo (termo 6).
#
# PROVA POR MUTAÇÃO (`mutacoes_e3.py`): promessa falsa acrescentada ao texto, valor de cobertura de
# volta, ferramenta tirada do especialista, `coverage` fora da entrada, runtime lendo a coluna —
# cada uma reprova um exemplo daqui.
module ManualDoEspecialistaDeAuto
  ARQUIVO = Autonomia::Insurance::QuoteAgent::Builder::INSTRUCOES.join('especialista_auto.md')
  SCHEMA = Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO

  module_function

  def campos
    @campos ||= SCHEMA['campos'].index_by { |c| c['campo'] }
  end

  # Só conta o que o MODELO RECEBE: campo presente no schema mas fora do formulário (`NAO_EXPOSTOS`)
  # é promessa sem capacidade do mesmo jeito.
  def expostos
    @expostos ||= Autonomia::Insurance::Parametros.new(SCHEMA).caminhos
  end

  def campo(nome)
    raise "o formulário do especialista não expõe #{nome}" unless expostos.include?(nome)

    campos.fetch(nome) { raise "o schema do adapter não tem #{nome}" }
  end

  def valores(nome)
    campo(nome)['valores'].to_h
  end

  def cotacao
    Autonomia::Agents::Tools::Native::InsuranceQuote
  end

  def grupos_da_entrada
    Autonomia::Insurance::QuoteInput::GRUPOS_DE_AUTO
  end

  # CADA PROMESSA, PELA FRASE EXATA, E O QUE A SUSTENTA. A frase é a âncora: se o texto mudar e a
  # frase sumir, o exemplo reprova — a tabela não pode envelhecer em silêncio.
  PROMESSAS = {
    'consulte-a' => lambda {
      Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_ESPECIALISTA.include?('consultar_placa') &&
        Autonomia::Agents::Tools::Registry.find('consultar_placa').present?
    },
    "a cotação consulta a\nplaca sozinha" => -> { cotacao.private_instance_methods.include?(:com_veiculo) },
    'A conferência é grátis e a cotação é paga' => lambda {
      cotacao.instance_methods.include?(:precheck) &&
        Autonomia::Insurance::Connector::Mock.instance_methods.include?(:quote_validate)
    },
    'basta mandar o PDF, que você tira tudo de lá' => -> { Autonomia::Agents::Specialists::Materia::MAX_DOCUMENTOS.positive? },
    'Cada parâmetro da ferramenta de cotação traz, escrito nele' => lambda {
      folhas = Autonomia::Insurance::Parametros.de_auto(SCHEMA).flat_map { |g| g['properties'] || [g] }
      folhas.any? && folhas.all? { |f| f['description'].present? }
    },
    'quer franquia maior' => -> { campo('coverage.deductibleType') && grupos_da_entrada.include?('coverage') },
    'mais cobertura de terceiros' => -> { campo('coverage.propertyDamage') && campo('coverage.bodilyInjury') },
    'incluir a filha que dirige' => -> { %w[vehicle.youngDriver vehicle.youngDriverAge vehicle.youngDriverGender].all? { |n| campo(n) } },
    'lembrou que tem rastreador' => -> { valores('vehicle.trackerCode').any? },
    'Antifurto tem a mesma armadilha' => -> { valores('vehicle.antiTheftCode').any? },
    'Renovação garantida' => -> { campo('quotation.isGuaranteedRenewal') },
    'Nunca chute a seguradora anterior' => -> { valores('quotation.previousInsurerCode').any? },
    'A mesma seguradora tem dois códigos' => -> { campo('quotation.previousInsurerCode')['descricao'].include?('DIFERENTE') },
    'associado a entidade de classe' => -> { campo('vehicle.isAssociate') },
    'com que frequência a moto é usada' => -> { campo('vehicle.usagePeriod') },
    'carroceria, tipo de carga e área de circulação' => lambda {
      %w[truck.bodyType truck.cargoType truck.circulationArea].all? { |n| campo(n) } && grupos_da_entrada.include?('truck')
    },
    'Empresa exige condutor, e exige o vínculo dele' => -> { campo('driver.document') && valores('driver.relationshipToInsured').any? },
    'Zero-quilômetro tem campo próprio' => -> { campo('vehicle.isZeroKm') },
    'Estado civil não tem "não informado"' => -> { valores('insured.maritalStatus').values.none? { |v| v.match?(/não informado/i) } },
    'FLEX não é GASOLINA' => -> { (valores('vehicle.fuelType').values & %w[FLEX GASOLINA]).size == 2 },
    'Garagem em casa não tem opção "0"' => -> { valores('vehicle.garageAtHome').any? && !valores('vehicle.garageAtHome').key?('0') },
    'Quilometragem é faixa, não número livre' => -> { valores('vehicle.monthlyMileageBand').any? },
    'No fim, o comparativo' => -> { cotacao.private_instance_methods.include?(:comparison_pdf) },
    'a resposta está nas condições gerais: ferramenta dele' => lambda {
      Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_PRINCIPAL.include?('consultar_condicoes_gerais')
    }
  }.freeze
end

RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:texto) { ManualDoEspecialistaDeAuto::ARQUIVO.read }
  let(:account) { create(:account) }

  def construir
    described_class.new(account: account, nome_agente: 'Clara', nome_corretora: 'Seguros do Vale').call
  end

  def especialista_de_auto
    construir.specialists.find_by!(slug: 'cotacao_auto')
  end

  describe 'promessa e capacidade (termos 2 e 4)' do
    ManualDoEspecialistaDeAuto::PROMESSAS.each do |frase, sustenta|
      it "«#{frase.tr("\n", ' ')}» tem o que a sustenta" do
        expect(texto).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end

    # O especialista só cita, como sua, ferramenta que tem. Qualquer outro slug do catálogo no texto
    # é promessa de capacidade alheia — foi assim que a v5 mandava consultar o que era do principal.
    it 'não cita ferramenta que não é dele' do
      alheias = Autonomia::Agents::Tools::Registry.slugs - described_class::TOOLS_DO_ESPECIALISTA
      citadas = alheias.select { |slug| texto.include?(slug) }

      expect(citadas).to be_empty
    end
  end

  # QUEM TEM O NÚMERO É UM LUGAR SÓ: o pacote e os seus valores vivem no adapter e chegam ao modelo
  # pela descrição dos parâmetros. No texto, nem valor em reais nem nome de pacote.
  describe 'nenhum valor de cobertura no texto (termo 3)' do
    it 'não escreve valor em reais' do
      expect(texto).not_to include('R$')
    end

    it 'não escreve nome de pacote' do
      nomes = ManualDoEspecialistaDeAuto.valores('coverage.packageCode').values

      expect(nomes).not_to be_empty
      expect(nomes.select { |nome| texto.include?(nome) }).to be_empty
    end
  end

  # O ARQUIVO É LIDO CRU em runtime (`Builder.instrucao_mantida`): variável aqui chegaria ao modelo
  # como `$nomeAgente`.
  it 'não tem variável para substituir' do
    expect(texto.scan(/\$[a-zA-Z]+/)).to be_empty
  end

  # PROSA NÃO SE VERIFICA POR MÁQUINA: uma promessa nova escrita com outras palavras ("emita a apólice")
  # passaria pela tabela. O que a máquina faz é NÃO DEIXAR O TEXTO MUDAR SEM REVISÃO: mudou uma letra,
  # este exemplo reprova, e quem o atualiza revisa `PROMESSAS` junto — o md5 é a assinatura da revisão.
  it 'é o texto revisado — mudou? revise PROMESSAS e assine aqui' do
    expect(Digest::MD5.hexdigest(ManualDoEspecialistaDeAuto::ARQUIVO.binread)).to eq('3eba319bca1e6159e950def73a2f91ab')
  end

  describe 'quem roda lê o manual do deploy (termos 5 e 6)' do
    it 'o agente já criado recebe o texto novo sem ser recriado' do
      especialista = especialista_de_auto
      especialista.update!(instruction: 'manual velho, gravado no nascimento')

      expect(especialista.reload.effective_instruction).to eq(texto)
    end

    it 'um agente criado do zero nasce com o mesmo texto, na coluna e no que roda' do
      especialista = especialista_de_auto

      expect(especialista.instruction).to eq(texto)
      expect(especialista.effective_instruction).to eq(texto)
    end

    it 'o que a corretora acrescenta entra depois do manual do deploy' do
      especialista = especialista_de_auto
      especialista.update!(custom_instruction: 'Fale como a Seguros do Vale.')

      expect(especialista.effective_instruction).to eq("#{texto}\n\nFale como a Seguros do Vale.")
    end

    it 'a descrição que o principal lê na função também é a do deploy' do
      especialista = especialista_de_auto
      especialista.update!(description: 'só pessoa física')

      expect(especialista.reload.openai_schema[:description]).to include('para empresa')
      expect(especialista.descricao_do_sistema).to eq(described_class::ESPECIALISTAS.first[:descricao])
    end

    it 'especialista que a corretora criou, fora do agente de cotação, continua lendo a própria instrução' do
      agente = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                                enabled: true, instruction: 'Atenda.')
      proprio = Autonomia::Agents::Specialist.create!(agent: agente, account: account, slug: 'cotacao_auto', name: 'Auto',
                                                      description: 'cota auto do jeito da corretora', instruction: 'Cote como eu mando.')

      expect(proprio.effective_instruction).to eq('Cote como eu mando.')
    end
  end
end
