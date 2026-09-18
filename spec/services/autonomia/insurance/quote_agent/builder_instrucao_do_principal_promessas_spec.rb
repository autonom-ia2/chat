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
  # Assinar o ARQUIVO inteiro continua não servindo, e a entrega 8 é a demonstração: aplicado o
  # `origin/pr-399` de hoje (`ade5ca58db`) sobre esta árvore, o arquivo muda em §2, §5, §6 e §10 — e o
  # md5 DESTE bloco não muda. Uma assinatura de arquivo reprovaria; a do bloco não. Quem editar
  # este bloco reassina abaixo e revisa `PROMESSAS_DO_DOCUMENTO` junto.
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

  # O ANEXO DE UM TURNO ANTERIOR CHEGA DE NOVO AO ESPECIALISTA — EXERCITADO, não inspecionado.
  #
  # POR QUE ASSIM (P2 do Codex na #416). A primeira versão desta âncora lia
  # `Materia.private_instance_methods.include?(:anteriores)`: o método existir. Esvaziar o corpo
  # (`def anteriores(_) = []`) deixava a âncora VERDE e a promessa morta. Aqui a matéria é montada
  # de verdade — conversa, um PDF numa mensagem ANTERIOR à que abriu o turno, nenhum documento
  # neste turno — e o que se afirma é o RESULTADO: o documento anterior volta, com o texto dentro.
  # Esvaziar `anteriores`, tirar a releitura, virar a ordem da janela ou fechar o portão de mídia
  # derruba este exemplo.
  HISTORICO_DO_TURNO = [{ role: 'user', content: 'Segue a apólice.' },
                        { role: 'user', content: 'usa a apólice do fulano' }].freeze

  def materia_de_turno_sem_anexo
    account = FactoryBot.create(:account)
    inbox = FactoryBot.create(:inbox, account: account)
    conversation = FactoryBot.create(:conversation, account: account, inbox: inbox, assignee: nil)
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom',
                                             status: :active, enabled: true, instruction: 'Atenda.')
    anexar_apolice(conversation, inbox, account)
    abriu = FactoryBot.create(:message, conversation: conversation, account: account, inbox: inbox,
                                        message_type: :incoming, content: 'usa a apólice do fulano')
    turno = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil,
                                                   origin_message_id: abriu.id)
    Autonomia::Agents::Specialists::Materia.new(delivery: turno, history: HISTORICO_DO_TURNO,
                                                documents: [], agent: agent)
  end

  def textos_da_materia(materia)
    materia.mensagens.flat_map { |m| m[:content].map { |c| c[:text] } }
  end

  def anexar_apolice(conversation, inbox, account)
    mensagem = FactoryBot.create(:message, conversation: conversation, account: account, inbox: inbox,
                                           message_type: :incoming, content: 'segue a apólice')
    anexo = mensagem.attachments.new(account_id: account.id, file_type: :file)
    anexo.file.attach(io: File.open(Rails.root.join('spec/assets/sample.pdf')),
                      filename: 'apolice.pdf', content_type: 'application/pdf')
    anexo.save!
    anexo
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
    #
    # E A DECISÃO DELE É UMA COMPARAÇÃO, não um reflexo (#415, P1 do Codex): o titular do documento
    # contra o SEGURADO INDICADO, que nem sempre é quem está conversando. Sem essa linha lá, o
    # "quem decide é o especialista" daqui mandaria o caso para uma regra que recusa o legítimo.
    'aproveita de um documento em nome de outra pessoa é o especialista, não você.' => lambda {
      manual = manual_do_especialista_de_auto
      manual.include?('Se a apólice que ele mandou estiver em nome e CPF de outra pessoa') &&
        manual.include?('Compare o titular da apólice com o SEGURADO DESTA COTAÇÃO') &&
        manual.include?('cote como seguro novo')
    },
    # DIZER QUE O DOCUMENTO ESTÁ EM OUTRO NOME cabe no pedido: a função do especialista tem um
    # parâmetro só, de texto livre em português, e ele é obrigatório. Não há campo estruturado a
    # preencher nem capacidade nova sendo prometida aqui.
    'diga que o documento está em outro nome.' => lambda {
      Autonomia::Agents::Specialist::REQUEST_PARAM == 'pedido' &&
        Autonomia::Agents::Specialist.new(slug: 'cotacao_auto', description: 'x')
                                     .openai_schema[:parameters][:required] == ['pedido']
    },
    # E EM TODO PEDIDO QUE VOCÊ SOUBER, NÃO SÓ NO TURNO DO ANEXO (#415). Em 12/09/2026, execução 20
    # da conversa 5045, nenhum documento foi enviado no turno: a apólice de terceiro chegara duas
    # horas antes, e a Lia só repassou "usa a apólice do William". O especialista leu aquilo como
    # ordem e cotou no nome do titular. A regra acima agia no turno em que o documento chega; esta
    # diz que ela vale sempre que o pedido se apoiar nele.
    #
    # O TEXTO PEDE SÓ O QUE O PRINCIPAL TEM (P2 do Codex na #416). A primeira escrita mandava repetir
    # a divergência em TODO pedido apoiado no documento, e afirmava que o especialista "só sabe pelo
    # bilhete". As duas coisas estavam erradas: o principal recebe os anexos do turno atual e uma
    # janela de histórico — se a titularidade só existia dentro do PDF de um turno antigo, ou saiu da
    # janela, ele não tem como saber —, e o especialista recebe a conversa e os documentos junto do
    # pedido (`Materia#mensagens`). O que ele NÃO recebe é a leitura que a Lia fez deles.
    #
    # O QUE SUSTENTA, EXERCITADO: o anexo de um turno anterior chega de novo ao especialista, com o
    # texto extraído. Sem isso, mandar repetir a divergência apontaria para um documento ausente. E
    # a conversa viaja junto, que é o que torna falsa a frase antiga.
    'E repita isso sempre que você souber, não só no turno em que o documento chegou.' => lambda {
      materia = materia_de_turno_sem_anexo
      docs = materia.documentos
      textos = textos_da_materia(materia)

      docs.map { |d| d[:name] } == ['apolice.pdf'] && docs.first[:text].present? &&
        textos.any? { |t| t.include?('usa a apólice do fulano') } &&
        textos.any? { |t| t.include?('<documento nome="apolice.pdf">') }
    }
  }.freeze
end

# O BLOCO DA FERRAMENTA DE RESULTADO DA §5 (fatia 2 do #420): o bloco, a conversa que exercita as promessas e
# a tabela de promessas. Módulo próprio, ao lado de `ManualDoPrincipal`, para não passar do teto de linhas.
module ManualDoPrincipalResultado
  # Do título até o subtítulo seguinte. Assinado pelo mesmo motivo dos outros dois blocos: a frase-âncora
  # não vê o que for escrito ao lado dela.
  SECAO = /### `ver_resultado_da_cotacao`.*?(?=\n### )/m
  RESULTADO = Autonomia::Agents::Tools::Native::InsuranceQuoteResult
  COTACAO = Autonomia::Agents::Tools::Native::InsuranceQuote
  BUILDER = Autonomia::Insurance::QuoteAgent::Builder
  MOTIVO = Autonomia::Insurance::MotivoDaRecusa
  MOTIVO_DO_VEICULO = 'Tipo de veículo não aceito.'.freeze

  module_function

  def secao(texto)
    texto[SECAO]
  end

  # UMA CONVERSA COM UMA COTAÇÃO ENCERRADA: Porto cotou, Sancor recusou pelo tipo do veículo. A conta NÃO tem
  # conexão com o portal, de propósito: a ferramenta de resultado responde sem ela.
  def conversa_com_cotacao
    account = FactoryBot.create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true })
    inbox = FactoryBot.create(:inbox, account: account)
    conversation = FactoryBot.create(:conversation, account: account, inbox: inbox)
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom',
                                             status: :active, enabled: true, instruction: 'Atenda.')
    ofertas = [{ 'insurer' => { 'code' => '8', 'name' => 'Porto Seguro' }, 'status' => 'quoted',
                 'premium' => { 'amount' => 2119.18, 'basis' => 'total' } },
               { 'insurer' => { 'code' => '19', 'name' => 'Sancor' }, 'status' => 'declined',
                 'reason' => { 'kind' => 'risco', 'text' => MOTIVO_DO_VEICULO } }]
    guardado = Autonomia::Insurance::ResultadoPorSeguradora.unir({}, ofertas)
    Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: COTACAO.slug, status: 'done',
                                       conversation_id: conversation.id, execution_key: SecureRandom.uuid, arguments: {},
                                       handle: { 'quote_id' => 'q-1:1', COTACAO::RESULTADO_KEY => guardado })
    [agent, conversation]
  end

  def no_turno(seguradora, conversa = conversa_com_cotacao)
    agent, conversation = conversa
    delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 1)
    RESULTADO.new(agent: agent, params: { 'seguradora' => seguradora }, delivery: delivery)
  end

  # O que o modelo lê, e o que ficou registrado no turno para a conferência da fala.
  def consultar(seguradora, conversa = conversa_com_cotacao)
    ferramenta = no_turno(seguradora, conversa)
    [ferramenta.call, ferramenta.send(:delivery).resultado_do_turno]
  end

  # CADA PROMESSA DO BLOCO, PELA FRASE EXATA, E O QUE A SUSTENTA.
  PROMESSAS = {
    # A ferramenta é do principal e responde sem o portal: a conta desta conversa não tem conexão nenhuma.
    'O que a cotação desta conversa já recebeu das seguradoras, sem cotar de novo.' => lambda {
      BUILDER::TOOLS_DO_PRINCIPAL.include?(RESULTADO.slug) && BUILDER::TOOLS_DO_ESPECIALISTA.exclude?(RESULTADO.slug) &&
        consultar('Sancor').first.include?('Sancor não fez proposta')
    },
    # Um parâmetro só, e a procura acha mais de uma seguradora no mesmo texto.
    'escreva todos os nomes no mesmo campo, numa chamada só.' => lambda {
      ao_modelo, = consultar('Sancor e Porto')
      RESULTADO.openai_schema[:parameters][:required] == ['seguradora'] &&
        ao_modelo.include?('Porto Seguro fez proposta') && ao_modelo.include?('Sancor não fez proposta')
    },
    # Pedir os preços não abre execução: a ferramenta é síncrona e do principal, e nenhuma cotação nova é aberta.
    'Pedir os preços não é pedir outra cotação' => lambda {
      consultar(nil)
      !RESULTADO.async? && BUILDER::TOOLS_DO_PRINCIPAL.include?(RESULTADO.slug) &&
        Autonomia::Agents::ToolRun.where(slug: [RESULTADO.slug]).none?
    },
    # A ferramenta devolve ao modelo o valor com o período, e o registra no turno para a conferência (fatia 3).
    'Quem escreve os preços é você, com os dados que a ferramenta devolve.' => lambda {
      ao_modelo, turno = consultar(nil)
      ao_modelo.include?('Porto Seguro fez proposta: R$ 2.119,18 no total') && turno.texto == ao_modelo &&
        turno.seguradoras.include?('Porto Seguro')
    },
    'Escreva só o recorte que a pessoa pediu.' => -> { RESULTADO::COMO_ESCREVER.include?('com o recorte que ele pediu') },
    # O período vem do adapter e vai junto do valor na linha de cada seguradora (`PremiumText#resumo`).
    'O período vai sempre junto do valor' => -> { consultar(nil).first.include?('R$ 2.119,18 no total') },
    # A lista que a ferramenta devolve já separa os períodos (`QuoteOffers#quoted`), e o texto ao modelo repete a regra.
    'Nunca ordene um valor por mês contra um valor total pelo número cru' => -> { RESULTADO::COMO_ESCREVER.include?('Não ordene') },
    # A conferência existe e não deixa valor que não está nos dados passar.
    'O sistema confere a sua resposta' => lambda {
      _, turno = consultar(nil)
      Autonomia::Agents::Answerer.private_instance_methods.include?(:conferir_precos) &&
        Autonomia::Agents::ConferenciaDePrecos.new(turno).publicavel('Porto Seguro: R$ 1.999,00.') { nil } ==
          Autonomia::Agents::ConferenciaDePrecos::RECUO_SEM_COMPARATIVO
    },
    # Nada fica guardado entre consultas: a segunda lê o que a cotação tem agora, e nenhuma execução é aberta.
    'Cada consulta mostra o que a cotação tem naquele momento.' => lambda {
      conversa = conversa_com_cotacao
      cotacao = Autonomia::Agents::ToolRun.find_by!(slug: COTACAO.slug, conversation_id: conversa.last.id)
      antes = consultar('Allianz', conversa).first
      allianz = { 'insurer' => { 'code' => '5', 'name' => 'Allianz' }, 'status' => 'quoted',
                  'premium' => { 'amount' => 2402.55, 'basis' => 'total' } }
      guardado = Autonomia::Insurance::ResultadoPorSeguradora.unir(cotacao.handle[COTACAO::RESULTADO_KEY], [allianz])
      cotacao.update!(handle: cotacao.handle.merge(COTACAO::RESULTADO_KEY => guardado))
      depois = consultar('Allianz', conversa).first
      antes == RESULTADO::NAO_ENCONTRADA && depois.include?('Allianz fez proposta: R$ 2.402,55 no total') &&
        Autonomia::Agents::ToolRun.where(slug: RESULTADO.slug).none?
    },
    # O motivo só chega ao modelo quando o pedido nomeia a seguradora: o resultado inteiro não o traz.
    'O motivo de quem não fez proposta só sai quando a pessoa perguntar por aquela seguradora' => lambda {
      motivo = RESULTADO::MOTIVOS.fetch(MOTIVO::VEICULO)
      consultar(nil).first.exclude?(motivo) && consultar('Sancor').first.include?(motivo)
    },
    # A ferramenta entrega uma de duas categorias, escritas pelo código.
    'que a ferramenta entregar: se a recusa foi pelo veículo ou pela região.' => lambda {
      MOTIVO::CATEGORIAS == [MOTIVO::VEICULO, MOTIVO::REGIAO] && RESULTADO::MOTIVOS.keys == MOTIVO::CATEGORIAS
    },
    # O texto do portal não chega ao modelo: não há detalhe a acrescentar além da categoria.
    'sem acrescentar detalhe que a ferramenta não deu.' => lambda {
      consultar('Sancor').first.exclude?(MOTIVO_DO_VEICULO) &&
        RESULTADO::MOTIVOS.values.all? { |texto| texto.include?('sem acrescentar detalhe') }
    },
    "Quando a ferramenta disser que não há motivo que\nvocê possa contar" => lambda {
      RESULTADO::SEM_MOTIVO.include?('Não há motivo que você possa contar') &&
        MOTIVO.categoria('kind' => 'passageiro', 'text' => MOTIVO_DO_VEICULO).nil?
    },
    # O molde fechado do motivo não tem palavra de conta nem da pessoa: com qualquer uma delas, o texto vai ao genérico.
    "Nunca fale de login, senha ou\npermissão da corretora, nem de restrição da pessoa." => lambda {
      moldes = MOTIVO::MOLDES.values.map { |molde| molde[:palavras] }
      %w[login senha permissao segurado condutor restricao].none? { |palavra| moldes.any? { |palavras| palavras.include?(palavra) } } &&
        ['faça login', 'senha vencida', 'sem permissão', 'segurado com restrição'].all? do |termo|
          MOTIVO.categoria('kind' => 'risco', 'text' => "Tipo de veículo não aceito, #{termo}.").nil?
        end
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

      expect(citadas).to include('consultar_condicoes_gerais', 'ver_resultado_da_cotacao')
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

    # O TERMO 3 PASSOU A SER CONSEQUÊNCIA DO CÓDIGO (fatia 2 do #420). Até aqui `Registry.for_agent`
    # filtrava pela lista gravada no nascimento (`native_tool_slugs`), e o agente criado antes de a
    # ferramenta existir só a recebia por escrita no banco de produção. Agora a lista do Agente de Cotação
    # é a do deploy (`Builder.ferramentas_mantidas`, lida por `Agent#ferramentas_nativas`): o agente com a
    # lista antiga gravada recebe a ferramenta, e a coluna não é tocada. Para os outros tipos de agente a
    # coluna continua mandando (`registry_spec`).
    it 'agente de cotação já criado sem o slug em native_tool_slugs recebe a ferramenta pela lista do deploy' do
      agente = construir
      sem_a_cg = agente.native_tool_slugs - ['consultar_condicoes_gerais']
      agente.update!(config: agente.config.merge('native_tool_slugs' => sem_a_cg))

      expect(condicoes_gerais.available_for?(agente)).to be(true)
      expect(Autonomia::Agents::Tools::Bound.for_agent(agente.reload).map(&:slug)).to include('consultar_condicoes_gerais')
      expect(agente.reload.native_tool_slugs).not_to include('consultar_condicoes_gerais')
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
      expect(Digest::MD5.hexdigest(secao)).to eq('b5bbc4c00099a879ea0877b5a09da28e')
    end

    # O ARQUIVO É LIDO COM AS ESCOLHAS SUBSTITUÍDAS (#380): a §7.1 não pode trazer marcador novo.
    it 'não introduz variável para substituir' do
      expect(secao).to be_present
      expect(secao.scan(/\$[a-zA-Z]+/)).to be_empty
    end
  end

  # MESMA ASSINATURA, MESMO MOTIVO, PARA O BLOCO DOS ESPECIALISTAS DA §5 (#403, agora com a #415). A
  # tabela `PROMESSAS_DO_DOCUMENTO` vê as quatro frases que estão escritas; não veria uma quinta, ao
  # lado delas, mandando recusar o documento — que é a conduta que a #403 tirou do caminho. Quem
  # editar este bloco reassina aqui e revisa a tabela junto. A assinatura mudou duas vezes em
  # 12/09/2026: com o parágrafo da #415 (`6cc2e90d…` -> `7c83a38a…`) e de novo com a correção do P2
  # do Codex (`7c83a38a…` -> `730b22a3…`), que trocou "em todo pedido" por "em todo pedido que você
  # souber" e tirou a afirmação falsa de que o especialista só sabe pelo bilhete. As duas mudanças
  # são o efeito esperado desta guarda.
  #
  # A ENTREGA 8 NÃO COLIDIA COM A ASSINATURA ANTERIOR, medido e não suposto: mesclado o
  # `origin/pr-399` de 12/09 (`ade5ca58db`) na árvore da #403, a #399 mexe na §5 ANTES deste bloco —
  # troca a linha "Você tem três/quatro ferramentas" e insere a subseção `proposta_da_seguradora`
  # logo acima do "### Os especialistas de ramo" — e o md5 do bloco não mudava. Se a #399 mudar de
  # forma e passar a editar o bloco, este exemplo reprova e é ele que avisa.
  describe 'o bloco dos especialistas da §5 é o texto revisado' do
    let(:secao) { ManualDoPrincipal.secao_especialistas(texto) }

    it 'está no arquivo e é extraído inteiro' do
      expect(secao).to be_present
      expect(secao).to start_with('### Os especialistas de ramo')
      expect(secao).to end_with("a corretora não atende esse seguro e ofereça o que ela atende.\n")
    end

    it 'mudou? revise PROMESSAS_DO_DOCUMENTO e assine aqui' do
      expect(secao).to be_present
      expect(Digest::MD5.hexdigest(secao)).to eq('730b22a3c58a716b8be34cccb5fd4aec')
    end

    it 'não introduz variável para substituir' do
      expect(secao).to be_present
      expect(secao.scan(/\$[a-zA-Z]+/)).to be_empty
    end
  end

  # O BLOCO DA FERRAMENTA DE RESULTADO (fatia 2 do #420): promessa por frase exata e assinatura por md5.
  # Nasceu ANTES do "### Os especialistas de ramo", e é por isso que a assinatura daquele bloco não mudou.
  describe 'promessa e capacidade da ferramenta de resultado da §5 (fatia 2 do #420)' do
    let(:secao) { ManualDoPrincipalResultado.secao(texto) }

    ManualDoPrincipalResultado::PROMESSAS.each do |frase, sustenta|
      it "«#{frase.tr("\n", ' ')}» tem o que a sustenta" do
        expect(ManualDoPrincipalResultado.secao(texto)).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end

    it 'está no arquivo, antes do bloco dos especialistas, e é extraído inteiro' do
      expect(secao).to be_present
      expect(secao).to start_with('### `ver_resultado_da_cotacao`')
      expect(secao).to end_with("permissão da corretora, nem de restrição da pessoa.\n")
      expect(texto.index(secao)).to be < texto.index('### Os especialistas de ramo')
    end

    it 'mudou? revise ManualDoPrincipalResultado::PROMESSAS e assine aqui' do
      expect(secao).to be_present
      expect(Digest::MD5.hexdigest(secao)).to eq('9d7fa68356107d16adee94eb60121c70')
    end

    it 'não escreve valor em reais nem introduz variável para substituir' do
      expect(secao).to be_present
      expect(secao).not_to include('R$')
      expect(secao.scan(/\$[a-zA-Z]+/)).to be_empty
    end

    it 'diz quantas ferramentas a Lia tem, contando a nova' do
      expect(texto).to include('Você tem quatro.')
    end
  end
end
