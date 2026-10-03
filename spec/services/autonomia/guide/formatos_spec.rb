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
    expect(described_class.fora_de_dia.map { |arquivo| arquivo.relative_path_from(Rails.root).to_s }).to eq([])
  end

  it 'cobre exatamente o catálogo de ações do Guia' do
    catalogo = Autonomia::Guide::Acoes.new(account: nil, user: nil).catalogo

    expect(described_class.todos.keys.sort).to eq(catalogo)
  end

  it 'POST custom_roles: envelope, permissões só da lista e nome obrigatório', :aggregate_failures do
    funcao = formato('POST custom_roles')

    expect(funcao).to include('envelope' => 'custom_role', 'corpo_plano' => true, 'completo' => true, 'modelo' => 'CustomRole')
    expect(funcao['campos'].keys).to contain_exactly('name', 'description', 'permissions')
    expect(funcao['campos']['permissions']).to include('tipo' => 'lista', 'um_de' => CustomRole::PERMISSIONS)
    expect(funcao['campos']['name']).to include('tipo' => 'string', 'obrigatorio' => true)
  end

  it 'PATCH labels/:id: na edição o título não é obrigatório, só não pode ficar vazio', :aggregate_failures do
    etiqueta = formato('PATCH labels/:id')

    expect(etiqueta).to include('envelope' => 'label', 'completo' => true)
    expect(etiqueta['campos'].keys).to contain_exactly('title', 'description', 'color', 'show_on_sidebar')
    expect(etiqueta['campos']['title']).to include('nao_pode_ficar_vazio' => true)
    expect(etiqueta['campos']['title']).not_to have_key('obrigatorio')
    expect(etiqueta['campos']['show_on_sidebar']).to include('tipo' => 'booleano')
  end

  it 'POST teams', :aggregate_failures do
    time = formato('POST teams')

    expect(time).to include('envelope' => 'team', 'completo' => true)
    expect(time['campos'].keys).to contain_exactly('name', 'description', 'allow_auto_assign', 'icon', 'icon_color')
    expect(time['campos']['name']).to include('obrigatorio' => true)
  end

  it 'POST crm/pipelines: envelope do CRM, que aceita também o corpo plano', :aggregate_failures do
    funil = formato('POST crm/pipelines')

    expect(funil).to include('envelope' => 'pipeline', 'corpo_plano' => true, 'modelo' => 'Crm::Pipeline')
    expect(funil['campos']).to include('name', 'description', 'status', 'is_default', 'position', 'metadata')
    expect(funil['campos']['metadata']).to include('tipo' => 'objeto_livre')
    expect(funil['campos']['status']).to include('um_de' => %w[active archived])
    expect(funil['campos']['name']).to include('obrigatorio' => true)
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
    it 'diz o envelope, os valores válidos e um exemplo mínimo', :aggregate_failures do
      texto = described_class.resumo_para_o_modelo('POST custom_roles')

      expect(texto).to include('"custom_role"', 'permissions', 'conversation_manage', 'obrigatório')
      expect(texto).to include('Exemplo mínimo: {"custom_role":{"name":"..."}}')
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
