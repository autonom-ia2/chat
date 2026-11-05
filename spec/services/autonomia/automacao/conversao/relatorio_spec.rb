require 'rails_helper'

# F9.1 (#2568): o relatório diz o que cada regra antiga vira no motor novo, sem gravar nada. As regras aqui imitam os
# moldes achados em produção (leitura agregada de 05/11, no doc F9), sem dado de cliente.
RSpec.describe Autonomia::Automacao::Conversao::Relatorio do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  def regra(**atributos)
    create(:automation_rule, account: account, **atributos)
  end

  # Molde "caixa X vai para a dona": conversa criada na caixa → atribuir à pessoa.
  def regra_da_caixa
    regra(event_name: 'conversation_created',
          conditions: [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: nil }],
          actions: [{ action_name: 'assign_agent', action_params: [admin.id] }])
  end

  # MOTIVO: é o molde de 26 das 34 regras de produção; tem de converter inteiro, e a receita tem de passar no esquema
  # e na conferência do motor novo, senão o "converte" do relatório é mentira.
  it 'converte o molde caixa → responsável numa receita que o motor novo aceita' do
    linha = described_class.new(account).tap { regra_da_caixa }.linhas.sole

    expect(linha).to be_convertivel
    expect(linha.receita).to eq(
      'gatilho' => { 'tipo' => 'conversa.criada',
                     'filtros' => [{ 'campo' => { '$valor' => 'conversa.caixa_id' }, 'op' => 'igual', 'valor' => inbox.id }] },
      'passos' => [{ 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST conversations/:conversation_id/assignments',
                     'caminho' => { 'conversation_id' => { '$valor' => 'conversa.id' } },
                     'descricao' => "Convertido da regra #{linha.id}", 'corpo' => { 'assignee_id' => admin.id } }]
    )
    expect(Autonomia::Automacao::Receita.esquema_valido?(linha.receita)).to be(true)
    expect(Autonomia::Automacao::Receita.new(linha.receita, conta: account).problemas).to eq([])
  end

  # MOTIVO: o relatório é só leitura (F9.1). Se gravasse, rodar o relatório já mexeria na conta.
  it 'não grava nada' do
    regra_da_caixa

    expect { described_class.new(account).resumo }.not_to change(Autonomia::Automacao::Definicao, :count)
    expect(account.automation_rules.sole).to be_active
  end

  # MOTIVO: 7 regras de produção ouvem "conversa atualizada", que o motor novo ainda não tem.
  it 'diz a falta e a fase quando o evento não tem gatilho, sem montar receita' do
    regra(event_name: 'conversation_updated', active: false,
          conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['pending'], query_operator: nil }],
          actions: [{ action_name: 'add_label', action_params: ['retorno'] }])

    linha = described_class.new(account).linhas.sole
    expect(linha).not_to be_convertivel
    expect(linha.receita).to be_nil
    expect(linha.faltas.pluck(:chave)).to eq(['gatilho_conversa_atualizada'])
    expect(linha.ligada).to be(false)
  end

  # MOTIVO: no antigo o AND pesa mais que o OR; agrupar errado mudaria quem a regra pega.
  it 'agrupa as condições no OR, com o AND dentro de cada grupo' do
    regra(event_name: 'conversation_created',
          conditions: [
            { attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: 'AND' },
            { attribute_key: 'priority', filter_operator: 'equal_to', values: ['high'], query_operator: 'OR' },
            { attribute_key: 'labels', filter_operator: 'equal_to', values: %w[vip], query_operator: nil }
          ],
          actions: [{ action_name: 'add_label', action_params: ['triagem'] }])

    filtro = described_class.new(account).linhas.sole.receita.dig('gatilho', 'filtros', 0)
    expect(filtro).to eq('alguma' => [
                           { 'todas' => [
                             { 'campo' => { '$valor' => 'conversa.caixa_id' }, 'op' => 'igual', 'valor' => inbox.id },
                             { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'high' }
                           ] },
                           { 'campo' => { '$valor' => 'conversa.etiquetas' }, 'op' => 'contem', 'valor' => 'vip' }
                         ])
  end

  # MOTIVO: o assunto do e-mail não tem valor no motor novo, e o "contém" antigo é pedaço de texto (o novo é item de
  # lista). Traduzir em silêncio faria a regra parar de pegar o que pegava.
  it 'não traduz o assunto do e-mail, e lista cada falta da regra de várias peças' do
    antiga = build(:automation_rule, account: account, event_name: 'message_created',
                                     conditions: [
                                       { 'attribute_key' => 'inbox_id', 'filter_operator' => 'equal_to', 'values' => [inbox.id],
                                         'query_operator' => 'AND' },
                                       { 'attribute_key' => 'mail_subject', 'filter_operator' => 'contains',
                                         'values' => ['cotação'], 'query_operator' => 'AND' },
                                       { 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to',
                                         'values' => ['incoming'], 'query_operator' => nil }
                                     ],
                                     actions: [{ 'action_name' => 'crm_create_card', 'action_params' => [1] },
                                               { 'action_name' => 'perguntar_ao_decisor', 'action_params' => [1, 'sim'] }])

    linha = Autonomia::Automacao::Conversao::DaRegra.new(antiga).resultado
    expect(linha.faltas.pluck(:chave)).to eq(%w[campo_sem_valor passo_de_card passo_decidir])
    expect(linha.receita.dig('gatilho', 'filtros', 0, 'todas').pluck('valor')).to eq([inbox.id, 'recebida'])
  end

  # MOTIVO: o "contém" antigo num campo de texto é pedaço do texto; o novo é item de lista.
  it 'não traduz o contém de texto num campo que existe' do
    antiga = build(:automation_rule, account: account, event_name: 'conversation_created',
                                     conditions: [{ 'attribute_key' => 'email', 'filter_operator' => 'contains',
                                                    'values' => ['@empresa'], 'query_operator' => nil }],
                                     actions: [{ 'action_name' => 'add_label', 'action_params' => ['b2b'] }])

    expect(Autonomia::Automacao::Conversao::DaRegra.new(antiga).resultado.faltas.pluck(:chave)).to eq(['operador_texto'])
  end

  # MOTIVO: no antigo, "diferente" é NOT IN e o campo vazio não casa; o novo casaria, e a regra pegaria conversas a mais.
  it 'leva o diferente de campo único junto com preenchido, e o de etiqueta sozinho' do
    antiga = build(:automation_rule, account: account, event_name: 'conversation_created',
                                     conditions: [
                                       { 'attribute_key' => 'team_id', 'filter_operator' => 'not_equal_to', 'values' => [3],
                                         'query_operator' => 'AND' },
                                       { 'attribute_key' => 'labels', 'filter_operator' => 'not_equal_to', 'values' => ['vip'],
                                         'query_operator' => nil }
                                     ],
                                     actions: [{ 'action_name' => 'add_label', 'action_params' => ['b'] }])

    expect(Autonomia::Automacao::Conversao::DaRegra.new(antiga).resultado.receita.dig('gatilho', 'filtros', 0)).to eq(
      'todas' => [
        { 'todas' => [{ 'campo' => { '$valor' => 'conversa.time_id' }, 'op' => 'preenchido' },
                      { 'campo' => { '$valor' => 'conversa.time_id' }, 'op' => 'diferente', 'valor' => 3 }] },
        { 'campo' => { '$valor' => 'conversa.etiquetas' }, 'op' => 'nao_contem', 'valor' => 'vip' }
      ]
    )
  end

  # MOTIVO: variável Liquid não tem tradução automática segura; o relatório precisa mandar para revisão humana.
  it 'manda texto com variável para o conversor, e converte o texto puro' do
    com_variavel = build(:automation_rule, account: account, event_name: 'conversation_created', conditions: [],
                                           actions: [{ 'action_name' => 'send_message', 'action_params' => ['Oi {{contact.name}}'] }])
    sem_variavel = build(:automation_rule, account: account, event_name: 'conversation_created', conditions: [],
                                           actions: [{ 'action_name' => 'send_message', 'action_params' => ['Oi!'] }])

    expect(Autonomia::Automacao::Conversao::DaRegra.new(com_variavel).resultado.faltas.pluck(:chave)).to eq(['texto_com_variavel'])
    expect(Autonomia::Automacao::Conversao::DaRegra.new(sem_variavel).resultado.receita['passos'])
      .to eq([{ 'id' => 'p1', 'tipo' => 'mensagem', 'texto' => ['Oi!'] }])
  end

  # MOTIVO: as 12 automações de etapa de produção dependem da F6 e da F7; o relatório tem de dizer isso por passo e
  # avisar que o gatilho novo também dispara na criação do card.
  it 'lê a automação de etapa, com a falta de cada passo e a ressalva do caminho do card' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    automacao = account.crm_stage_automations.create!(pipeline: pipeline, stage: stage, name: 'Retornos',
                                                      trigger_event: :on_enter, created_by: admin)
    automacao.steps.create!(account: account, action_type: :create_follow_up, delay_seconds: 86_400,
                            action_config: { title: 'Ligar' })
    automacao.steps.create!(account: account, action_type: :assign_owner, action_config: { owner_id: admin.id })

    linha = described_class.new(account).linhas.sole
    expect(linha.origem).to eq('etapa')
    expect(linha.receita['gatilho']).to eq('tipo' => 'card.entrou_na_etapa', 'etapa_id' => stage.id)
    expect(linha.faltas.pluck(:chave)).to eq(%w[gatilho_de_card passo_retorno passo_de_card])
    expect(linha.ressalvas.first).to start_with('caminho_do_card')
    expect(linha.autor_conhecido).to be(true)
  end

  # MOTIVO: o resumo é o "estas N viram estas N" que vai ao Rodrigo.
  it 'resume a conta em contagens e faltas por fase' do
    regra_da_caixa
    regra(event_name: 'conversation_updated', active: false,
          conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['pending'], query_operator: nil }],
          actions: [{ action_name: 'add_label', action_params: ['retorno'] }])

    expect(described_class.new(account).resumo).to include(
      antigas: 2, ligadas: 1, convertiveis_agora: 1, faltas_por_fase: { 'F6 PR2d (proposta F9)' => 1 }
    )
  end
end
