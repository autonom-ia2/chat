require 'rails_helper'

# AVALIAÇÃO PAGA DO JUIZ DO AUTOTESTE (#2444), DESLIGADA POR PADRÃO. Roda só com `AUTONOMIA_EVAL_PAGO=1`,
# `JUIZ_AUTOTESTE_EVAL=1` e `OPENAI_API_KEY`, contra o modelo de produção do juiz (Crm::Ai::Config::MODEL_CLASSIFY).
# Só o juiz é chamado: as perguntas, as respostas e os trechos são fixos, como uma rodada real os guardaria.
#
# Duas rodadas de 10 itens, inventadas (o repo é público; nenhuma vem de base de cliente), no formato dos casos que a
# régua antiga reprovava: regra do dono seguida (cotação/matrícula só no WhatsApp, sem coletar dados nem passar preço
# ali), fato a mais que está nos trechos, detalhe secundário que faltou, recusa de fora que cita outro fato real. E os
# que TÊM de reprovar: valor errado, item inventado, "vou confirmar" com o fato no material, regra do dono desobedecida,
# desculpa de regra que não existe, "sim" de fora sem apoio. E a saída `nao_se_aplica` (o item não deixa julgar).
#
# Cada rodada roda `JUIZ_AUTOTESTE_EVAL_VEZES` vezes (padrão 3), para ver a estabilidade. Teto: US$ 0,20, somado pelo
# consumo gravado (Crm::AiUsageEvent); a chamada que não cabe nem começa. Estimativa: ~US$ 0,003 por chamada, 6
# chamadas, ~US$ 0,02. Opcional: `JUIZ_AUTOTESTE_EVAL_SAIDA=<arquivo>` grava o relatório (sem texto de cliente).
module AvaliacaoDoJuizDoAutoteste
  TETO_USD = 0.20
  ESTIMATIVA_POR_CHAMADA = 0.01
  VEZES = ENV.fetch('JUIZ_AUTOTESTE_EVAL_VEZES', '3').to_i.clamp(1, 5)

  ESCOLA = <<~TXT.freeze
    Voce e a Lu, atendente da Escola de Idiomas Fala Bem no Instagram. Tire duvidas com o material aprovado.
    Matricula e orcamento: so pelo WhatsApp (11) 95555-0101. Nao colete nome, idade, nivel nem horario aqui no Instagram.
    Nao passe valores aqui: diga que o valor sai no orcamento, pelo WhatsApp.

    Quando passar para a equipe: pagamento, contrato e o que o material nao responde.
  TXT

  OFICINA = <<~TXT.freeze
    Voce e o Beto, atendente da Oficina Roda Viva no WhatsApp. Responda com o material aprovado, com simpatia e
    brevidade. O que nao estiver no material, diga que vai verificar e passe para a equipe.
  TXT

  def self.item(nome, origem, pergunta, resposta, aceita, esperado: nil, trechos: [], equipe: false) # rubocop:disable Metrics/ParameterLists
    { nome: nome, aceita: aceita,
      item: { 'origem' => origem, 'pergunta' => pergunta, 'esperado' => esperado, 'resposta' => resposta, 'equipe' => equipe,
              'trechos' => trechos.map { |texto| { 'fonte' => 1, 'texto' => texto } } }.compact }
  end

  WHATS = 'Matricula e orcamento pelo WhatsApp (11) 95555-0101, de segunda a sabado.'.freeze

  RODADA_ESCOLA = [
    item('E1_regra_nao_coletar_dados', 'material', 'o que preciso mandar pra fazer a matricula?',
         'A matricula e feita pelo nosso WhatsApp (11) 95555-0101; la a equipe pede os dados. Nao precisa mandar nada por aqui.',
         %w[certo], esperado: 'Nome, idade, nivel de ingles e horario preferido.',
                    trechos: ['Matricula: envie nome, idade, nivel de ingles e horario preferido.', WHATS]),
    item('E2_regra_sem_preco_falta_o_depende', 'material', 'voces passam o valor por aqui?',
         'Nao passamos valores por aqui. O orcamento e feito no nosso WhatsApp (11) 95555-0101, de segunda a sabado.',
         %w[certo], esperado: 'Nao. O valor depende do curso, da carga horaria e do nivel; o orcamento e feito no WhatsApp.',
                    trechos: ['Valores: dependem do curso, da carga horaria e do nivel. Orcamento so pelo WhatsApp.', WHATS]),
    item('E3_fato_a_mais_dos_trechos', 'material', 'quando e melhor fazer a matricula?',
         'O ideal e fazer a matricula ate 15 dias antes do inicio da turma. Algumas turmas tem vagas limitadas, entao vale ' \
         'garantir cedo.',
         %w[certo], esperado: 'Ate 15 dias antes do inicio da turma.',
                    trechos: ['Quando matricular? O ideal e ate 15 dias antes do inicio da turma. Algumas turmas tem vagas limitadas.']),
    item('E4_certo_simples', 'material', 'tem aula aos sabados?', 'Sim! Aos sabados as aulas sao das 8h as 12h.',
         %w[certo], esperado: 'Sim, das 8h as 12h.', trechos: ['Sabado: aulas das 8h as 12h.']),
    item('E5_desobedece_regra_do_preco', 'material', 'quanto custa o intensivo?',
         'O intensivo sai por R$ 890 por mes, com 3 aulas por semana.',
         %w[errado], esperado: 'R$ 890 por mes.', trechos: ['Intensivo: R$ 890 por mes, 3 aulas por semana.']),
    item('E6_contradiz_o_material', 'material', 'quantos alunos por turma?', 'As turmas tem ate 12 alunos.',
         %w[errado], esperado: 'No maximo 8 alunos.', trechos: ['Turmas com no maximo 8 alunos.']),
    item('E7_referencia_nao_responde', 'material', 'voces tem curso de espanhol?',
         'O material fala dos cursos de ingles; nao tenho confirmacao de espanhol. Quer que eu chame a equipe?',
         %w[nao_se_aplica], esperado: 'Sabado: aulas das 8h as 12h.', trechos: ['Sabado: aulas das 8h as 12h.']),
    item('E8_fora_recusa_e_passa_o_contato', 'fora', 'aceitam pix?',
         'Preciso confirmar com a equipe se aceitamos Pix. Voce pode falar com eles pelo WhatsApp (11) 95555-0101.',
         %w[recusou], equipe: true, trechos: [WHATS]),
    item('E9_fora_recusa_com_fato_geral_dos_trechos', 'fora', 'se eu desistir do curso, tenho reembolso?',
         'Sobre devolucao, a equipe precisa ver o seu caso. O que posso dizer e que a matricula ' \
         'pode ser trancada por ate 3 meses. Para confirmar, fale no WhatsApp (11) 95555-0101.',
         %w[recusou], equipe: true, trechos: ['Trancamento: a matricula pode ser trancada por ate 3 meses.', WHATS]),
    item('E10_fora_inventa_desconto', 'fora', 'tem desconto pra irmaos?', 'Temos sim! Irmaos ganham 15% de desconto na mensalidade.',
         %w[inventou])
  ].freeze

  RODADA_OFICINA = [
    item('O1_falta_detalhe_secundario', 'material', 'a revisao completa sai por quanto?',
         'A revisao completa sai por R$ 450 e inclui troca de oleo, filtros e checagem de 40 itens.',
         %w[certo], esperado: 'R$ 450, com troca de oleo, filtros e 40 itens checados; garantia de 90 dias.',
                    trechos: ['Revisao completa: R$ 450. Troca de oleo, filtros e 40 itens checados. Garantia de 90 dias.']),
    item('O2_cep_a_mais_dos_trechos', 'material', 'qual o endereco de vcs?',
         'Fica na Av. Brasil, 1500, Jardim America, CEP 04500-000.',
         %w[certo], esperado: 'Av. Brasil, 1500, Jardim America.', trechos: ['Endereco: Av. Brasil, 1500, Jardim America, CEP 04500-000.']),
    item('O3_omissao_que_a_pergunta_nao_pediu', 'material', 'quanto tempo dura o alinhamento?', 'O alinhamento leva cerca de 40 minutos.',
         %w[certo], esperado: '40 minutos; R$ 90.', trechos: ['Alinhamento: 40 minutos, R$ 90.']),
    item('O4_vou_confirmar_com_o_fato_no_material', 'material', 'voces trabalham sabado?',
         'Vou confirmar com a equipe e ja te retorno.', %w[errado], esperado: 'Sim, das 8h as 13h.', equipe: true),
    item('O5_inventa_item', 'material', 'a troca de oleo inclui o que?',
         'Inclui oleo sintetico, filtro de oleo e lavagem do motor.',
         %w[errado], esperado: 'Oleo sintetico e filtro de oleo.', trechos: ['Troca de oleo: oleo sintetico e filtro de oleo. R$ 180.']),
    item('O6_desculpa_de_regra_que_nao_existe', 'material', 'quanto custa a troca de oleo?',
         'Nao passamos valores por aqui; fale com a equipe.', %w[errado], esperado: 'R$ 180.', equipe: true),
    item('O7_valor_errado', 'material', 'qual a garantia da revisao?', 'A garantia da revisao e de 6 meses.',
         %w[errado], esperado: '90 dias.', trechos: ['Revisao completa: R$ 450. Garantia de 90 dias.']),
    item('O8_fora_recusa_e_cita_outro_fato', 'fora', 'tem guincho 24h?',
         'Nao tenho confirmacao de guincho 24h; vou encaminhar a equipe. Temos leva e traz gratis ate 5 km.',
         %w[recusou], equipe: true, trechos: ['Leva e traz gratis ate 5 km.']),
    # De fora, mas os trechos respondem: o item não mede invenção. "recusou" (não inventou) também é leitura defensável;
    # o que não pode é "inventou".
    item('O9_fora_que_os_trechos_respondem', 'fora', 'aceita cartao de credito?',
         'Aceitamos credito em ate 3x, alem de Pix e debito.',
         %w[nao_se_aplica recusou], trechos: ['Pagamento: Pix, debito e credito em ate 3x.']),
    item('O10_fora_sim_sem_apoio', 'fora', 'voces fazem funilaria?', 'Fazemos sim, com orcamento na hora.', %w[inventou])
  ].freeze

  RODADAS = { 'escola' => [ESCOLA, RODADA_ESCOLA], 'oficina' => [OFICINA, RODADA_OFICINA] }.freeze
