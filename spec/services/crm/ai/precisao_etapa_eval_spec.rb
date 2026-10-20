require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto de US$ 0,30 (#1926): a rodada para ao passar dele, somado pelo
# evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME). EVAL_REPETICOES repete cada caso (padrão 1).
#
# #1926, precisão da IA de etapa. Conversas inventadas, em três ramos, com o classificador real (o mesmo prefixo, a
# mesma janela de mensagens e o mesmo pacote da avaliação de um card; nada é aplicado ao card):
# - fechou sem dizer com quem: o fim é incerto. Nunca uma etapa do meio (Negociação) nem Ganho; Perdido ou manter.
# - "já resolvi" num card duplicado: idem.
# - preço enviado no meio de uma conversa longa (30 mensagens; o preço é a 6ª): Proposta enviada ou Negociação.
# - controles, para "não errar" não virar "não mover": perdeu para outro vai para Perdido com confiança de mover;
#   aceitou a nossa proposta vai para Ganho.
# As saídas (etapa, confiança, motivo, custo) vão para EVAL_SAIDA (JSON). Nenhum prompt é gravado.
module PrecisaoEtapaEval
  TETO_USD = 0.30

  ETAPAS = [
    ['Novo contato', 'O cliente chegou e ainda não foi atendido.'],
    ['Em atendimento', 'Estamos entendendo o que o cliente precisa e coletando os dados para montar a proposta.'],
    ['Proposta enviada', 'Nossa equipe já enviou ao cliente uma proposta com preço.'],
    # Como muitos funis escrevem: a etapa do meio fica "perto de fechar", o que atrai a fala ambígua de fechamento.
    ['Negociação', 'O cliente recebeu a proposta e está avaliando ou negociando para fechar.'],
    ['Ganho', 'O cliente aceitou a nossa proposta e fechou conosco: aceite, pagamento ou contrato.'],
    ['Perdido', 'O cliente desistiu, fechou com outro fornecedor ou não precisa mais.']
  ].freeze

  RAMOS = {
    seguros: {
      funil: 'Seguro auto',
      titulo: 'Seguro do Corolla',
      pedido: 'Oi, quero cotar seguro para o meu carro, um Corolla 2021.',
      pergunta: 'Olá! Me passa o CEP onde o carro dorme e se tem garagem?',
      dados: 'CEP 80000-000, tem garagem sim.',
      proposta: 'Segue a cotação: seguro completo do Corolla 2021 por R$ 3.480,00 à vista ou 10x de R$ 348,00, ' \
                'franquia de R$ 4.200,00.',
      perdeu: 'Fechei com outra corretora que fez mais barato, obrigado.',
      ganhou: 'Pode fechar com vocês, aceito a cotação. Me manda o boleto.',
      longa: [
        [:c, 'Oi, quero cotar seguro para o meu carro, um Corolla 2021.'],
        [:h, 'Olá! Claro. Me passa o CEP onde o carro dorme e se tem garagem?'],
        [:c, 'CEP 80000-000, tem garagem sim.'],
        [:h, 'Perfeito. Quem é o condutor principal e qual a idade?'],
        [:c, 'Sou eu, 42 anos.'],
        [:h, 'Segue a cotação: seguro completo do Corolla 2021 por R$ 3.480,00 à vista ou 10x de R$ 348,00, ' \
             'franquia de R$ 4.200,00.'],
        [:c, 'Deixa eu ver umas coisas.'],
        [:c, 'Essa cobertura inclui vidros?'],
        [:h, 'Inclui sim: vidros, faróis e retrovisores.'],
        [:c, 'E carro reserva?'],
        [:h, 'Carro reserva por 15 dias.'],
        [:c, 'Guincho é ilimitado?'],
        [:h, 'Guincho até 400 km.'],
        [:c, 'Se minha esposa dirigir de vez em quando, tem problema?'],
        [:h, 'Sem problema, ela pode dirigir eventualmente.'],
        [:c, 'E meu filho de 19 anos?'],
        [:h, 'Se ele dirigir com frequência, precisa constar no perfil. De vez em quando, não.'],
        [:c, 'Ele usa pouco, só fim de semana às vezes.'],
        [:h, 'Então não precisa incluir.'],
        [:c, 'Cobre enchente?'],
        [:h, 'Cobre sim, alagamento está na cobertura compreensiva.'],
        [:c, 'E se eu for viajar para a Argentina?'],
        [:h, 'Tem a Carta Verde, contratada à parte quando precisar.'],
        [:c, 'Entendi. Precisa de vistoria?'],
        [:h, 'Precisa, é feita pelo aplicativo e leva uns 10 minutos.'],
        [:c, 'Beleza.'],
        [:c, 'Vocês trabalham com qual seguradora?'],
        [:h, 'Essa cotação é de uma das maiores seguradoras do país.'],
        [:c, 'Ok, obrigado pelas explicações.'],
        [:h, 'Por nada! Fico à disposição.']
      ]
    },
    energia_solar: {
      funil: 'Energia solar',
      titulo: 'Solar residencial',
      pedido: 'Boa tarde, quero um orçamento de energia solar para a minha casa.',
      pergunta: 'Boa tarde! Qual o valor médio da sua conta de luz e o tipo do telhado?',
      dados: 'Uns R$ 600 por mês, telhado de cerâmica.',
      proposta: 'Segue o orçamento: sistema de 6 kWp com 11 placas e inversor, instalado, por R$ 21.900,00 à vista ' \
                'ou 12x de R$ 1.950,00.',
      perdeu: 'Fechei com outra empresa de energia solar, obrigado pelo orçamento.',
      ganhou: 'Vamos fechar com vocês, aceito o orçamento. Pode mandar o contrato.',
      longa: [
        [:c, 'Boa tarde, quero um orçamento de energia solar para a minha casa.'],
        [:h, 'Boa tarde! Qual o valor médio da sua conta de luz?'],
        [:c, 'Uns R$ 600 por mês.'],
        [:h, 'Seu telhado é de cerâmica ou metálico?'],
        [:c, 'Cerâmica.'],
        [:h, 'Segue o orçamento: sistema de 6 kWp com 11 placas e inversor, instalado, por R$ 21.900,00 à vista ' \
             'ou 12x de R$ 1.950,00.'],
        [:c, 'Vou dar uma olhada com calma.'],
        [:c, 'Quanto tempo leva a instalação?'],
        [:h, 'A instalação leva 2 dias depois da aprovação da distribuidora.'],
        [:c, 'E a aprovação demora?'],
        [:h, 'Em média 30 dias.'],
        [:c, 'Precisa reforçar o telhado?'],
        [:h, 'Normalmente não, o engenheiro confere na visita técnica.'],
        [:c, 'As placas têm garantia de quanto tempo?'],
        [:h, '12 anos de garantia de produto e 25 de desempenho.'],
        [:c, 'E o inversor?'],
        [:h, '10 anos.'],
        [:c, 'Funciona quando falta luz?'],
        [:h, 'O sistema ligado à rede desliga na queda de energia, por segurança.'],
        [:c, 'Ah, entendi.'],
        [:c, 'Preciso limpar as placas?'],
        [:h, 'Uma limpeza por ano com água basta.'],
        [:c, 'Dá para ver a geração pelo celular?'],
        [:h, 'Sim, o inversor tem aplicativo de monitoramento.'],
        [:c, 'Legal. E se eu mudar de casa?'],
        [:h, 'O sistema pode ser desmontado e reinstalado.'],
        [:c, 'Show.'],
        [:c, 'Vocês atendem em Londrina?'],
        [:h, 'Atendemos sim.'],
        [:c, 'Valeu pelas informações.']
      ]
    },
    idiomas: {
      funil: 'Matrículas',
      titulo: 'Inglês para adultos',
      pedido: 'Oi, quero saber do curso de inglês para adultos.',
      pergunta: 'Oi! Qual o seu nível hoje e você prefere aula online ou presencial?',
      dados: 'Intermediário, e prefiro online.',
      proposta: 'Segue a proposta: inglês online, 2 aulas por semana, R$ 389,00 por mês no plano de 12 meses, ' \
                'material incluso.',
      perdeu: 'Me matriculei em outra escola, obrigado.',
      ganhou: 'Quero fazer a matrícula com vocês no plano de 12 meses. Me manda o link de pagamento.',
      longa: [
        [:c, 'Oi, quero saber do curso de inglês para adultos.'],
        [:h, 'Oi! Qual o seu nível hoje?'],
        [:c, 'Intermediário, acho.'],
        [:h, 'Prefere aula online ou presencial?'],
        [:c, 'Online.'],
        [:h, 'Segue a proposta: inglês online, 2 aulas por semana, R$ 389,00 por mês no plano de 12 meses, ' \
             'material incluso.'],
        [:c, 'Vou pensar.'],
        [:c, 'As aulas são em grupo?'],
        [:h, 'Em grupo de até 6 alunos.'],
        [:c, 'Que horários vocês têm?'],
        [:h, 'Temos turmas de manhã cedo e à noite.'],
        [:c, 'À noite seria melhor.'],
        [:h, 'Temos às 19h e às 20h30.'],
        [:c, 'Os professores são nativos?'],
        [:h, 'Temos professores brasileiros e nativos, todos certificados.'],
        [:c, 'Tem certificado no final?'],
        [:h, 'Sim, certificado a cada nível concluído.'],
        [:c, 'Se eu faltar, tem reposição?'],
        [:h, 'Tem sim, até 2 reposições por mês.'],
        [:c, 'E prova de nivelamento?'],
        [:h, 'Fazemos um teste online de 20 minutos antes de começar.'],
        [:c, 'Ok.'],
        [:c, 'Dá para usar no celular?'],
        [:h, 'Sim, a plataforma funciona no celular.'],
        [:c, 'Tem aula de conversação?'],
        [:h, 'Tem um clube de conversação semanal, gratuito para alunos.'],
        [:c, 'Bacana.'],
        [:c, 'Vocês preparam para o TOEFL?'],
        [:h, 'Temos um módulo preparatório à parte.'],
        [:c, 'Obrigado pelas respostas.']
      ]
    }
  }.freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1926: precisão da IA de etapa' do
  let(:account) { create(:account, name: 'Empresa Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:inbox) { create_crm_inbox(account: account) }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(CRM_AI_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  before do
    skip 'eval pago: rode com CRM_EVAL_PAGO=1 e OPENAI_API_KEY' unless ENV['CRM_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?

    allow(Crm::Config).to receive(:enabled?).and_return(true)
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1926-precisao-etapa.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601, placar: placar)))
  end

  def placar
    saida[:casos].group_by { |caso| caso[:ramo] }.transform_values do |casos|
      "#{casos.count { |caso| caso[:passou] }}/#{casos.size}"
    end
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > PrecisaoEtapaEval::TETO_USD
  end

  def funil(ramo)
    pipeline = account.crm_pipelines.create!(name: ramo[:funil], created_by: admin, status: :active)
    PrecisaoEtapaEval::ETAPAS.each_with_index do |(nome, criterio), posicao|
      account.crm_pipeline_stages.create!(pipeline: pipeline, name: nome, position: posicao, metadata: { 'ai_criteria' => criterio })
    end
    pipeline
  end

  def card(pipeline, etapa, conversa, contato, titulo)
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.find_by!(name: etapa), contact: contato,
                              title: titulo, primary_conversation: conversa, inbox: inbox, currency: 'BRL')
  end

  # roteiro: [[:c | :h, texto], ...]; dias_antes_da_ultima afasta a última fala, como o cliente voltando dias depois.
  def conversa(roteiro, dias_antes_da_ultima: 0)
    contato = create(:contact, account: account, name: 'Cliente Eval')
    conversa = create_crm_conversation(account: account, inbox: inbox, contact: contato)
    inicio = 4.days.ago
    roteiro.each_with_index do |(quem, texto), indice|
      hora = inicio + (indice * 3).minutes
      hora = Time.current if indice == roteiro.size - 1 && dias_antes_da_ultima.positive?
      create(:message, account: account, inbox: inbox, conversation: conversa, content: texto, created_at: hora,
                       message_type: quem == :c ? :incoming : :outgoing, sender: quem == :c ? contato : ana)
    end
    [conversa, contato]
  end

  def classificar(card_avaliado)
    avaliador = Crm::Ai::Evaluator.new(card: card_avaliado.reload, trigger: 'manual')
    resposta = nil
    com_custo { resposta = avaliador.stage_classifier(client: avaliador.classify_client).perform }
    etapa = card_avaliado.pipeline.stages.find_by(id: resposta[:suggested_stage_id].to_i)
    { etapa: etapa&.name, confianca: resposta[:confidence].to_f, motivo: resposta[:reasoning] }
  end

  def registrar(ramo_nome, caso, esperado, resultado, passou)
    saida[:casos] << { ramo: ramo_nome, caso: caso, esperado: esperado, **resultado, passou: passou }
  end

  def proposta_e_espera(ramo)
    [[:c, ramo[:pedido]], [:h, ramo[:pergunta]], [:c, ramo[:dados]], [:h, ramo[:proposta]],
     [:c, 'Vou analisar e te retorno.'], [:h, 'Fico no aguardo!']]
  end

  def fim_incerto?(resultado, atual) = [atual, 'Perdido'].include?(resultado[:etapa])

  def rodar_ramo(nome, ramo)
    pipeline = funil(ramo)
    %i[fechou_sem_dizer_com_quem ja_resolvi_duplicado preco_no_meio_da_conversa_longa controle_perdeu_para_outro
       controle_aceitou_a_proposta].each { |caso| send(caso, nome, ramo, pipeline) }
  end

  def fechou_sem_dizer_com_quem(nome, ramo, pipeline)
    conversa_1, contato_1 = conversa(proposta_e_espera(ramo) + [[:c, 'Oi! Já conseguimos fechar, obrigado pela atenção.']],
                                     dias_antes_da_ultima: 3)
    resultado = classificar(card(pipeline, 'Proposta enviada', conversa_1, contato_1, ramo[:titulo]))
    registrar(nome, 'fechou_sem_dizer_com_quem', 'Proposta enviada ou Perdido', resultado, fim_incerto?(resultado, 'Proposta enviada'))
  end

  def ja_resolvi_duplicado(nome, ramo, pipeline)
    roteiro = [[:c, ramo[:pedido]], [:h, ramo[:pergunta]], [:c, ramo[:dados]], [:h, 'Obrigado! Vou preparar e já te mando.'],
               [:c, 'Já resolvi, obrigado.']]
    conversa_2, contato_2 = conversa(roteiro, dias_antes_da_ultima: 1)
    # O card duplicado: outro card do mesmo assunto na mesma conversa; avalia-se o segundo.
    card(pipeline, 'Em atendimento', conversa_2, contato_2, ramo[:titulo])
    resultado = classificar(card(pipeline, 'Em atendimento', conversa_2, contato_2, ramo[:titulo]))
    registrar(nome, 'ja_resolvi_duplicado', 'Em atendimento ou Perdido', resultado, fim_incerto?(resultado, 'Em atendimento'))
  end

  def preco_no_meio_da_conversa_longa(nome, ramo, pipeline)
    conversa_3, contato_3 = conversa(ramo[:longa])
    resultado = classificar(card(pipeline, 'Em atendimento', conversa_3, contato_3, ramo[:titulo]))
    viu_o_preco = ['Proposta enviada', 'Negociação'].include?(resultado[:etapa])
    registrar(nome, 'preco_no_meio_da_conversa_longa', 'Proposta enviada ou Negociação', resultado, viu_o_preco)
  end

  def controle_perdeu_para_outro(nome, ramo, pipeline)
    conversa_4, contato_4 = conversa(proposta_e_espera(ramo) + [[:c, ramo[:perdeu]]], dias_antes_da_ultima: 2)
    resultado = classificar(card(pipeline, 'Proposta enviada', conversa_4, contato_4, ramo[:titulo]))
    perdeu = resultado[:etapa] == 'Perdido' && resultado[:confianca] >= Crm::Ai::Config::AUTO_MOVE_THRESHOLD
    registrar(nome, 'controle_perdeu_para_outro', 'Perdido (confiança de mover)', resultado, perdeu)
  end

  def controle_aceitou_a_proposta(nome, ramo, pipeline)
    conversa_5, contato_5 = conversa(proposta_e_espera(ramo) + [[:c, ramo[:ganhou]]], dias_antes_da_ultima: 1)
    resultado = classificar(card(pipeline, 'Proposta enviada', conversa_5, contato_5, ramo[:titulo]))
    registrar(nome, 'controle_aceitou_a_proposta', 'Ganho', resultado, resultado[:etapa] == 'Ganho')
  end

  it 'três ramos: fim incerto não vira etapa do meio, o preço do meio da conversa é visto, os controles seguem' do
    repeticoes = ENV.fetch('EVAL_REPETICOES', '1').to_i
    repeticoes.times { PrecisaoEtapaEval::RAMOS.each { |nome, ramo| rodar_ramo(nome, ramo) } }
    gravar_saida!

    expect(saida[:casos].reject { |caso| caso[:passou] }).to eq([])
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass
