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
# O FORMULÁRIO E A ENTRADA, que é o que as promessas consultam. Mora separado da tabela porque são
# duas coisas: ler o que o adapter expõe ao modelo, e escrever a promessa que depende disso. A tabela
# só cresce, e misturar as duas fazia o módulo passar de 100 linhas a cada entrega.
module FormularioDoEspecialista
  SCHEMA = Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO

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

  # A entrada como o `QuoteInput` a monta para auto — é ela que chega ao adapter.
  def entrada_de_auto(params)
    Autonomia::Insurance::QuoteInput.new(produto: 'auto', params: params, dados: {}, commission_percent: nil).to_h
  end
end

module ManualDoEspecialistaDeAuto
  extend FormularioDoEspecialista

  ARQUIVO = Autonomia::Insurance::QuoteAgent::Builder::INSTRUCOES.join('especialista_auto.md')
  SCHEMA = FormularioDoEspecialista::SCHEMA

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
    # APÓLICE EM NOME DE TERCEIRO (#400). A regra manda separar o que é do VEÍCULO, que serve, do que
    # é do DONO, que não se transfere. Cada metade tem a sua âncora: sumiu a de cima, o formulário
    # não tem mais onde escrever o que se aproveita; sumiu a de baixo, a cotação seria marcada como
    # renovação com bônus alheio — e o preço não se sustenta na emissão.
    'placa, CEP, modelo, ano' => lambda {
      %w[vehicle.plate vehicle.overnightZipCode vehicle.fipeCode vehicle.modelYear].all? { |n| campo(n) }
    },
    'sem marcar renovação, sem bônus e sem histórico de sinistros' => lambda {
      %w[quotation.isRenewal quotation.bonusClass quotation.previousClaimsCount].all? { |n| campo(n)['obrigatorio'] == false }
    },
    # O AVISO SÓ É VERDADE SE A AUSÊNCIA FOR AUSÊNCIA: não marcar renovação e não mandar bônus tem de
    # significar seguro novo sem bônus, não um padrão preenchido em silêncio. O aviso automático da
    # ferramenta (`AVISO_SEM_BONUS`) não cobre este caso — ele exige `sem_bonus?`, que é renovação
    # marcada —, então quem avisa é este texto.
    'a cotação saiu sem bônus porque a apólice está em outro nome' => lambda {
      vazia = Autonomia::Insurance::AutoRenewal.new({})
      !vazia.renovacao? && vazia.bonus.nil? && !vazia.sem_bonus?
    },
    # SEGURADO TROCADO PELO TITULAR DO DOCUMENTO (#415). Em 12/09/2026, execução 20 da conversa 5045:
    # o cliente pediu "usa a apólice que te mandei, do William" e a cotação saiu no nome, no CPF, no
    # nascimento e no telefone do William, marcada como renovação, com a classe de bônus 9 e um
    # sinistro dele. A §4 dava precedência absoluta ao pedido do cliente e só excepcionava cobertura:
    # "usa a apólice do fulano" era lido como ORDEM, não como documento de terceiro, e a §6.2 nunca
    # disparava. Medido no caso de produção (`~/ops/agente-cotacao/teste-especialista/
    # caso-producao-5045/`): sem o parágrafo, 13 defeitos em 16 no bilhete que só repassa as palavras
    # do cliente; com ele, 0.
    #
    # A FRONTEIRA É REFERÊNCIA × INDICAÇÃO (P1 do Codex, 12/09). A primeira escrita desta regra dizia
    # que o segurado é SEMPRE a pessoa da conversa — e isso quebra caso legítimo e previsto no
    # próprio manual: cotar para a esposa com o CPF dela, cotar para empresa (§3), o "CPF do titular
    # ou CNPJ" da §4. O que o documento não pode é DECIDIR sozinho; quem o cliente indica de forma
    # explícita continua valendo.
    #
    # QUEM É O SEGURADO É O QUE O ESPECIALISTA ESCREVE, e chega assim ao portal: o `cpf` e o `nome`
    # que ele manda viram `insured.document` e `insured.name` na entrada, e o grupo `insured` viaja.
    # Se o grupo saísse da entrada, ou se o CPF deixasse de decidir quem é o segurado, a regra
    # perderia objeto. As SEIS coisas pessoais que ela proíbe copiar do documento são conferidas uma
    # a uma — proibir o que não existe no formulário seria texto sem alvo — e são as mesmas que o
    # contador da medição confere (`caso-producao-5045/medir.py`, `CAMPOS_PESSOAIS`). O ENDEREÇO são
    # três campos, não um: o CEP, o número e o complemento. Conferir só o CEP deixava o endereço do
    # titular entrar pelo número, e o `numero` solto ainda funde em `address.number` na entrada.
    'E para QUEM CONTRATA a ordem é outra: quem decide é o cliente, nunca o documento.' => lambda {
      entrada = entrada_de_auto('cpf' => '042.979.126-78', 'nome' => 'Rodrigo Silva',
                                'numero' => '294')

      grupos_da_entrada.include?('insured') &&
        entrada.dig('insured', 'document') == '04297912678' &&
        entrada.dig('insured', 'name') == 'Rodrigo Silva' &&
        entrada.dig('address', 'number') == '294' &&
        %w[insured.name insured.document insured.birthDate insured.maritalStatus insured.phone
           address.zipCode address.number address.complement].all? { |n| campo(n) }
    },
    # O CAMINHO LEGÍTIMO É EXPRESSÁVEL — e é isso que impede a regra de virar recusa. Cotar no nome
    # de quem o cliente indicou, com o bônus DELA e a apólice DELA, tem de caber no MESMO pedido: o
    # CPF que o especialista escreve é o único que decide o segurado, e o bloco de renovação viaja
    # junto e intacto. `QuoteInput` recebe produto, params, dados e comissão — nada da conversa, nada
    # do contato —, então não há por onde o interlocutor sobrescrever o segurado. Se essa assinatura
    # ganhasse o contato, ou se a renovação deixasse de acompanhar um segurado diferente de quem
    # digita, o texto estaria mandando recusar o caso legítimo.
    'Compare o titular da apólice com o SEGURADO DESTA COTAÇÃO' => lambda {
      renovacao = { 'isRenewal' => true, 'bonusClass' => 9, 'previousInsurerCode' => '4',
                    'previousPolicyNumber' => '01.142.431.056070' }
      entrada = entrada_de_auto('cpf' => '318.472.905-11', 'nome' => 'Ana Paula Ribeiro',
                                'quotation' => renovacao)

      Autonomia::Insurance::QuoteInput.instance_method(:initialize).parameters.map(&:last) ==
        %i[produto params dados commission_percent] &&
        entrada.dig('insured', 'document') == '31847290511' &&
        entrada.dig('insured', 'name') == 'Ana Paula Ribeiro' &&
        entrada['quotation'] == renovacao &&
        Autonomia::Insurance::AutoRenewal.new('quotation' => renovacao).bonus == 9
    },
    # POR QUE ELE ESTÁ NA LISTA DAS QUE PASSAM, e não na das que voltam vazias: nada neste
    # repositório confere de quem é o CPF. A entrada leva o que o modelo escreveu, seja de quem for,
    # e o `quotation` do titular — bônus e sinistros — viaja no mesmo pedido. A recusa, quando vem, é
    # na emissão, longe daqui. É a mesma capacidade que sustenta o caso legítimo acima: o código não
    # distingue os dois, e por isso quem distingue é o texto.
    'Segurado trocado pelo titular do documento.' => lambda {
      entrada = entrada_de_auto('cpf' => '296.562.576-34',
                                'quotation' => { 'isRenewal' => true, 'bonusClass' => 9 })

      grupos_da_entrada.include?('quotation') &&
        entrada.dig('insured', 'document') == '29656257634' &&
        entrada.dig('quotation', 'bonusClass') == 9
    },
    # O CAMINHO CERTO EXISTE E É LEGAL. Alguém tem de ser escrito no segurado — `insured.document` é
    # obrigatório no formulário, e o erro é o DOCUMENTO escolher quem —, mas levar o bônus e o
    # histórico do titular não é obrigatório: os dois campos são opcionais. Se virassem exigência,
    # este item proibiria a única saída que sobrou para a apólice de terceiro.
    'Deixa o documento escolher o segurado — cota em nome de quem o cliente não indicou.' => lambda {
      campo('insured.document')['obrigatorio'] == true && expostos.include?('insured.name') &&
        %w[quotation.bonusClass quotation.previousClaimsCount].all? { |n| campo(n)['obrigatorio'] == false }
    },
    # COBERTURA COPIADA DA APÓLICE (#410). Em 12/09/2026 o documento trouxe o quadro de coberturas e
    # o pedido saiu com ele: dezessete seguradoras acionadas, nenhum preço; minutos depois, com as
    # coberturas padrão, nove preços. A regra nova tem duas metades, e cada uma é uma capacidade.
    # NÃO MANDAR precisa ser legal: todo campo de cobertura exposto — e o percentual da tabela de
    # referência, que é escolha de cobertura morando no grupo do veículo — é opcional. Se um deles
    # virar obrigatório, "a cotação sai com as coberturas padrão" deixa de ser verdade.
    #
    # O QUE ESTA ÂNCORA PROVA, E O QUE NÃO PROVA (P2 do Codex na #411). Ela lê o RETRATO local do
    # formulário (`Connector::Mock::SCHEMA_AUTO`, o arquivo `mock/schema_auto.json`), não o contrato
    # que roda: em produção o formulário vem de `Connection#quote_schema`, o schema que o adapter
    # devolveu na sincronização da conexão. Torne uma cobertura obrigatória lá e deixe o retrato como
    # está — esta âncora continua verde. Ela prova que NO RETRATO as coberturas são opcionais, e que
    # ninguém as torna obrigatórias aqui dentro sem passar por esta tabela; ela NÃO detecta o dia em
    # que o contrato real exigir cobertura, que é justamente quando a promessa do manual viraria
    # mentira. Nada neste repositório compara os dois — o `http_contrato_real_spec` guarda só a
    # tradução camelCase da fronteira, com resposta simulada, e não lê schema nenhum.
    #
    # O contrato vive no outro repositório e o CI deste não o tem. O que dá para reproduzir sem tocar
    # no portal (`quoteSchema` do adapter é estático: sem sessão, sem rede, sem custo) é comparar os
    # dois à mão, e foi feito em 12/09/2026:
    #   (em autonomia-adapters, main) npx tsx src/cli/main.ts agger quote schema auto
    # Os 17 campos que a lambda confere — 16 `coverage.*` e o `vehicle.referencedValuePercent` —
    # saem de lá com `obrigatorio: false`, iguais ao retrato. A lacuna (ninguém refaz essa comparação
    # sozinho, e o retrato já está velho em dois campos de outro grupo) está registrada na #412.
    'Documento não é pedido' => lambda {
      cobertura = expostos.grep(/\Acoverage\./) + ['vehicle.referencedValuePercent']

      cobertura.size > 1 && cobertura.all? { |nome| campo(nome)['obrigatorio'] == false }
    },
    # MEXER DEPOIS precisa existir: o grupo `coverage` chega ao envio. Fora da entrada, o pedido de
    # cobertura que o cliente já fez não teria por onde viajar na primeira cotação — e o ajuste que
    # ele pedir depois do primeiro preço seria adiado para nunca.
    'O que o cliente já pediu entra na primeira cotação' => -> { grupos_da_entrada.include?('coverage') },
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

