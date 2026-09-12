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

  # O BLOCO DA §7.1, ISOLADO — da linha do título até o próximo capítulo numerado.
  #
  # A GUARDA POR FRASE-ÂNCORA É CEGA À REGRA INVERTIDA. Mutação de 12/09/2026: mantive as quatro
  # âncoras da tabela `PROMESSAS` e acrescentei ao texto "Na dúvida, acione o especialista de novo e
  # mande cotar outra vez" — o oposto do que a entrega escreveu. Passaram 35 de 35. Frase que EXISTE
  # se verifica; texto novo entre elas, não. Por isso a §7.1 é assinada por md5.
  #
  # Assinar o ARQUIVO inteiro (molde da entrega 3, `builder_instrucao_do_especialista_spec`) não
  # serve nesta janela: a entrega 8 edita §5 e §10 do mesmo arquivo, e a assinatura reprovaria por
  # mudança sem relação nenhuma com esta entrega. O que esta entrega escreveu é a §7.1.
  SECAO_DUVIDA = /### 7\.1.*?(?=\n## \d)/m

  # O BLOCO DOS ESPECIALISTAS DA §5, ISOLADO — do subtítulo até o próximo capítulo numerado. É onde a
  # #403 escreveu a regra de titularidade, e vale para ele o mesmo motivo da §7.1: a frase-âncora não
  # vê o que for acrescentado ao lado dela. "Na dúvida, recuse o documento você mesma" passaria por
  # todas as âncoras desta tabela — é exatamente a conduta que a #403 existe para tirar do texto.
  # Assinar o ARQUIVO inteiro continua não servindo: a entrega 8 volta a editar §5 e §10, e uma
  # assinatura de arquivo reprovaria por mudança sem relação com esta. Quem editar este bloco
  # reassina aqui e revisa `PROMESSAS_DO_DOCUMENTO` junto.
  SECAO_ESPECIALISTAS = /### Os especialistas de ramo.*?(?=\n## \d)/m

  # O manual do especialista de auto — o mesmo arquivo que o `Builder` entrega ao especialista do
  # ramo no deploy (`ESPECIALISTAS`), não uma cópia.
  ESPECIALISTA_DE_AUTO = Autonomia::Insurance::QuoteAgent::Builder::ESPECIALISTAS
                         .find { |e| e[:slug] == 'cotacao_auto' }.freeze

  module_function

  def principal
    Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_PRINCIPAL
  end

  def secao_duvida(texto)
    texto[SECAO_DUVIDA]
  end

  def secao_especialistas(texto)
    texto[SECAO_ESPECIALISTAS]
  end

  def manual_do_especialista_de_auto
    Autonomia::Insurance::QuoteAgent::Builder::INSTRUCOES.join(ESPECIALISTA_DE_AUTO[:arquivo]).read
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
    # O QUE ESTA LINHA GARANTE, E O QUE NÃO GARANTE. Executar SOMENTE a consulta às condições gerais
    # preserva a cotação em andamento: a consulta é SÍNCRONA, só ferramenta assíncrona abre execução
    # (`Bound#accept_async`), e é a abertura que supersedia a execução viva da conversa
    # (`ToolRun.open!`). Isso é invariante de código, e é o que este lambda prova.
    # NÃO é invariante que o modelo vá chamar só a consulta: se ele chamar também o especialista, a
    # cotação PODE ser reaberta (só se houver nova chamada assíncrona aceita — pedido igual é recusado
    # como repetido) e a frase da instrução vira mentira. Escolher só a consulta é CONDUTA, e se
    # prova na conversa real (§7 da auditoria), não aqui.
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

  # CADA PROMESSA DA REGRA DE TITULARIDADE DA §5 (#403), PELA FRASE EXATA, E O QUE A SUSTENTA.
  #
  # O FATO QUE ORIGINOU A ENTREGA: em 11/09/2026, numa conversa real, a Lia recebeu uma apólice em
  # nome e CPF de outra pessoa, tratou a divergência como o "dados incoerentes" da §3 e recusou ali
  # mesmo. A §6.2 do manual do especialista — que manda aproveitar placa, CEP, modelo e ano e cotar
  # como seguro novo — só age depois que o pedido chega ao especialista, e nunca chegou. O buraco
  # era do principal: nenhuma linha dizia que titularidade é matéria do ramo.
  PROMESSAS_DO_DOCUMENTO = {
    # A LIA NÃO TEM COMO DECIDIR, mesmo que quisesse: a ferramenta de cotação é do especialista, e o
    # `Answerer#enabled_agent_tools` a esconde do principal. Repassar não é cortesia — é o único
    # caminho que o código deixa aberto, e o que a frase faz é impedir que ele termine numa recusa.
    'Documento que a pessoa mandar vai para o especialista, mesmo que o nome nele não seja o dela.' => lambda {
      Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_PRINCIPAL.exclude?('cotar_seguro') &&
        Autonomia::Insurance::QuoteAgent::Builder::TOOLS_DO_ESPECIALISTA.include?('cotar_seguro') &&
        ESPECIALISTA_DE_AUTO.present?
    },
    # QUEM DECIDE É O ESPECIALISTA porque a decisão está escrita no manual DELE — a §6.2, no arquivo
    # que o deploy entrega ao especialista de auto. Se essa regra sair de lá, a frase do principal
    # vira um encaminhamento para lugar nenhum, e este exemplo reprova junto.
    'aproveita de um documento em nome de outra pessoa é o especialista, não você.' => lambda {
      manual = manual_do_especialista_de_auto
      manual.include?('Se a apólice que ele mandou estiver em nome e CPF de outra pessoa') &&
        manual.include?('cote como seguro novo')
    },
    # DIZER QUE O DOCUMENTO ESTÁ EM OUTRO NOME cabe no pedido: a função do especialista tem um
    # parâmetro só, de texto livre em português, e ele é obrigatório. Não há campo estruturado a
    # preencher nem capacidade nova sendo prometida aqui.
    'diga que o documento está em outro nome.' => lambda {
      Autonomia::Agents::Specialist::REQUEST_PARAM == 'pedido' &&
        Autonomia::Agents::Specialist.new(slug: 'cotacao_auto', description: 'x')
                                     .openai_schema[:parameters][:required] == ['pedido']
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

  describe 'promessa e capacidade da §5 (documento em nome de outra pessoa, #403)' do
    let(:secao) { ManualDoPrincipal.secao_especialistas(texto) }

    ManualDoPrincipal::PROMESSAS_DO_DOCUMENTO.each do |frase, sustenta|
      it "«#{frase.tr("\n", ' ')}» tem o que a sustenta" do
        expect(ManualDoPrincipal.secao_especialistas(texto)).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end

    # A REGRA VIVE NO BLOCO DOS ESPECIALISTAS, não solta no arquivo. Fora dali ela não é lida junto
    # do "você não cota", que é o que lhe dá sentido — e a assinatura abaixo deixaria de cobri-la.
    it 'a regra está dentro do bloco dos especialistas de ramo' do
      expect(secao).to be_present
      expect(secao).to include('Documento que a pessoa mandar vai para o especialista')
    end

    # O NEGATIVO: a divergência de nome é tratada como matéria do ramo, não como o "dados
    # incoerentes" da §3 — foi essa leitura que fez a Lia recusar em 11/09.
    it 'diz que nome ou CPF diferentes não são dado incoerente' do
      expect(secao).to be_present
      expect(secao).to include('não são dado incoerente')
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

    # O NEGATIVO DO TERMO 3 — "habilitada nos agentes que já existem" NÃO é consequência do código.
    # `Registry.for_agent` filtra pelo que está LIGADO no agente (`agent.native_tool_slugs`), gravado
    # no nascimento: um agente criado antes de a ferramenta existir, com a lista sem o slug, não a
    # recebe — com módulo ligado, conexão pronta e `available_for?` verdadeiro do mesmo jeito. O
    # `Builder` só escreve a lista em `criar_agente`. Quem já existe depende de rollout, e é por isso
    # que o termo 3 se prova no agente 24 em produção (auditoria da entrega 2, linha 144) — aqui se
    # prova apenas que a lista é o que manda.
    it 'agente já criado sem o slug em native_tool_slugs não recebe a ferramenta' do
      agente = construir
      sem_a_cg = agente.native_tool_slugs - ['consultar_condicoes_gerais']
      agente.update!(config: agente.config.merge('native_tool_slugs' => sem_a_cg))

      expect(condicoes_gerais.available_for?(agente)).to be(true)
      expect(Autonomia::Agents::Tools::Bound.for_agent(agente).map(&:slug))
        .not_to include('consultar_condicoes_gerais')
    end
  end

  # PROSA NÃO SE VERIFICA POR MÁQUINA — e a tabela `PROMESSAS` só vê o que ESTÁ escrito, nunca o que
  # foi acrescentado entre uma âncora e outra. O md5 da §7.1 é a assinatura da revisão: mudou uma
  # letra da seção, estes exemplos reprovam, e quem os atualiza revisa `PROMESSAS` junto.
  describe 'a §7.1 é o texto revisado' do
    let(:secao) { ManualDoPrincipal.secao_duvida(texto) }

    # A EXTRAÇÃO PODE FALHAR EM SILÊNCIO. A versão anterior deste arquivo fazia
    # `texto[/### 7\.1.*?\n## 8/m].to_s` — com a seção ausente, ou com o capítulo seguinte
    # renumerado, o resultado virava "" e o exemplo passava sem ter lido nada. A presença é afirmada
    # primeiro, e em cada exemplo que depende dela.
    it 'está no arquivo e é extraída inteira' do
      expect(secao).to be_present
      expect(secao).to start_with('### 7.1 ')
      expect(secao).to end_with("A consulta é por seguradora, e sem esse nome não existe resposta.\n")
    end

    it 'mudou? revise PROMESSAS e assine aqui' do
      expect(secao).to be_present
      expect(Digest::MD5.hexdigest(secao)).to eq('197f319bce3a110da98823bb7d359dbf')
    end

    # O ARQUIVO É LIDO COM AS ESCOLHAS SUBSTITUÍDAS (#380): a §7.1 não pode trazer marcador novo.
    it 'não introduz variável para substituir' do
      expect(secao).to be_present
      expect(secao.scan(/\$[a-zA-Z]+/)).to be_empty
    end
  end

  # MESMA ASSINATURA, MESMO MOTIVO, PARA O BLOCO DOS ESPECIALISTAS DA §5 (#403). A tabela
  # `PROMESSAS_DO_DOCUMENTO` vê as três frases que escrevi; não veria uma quarta, escrita ao lado
  # delas, mandando recusar o documento — que é a conduta que esta entrega tira do caminho. Quem
  # editar este bloco reassina aqui e revisa a tabela junto. A entrega 8 volta a mexer na §5: é
  # esperado que ela reprove estes exemplos e os reassine.
  describe 'o bloco dos especialistas da §5 é o texto revisado' do
    let(:secao) { ManualDoPrincipal.secao_especialistas(texto) }

    it 'está no arquivo e é extraído inteiro' do
      expect(secao).to be_present
      expect(secao).to start_with('### Os especialistas de ramo')
      expect(secao).to end_with("a corretora não atende esse seguro e ofereça o que ela atende.\n")
    end

    it 'mudou? revise PROMESSAS_DO_DOCUMENTO e assine aqui' do
      expect(secao).to be_present
      expect(Digest::MD5.hexdigest(secao)).to eq('6cc2e90da520f0b14720f943307134cf')
    end

    it 'não introduz variável para substituir' do
      expect(secao).to be_present
      expect(secao.scan(/\$[a-zA-Z]+/)).to be_empty
    end
  end
end