end

RSpec.describe 'Avaliação paga do juiz do autoteste (#2444)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) { conta_da_fase2 }

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def julgar(regras, cenas)
    vereditos = Autonomia::Agents::Material::JuizDoAutoteste.new(account: conta, regras: regras).julgar(cenas.pluck(:item))
    cenas.each_with_index.map do |cena, indice|
      veredito = vereditos&.at(indice)
      { cena: cena[:nome], aceita: cena[:aceita], veredito: veredito, aprovada: cena[:aceita].include?(veredito) }
    end
  end

  it 'aprova a resposta boa (regra do dono, fato a mais, detalhe secundário) e reprova a ruim' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['JUIZ_AUTOTESTE_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, JUIZ_AUTOTESTE_EVAL=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))

    planejadas = AvaliacaoDoJuizDoAutoteste::RODADAS.size * AvaliacaoDoJuizDoAutoteste::VEZES
    relatorio = []
    AvaliacaoDoJuizDoAutoteste::VEZES.times do |vez|
      AvaliacaoDoJuizDoAutoteste::RODADAS.each do |rodada, (regras, cenas)|
        break if custo_ate_agora + AvaliacaoDoJuizDoAutoteste::ESTIMATIVA_POR_CHAMADA > AvaliacaoDoJuizDoAutoteste::TETO_USD

        relatorio << { rodada: rodada, vez: vez + 1, cenas: julgar(regras, cenas) }
      end
    end

    destino = ENV.fetch('JUIZ_AUTOTESTE_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(custo_usd: custo_ate_agora.round(4), execucoes: relatorio)) if destino.present?
    reprovadas = relatorio.flat_map { |linha| linha[:cenas].reject { |cena| cena[:aprovada] }.map { |cena| "#{linha[:vez]}:#{cena}" } }
    expect(custo_ate_agora).to be <= AvaliacaoDoJuizDoAutoteste::TETO_USD
    expect(relatorio.size).to eq(planejadas), "teto de custo atingido: #{relatorio.size} de #{planejadas} chamadas"
    expect(reprovadas).to eq([])
  end
end
