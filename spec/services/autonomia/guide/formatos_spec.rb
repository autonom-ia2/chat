require 'rails_helper'

# O formato de cada ação de escrita do Guia sai do código (#900). Este spec
# segura três coisas: o JSON versionado está em dia com o código (roda no CI
# "Testes do fork"), amostras reais conferidas à mão contra os controllers, e
# um piso de cobertura — o formato só pode melhorar.
RSpec.describe Autonomia::Guide::Formatos do
  def formato(acao)
    described_class.para(acao) || raise("sem formato para #{acao}")
  end

  it 'o formato versionado está em dia com o código (rode `bundle exec rails autonomia:guia:formatos`)' do
    fora = described_class.fora_de_dia.map { |arquivo| arquivo.relative_path_from(Rails.root).to_s }
    expect(fora).to eq([]), "fora de dia: #{fora.join(', ')}\n#{described_class.diferencas.join("\n")}"
  end

  it 'cobre exatamente o catálogo de ações do Guia' do
    catalogo = Autonomia::Guide::Acoes.new(account: nil, user: nil).catalogo

    expect(described_class.todos.keys.sort).to eq(catalogo)
  end

  it 'POST custom_roles: envelope, permissões só da lista e nome exigido pelo registro', :aggregate_failures do
    funcao = formato('POST custom_roles')

    expect(funcao).to include('envelope' => 'custom_role', 'corpo_plano' => true, 'completo' => true, 'modelo' => 'CustomRole')
    expect(funcao['campos'].keys).to contain_exactly('name', 'description', 'permissions')
    expect(funcao['campos']['permissions']).to include('tipo' => 'lista', 'um_de' => CustomRole::PERMISSIONS)
    expect(funcao['campos']['name']).to include('tipo' => 'string', 'obrigatorio' => 'pelo_modelo')
  end

  it 'PATCH labels/:id: na edição o título não é obrigatório, só não pode ficar vazio', :aggregate_failures do
    etiqueta = formato('PATCH labels/:id')

    expect(etiqueta).to include('envelope' => 'label', 'completo' => true)
    expect(etiqueta['campos'].keys).to contain_exactly('title', 'description', 'color', 'show_on_sidebar')
    expect(etiqueta['campos']['title']).to include('nao_pode_ficar_vazio' => true)
    expect(etiqueta['campos']['title']).not_to have_key('obrigatorio')
    expect(etiqueta['campos']['show_on_sidebar']).to include('tipo' => 'booleano')
  end

  # Bateria, C03: "Title is invalid" não diz a regra. O formato leva a expressão do FormatValidator e a
  # unicidade, e o resumo para o modelo as mostra — é daí que ele tira "cliente-vip".
  it 'POST labels: leva a regra de texto e a unicidade do título', :aggregate_failures do
    titulo = formato('POST labels')['campos']['title']

    expect(titulo['padrao_do_texto']).to eq(Label.validators_on(:title).grep(ActiveModel::Validations::FormatValidator).first.options[:with].source)
    expect(titulo).to include('unico' => true)
    expect(described_class.resumo_para_o_modelo('POST labels')).to include('expressão', 'único na conta')
  end

  it 'POST teams', :aggregate_failures do
    time = formato('POST teams')

    expect(time).to include('envelope' => 'team', 'completo' => true)
    expect(time['campos'].keys).to contain_exactly('name', 'description', 'allow_auto_assign', 'icon', 'icon_color')
    expect(time['campos']['name']).to include('obrigatorio' => 'pelo_modelo')
  end

  it 'POST crm/pipelines: envelope do CRM, que aceita também o corpo plano', :aggregate_failures do
    funil = formato('POST crm/pipelines')

    expect(funil).to include('envelope' => 'pipeline', 'corpo_plano' => true, 'modelo' => 'Crm::Pipeline')
    expect(funil['campos']).to include('name', 'description', 'status', 'is_default', 'position', 'metadata')
    expect(funil['campos']['metadata']).to include('tipo' => 'objeto_livre')
    expect(funil['campos']['status']).to include('um_de' => %w[active archived])
    expect(funil['campos']['name']).to include('obrigatorio' => 'pelo_modelo')
  end

  it 'PATCH crm/cards/:id não aceita funil, etapa nem situação (esses têm ação própria)', :aggregate_failures do
    card = formato('PATCH crm/cards/:id')

    expect(card).to include('envelope' => 'card', 'completo' => true, 'modelo' => 'Crm::Card')
    expect(card['campos'].keys).not_to include('pipeline_id', 'stage_id', 'status')
    expect(card['campos']).to include('title', 'owner_id', 'value_cents', 'priority')
    expect(card['campos']['priority']).to include('um_de' => Crm::Card.defined_enums['priority'].keys)
  end

  it 'PATCH inboxes/:id: o canal muda com o tipo e o fuso vai resumido', :aggregate_failures do
    caixa = formato('PATCH inboxes/:id')
    canal = caixa['campos']['channel']

    expect(caixa).to include('modelo' => 'Inbox')
    expect(caixa['envelope']).to be_nil
    expect(canal['depende_de']).to be_present
    expect(canal['por_tipo'].keys).to include('Channel::Api', 'Channel::WebWidget', 'Channel::Email')
    expect(canal['por_tipo']['Channel::Api'].keys).to include('webhook_url', 'hmac_mandatory', 'additional_attributes')
    expect(caixa['campos']['timezone']).to include('valida_no_servidor' => true)
    expect(caixa['campos']['timezone']).not_to have_key('um_de')
    expect(caixa['campos']['working_hours']).to include('tipo' => 'lista_de_objetos')
    expect(caixa['campos']['working_hours']['campos']).to include('day_of_week', 'open_hour', 'closed_all_day')
  end

  it 'POST automation_rules: condições e ações em lista, atraso só com o recurso ligado', :aggregate_failures do
    regra = formato('POST automation_rules')

    expect(regra['completo']).to be(true)
    expect(regra['campos']['conditions']).to include('tipo' => 'lista_de_objetos')
    expect(regra['campos']['conditions']['campos']).to include('attribute_key', 'filter_operator', 'values')
    expect(regra['campos']['actions']['campos']).to include('action_name', 'action_params')
    expect(regra['campos']['execution_delay']).to include('so_se' => a_string_including('delayed_automations'))
  end

  # Revisão do #900. A presença que o modelo exige não é contrato do corpo: o
  # card nasce com o título derivado do contato, o ContactInboxBuilder gera o
  # source_id, o OutboundCallBuilder abre a conversa e o provisionador do WAHA
  # usa o telefone como nome. Barrar antes da API recusava pedido que funciona.
  describe 'obrigatório' do
    def problemas(acao, corpo)
      Autonomia::Guide::Formatos::Conferencia.new(acao, corpo).problemas
    end

    it 'o exigido só pelo modelo informa e não bloqueia', :aggregate_failures do
      expect(problemas('POST crm/cards', { 'conversation_id' => 10, 'pipeline_id' => 1, 'stage_id' => 2 })).to eq([])
      expect(problemas('POST contacts/:contact_id/contact_inboxes', { 'inbox_id' => 3 })).to eq([])
      expect(problemas('POST contacts/:id/call', { 'inbox_id' => 3 })).to eq([])
      expect(problemas('POST waha_inboxes', { 'phone' => '5511999999999' })).to eq([])
      expect(formato('POST crm/cards')['campos']['title']).to include('obrigatorio' => 'pelo_modelo')
      expect(described_class.resumo_para_o_modelo('POST crm/cards')).not_to include('Exemplo mínimo')
    end

    it 'o params.require do código continua bloqueando', :aggregate_failures do
      expect(formato('POST contacts/:id/call')['campos']['inbox_id']).to include('obrigatorio' => true)
      expect(problemas('POST contacts/:id/call', { 'conversation_id' => 7 })).to eq(['falta o obrigatório: inbox_id'])
    end
  end

  # O permit vai para o cliente do Linear, não para a conversa que o
  # before_action busca: prioridade lá é 0 a 4 e os ids são UUID.
  it 'POST integrations/linear/create_issue não herda tipo nem enum do modelo de outro lugar', :aggregate_failures do
    linear = formato('POST integrations/linear/create_issue')

    expect(linear).not_to have_key('modelo')
    expect(linear['campos']['priority']).not_to have_key('um_de')
    expect(linear['campos']['team_id']).not_to have_key('tipo')
    expect(Autonomia::Guide::Formatos::Conferencia.new('POST integrations/linear/create_issue',
                                                       { 'conversation_id' => 5, 'team_id' => 'abc', 'title' => 'Bug',
                                                         'priority' => 2 }).problemas).to eq([])
  end

  # `permit(allowed_agent_params)` recebe uma lista, que o Rails achata; e o
  # update só usa o que o `slice` separa — o e-mail fica de fora.
  it 'PATCH agents/:id: abre a lista do permit e segue o slice do update', :aggregate_failures do
    campos = formato('PATCH agents/:id')['campos']

    expect(campos.keys).to include('name', 'role', 'availability', 'auto_offline', 'custom_role_id')
    expect(campos.keys).not_to include('email')
  end

  # O update recorta o `account_params` (que é do cadastro) com `slice`: o que
  # sobra é descartado calado, e o formato não pode oferecer.
  it 'PATCH conta: só o que o update usa do account_params', :aggregate_failures do
    campos = formato('PATCH conta')['campos']

    expect(campos.keys).to include('name', 'locale', 'domain', 'support_email', 'timezone', 'auto_resolve_after')
    expect(campos.keys).not_to include('account_name', 'email', 'password', 'user_full_name')
    expect(Autonomia::Guide::Formatos::Conferencia.new('PATCH conta', { 'account_name' => 'Corretora Nova' }).problemas)
      .to include(a_string_including('campo que esta ação não tem: account_name'))
  end

  it 'nenhum nome de campo, em nível nenhum, é trecho de código' do
    nomes = lambda do |campos|
      (campos || {}).flat_map do |nome, campo|
        [nome, *nomes.call(campo['campos']), *(campo['por_tipo'] || {}).values.flat_map { |dentro| nomes.call(dentro) }]
      end
    end
    todos = described_class.todos.values.flat_map { |item| nomes.call(item['campos']) + nomes.call(item['fora_do_envelope']) }

    expect(todos.select { |nome| nome.include?('[') || nome.include?(':') || nome.include?(' ') }.uniq).to eq([])
  end

  it 'ação que não lê corpo', :aggregate_failures do
    expect(formato('POST conversations/:id/mute')).to include('sem_corpo' => true, 'completo' => true)
    expect(formato('POST conversations/:id/mute')).not_to have_key('campos')
  end

  # Medido em 03/10/2026: 218 de 360 ações com corpo (60,6%). Só sobe.
  it 'mantém o piso de cobertura das ações com corpo' do
    com_corpo = described_class.todos.values.reject { |item| item['sem_corpo'] }
    completas = com_corpo.count { |item| item['completo'] }

    expect(completas.to_f / com_corpo.size).to be >= 0.605
  end

  describe '.resumo_para_o_modelo' do
    it 'diz o envelope, os valores válidos e o que o registro exige, sem pôr no mínimo', :aggregate_failures do
      texto = described_class.resumo_para_o_modelo('POST custom_roles')

      expect(texto).to include('"custom_role"', 'permissions', 'conversation_manage')
      expect(texto).to include('name: texto; o registro exige, mas a ação pode preencher sozinha')
      expect(texto).not_to include('Exemplo mínimo')
    end

    it 'monta o exemplo mínimo com o que o código exige' do
      expect(described_class.resumo_para_o_modelo('POST contacts/:id/call')).to include('Exemplo mínimo: {"inbox_id":1}')
    end

    it 'cabe no teto para toda ação do catálogo' do
      maiores = described_class.todos.keys.map { |acao| [acao, described_class.resumo_para_o_modelo(acao).size] }

      expect(maiores.select { |_acao, tamanho| tamanho > Autonomia::Guide::Formatos::Resumo::TETO }).to eq([])
    end

    it 'avisa quando a ação não lê corpo e devolve nil para ação desconhecida', :aggregate_failures do
      expect(described_class.resumo_para_o_modelo('POST conversations/:id/mute')).to include('não lê corpo')
      expect(described_class.resumo_para_o_modelo('POST nada_disso')).to be_nil
    end
  end
end