# AS PROMESSAS QUE A ENTREGA DAS FRASES ESCREVEU (12/09/2026), em módulo próprio pelo mesmo motivo
# que o formulário mora separado: a tabela acima só cresce, e cada entrega que a engordasse no mesmo
# módulo passaria do teto de linhas por um motivo que não é o dela.
module PromessasDasFrasesDoEspecialista
  FRASES = Autonomia::Agents::Tools::Native::InsuranceQuote::Frases
  PENEIRA = Autonomia::Agents::Tools::TextoAoCliente

  PROMESSAS = {
    # O manual só pode pedir que o especialista escreva as frases do cliente porque a ferramenta tem
    # ONDE recebê-las: o nó de quatorze folhas no formulário. Tire o nó dos parâmetros e a §2.1 vira
    # ordem impossível — ele escreveria num campo inexistente e o cliente leria o texto fixo de
    # sempre, sem ninguém reclamar.
    'Quem escreve essas frases é você' => lambda {
      Autonomia::Agents::Tools::Native::InsuranceQuote.params.any? { |p| p['name'] == FRASES::NO } &&
        FRASES::ORDEM.size == 14
    },
    # A OUTRA METADE: o manual afirma que a frase proibida é trocada por um texto padrão, e não que
    # ela some. Só é verdade porque TODA constante de recuo passa pela própria peneira — uma que não
    # passasse publicaria o que o texto acabou de proibir.
    'sai um texto padrão no lugar' => lambda {
      FRASES.constantes.size == FRASES::ORDEM.size &&
        FRASES.constantes.values.all? { |texto| PENEIRA.vetar(texto) == texto }
    },
    # A REGRA DE VOZ DO TRAVESSÃO TEM GUARDA NOS DOIS LADOS: a peneira reprova a frase do modelo que
    # o traga, e a depuração o troca no texto já composto (o nome da seguradora vem do portal).
    'Não use travessão em nada que chegue ao cliente' => lambda {
      PENEIRA.vetar('Segue o comparativo — com tudo').nil? &&
        PENEIRA.depurar('Porto — Cia', teto: 100) == 'Porto - Cia'
    },
    # E O ITEM DA LISTA SEGUE A MESMA REGRA: era o travessão que separava o nome do valor.
    'use dois pontos, vírgula ou ponto final' => lambda {
      item = Autonomia::Insurance::QuoteOffers.item(
        'insurer' => { 'name' => 'Ezze' }, 'premium' => { 'amount' => 2050.4, 'basis' => 'total' }
      )
      item.include?('*Ezze*: R$') && item.exclude?('—')
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
    ManualDoEspecialistaDeAuto::PROMESSAS
      .merge(PromessasDasFrasesDoEspecialista::PROMESSAS).each do |frase, sustenta|
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
    expect(Digest::MD5.hexdigest(ManualDoEspecialistaDeAuto::ARQUIVO.binread)).to eq('2e05afb8cbbc67671a48ed1325e54a3e')
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
