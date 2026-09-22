require 'rails_helper'

# As telas para onde o botão do Guia leva (#590), lidas do mapa DE VERDADE —
# o mesmo arquivo que o modelo recebe. Um mapa escrito à mão aqui repetiria o
# engano do código em vez de pegá-lo.
RSpec.describe Autonomia::Guide::Telas do
  let(:telas) { described_class.padrao }

  it 'conhece as telas do mapa, inclusive as de um registro só' do
    expect(telas.nomes).to include('labels_list', 'settings_inbox_show', 'inbox_conversation')
  end

  it 'leva à tela geral sem parâmetro nenhum', :aggregate_failures do
    destino = telas.destino('labels_list', {})

    expect(destino[:route_name]).to eq('labels_list')
    expect(destino[:params]).to eq({})
  end

  # O caso que não tinha botão: horário de atendimento é a aba de UMA caixa.
  it 'leva à tela de uma caixa com o id e a aba' do
    destino = telas.destino('settings_inbox_show', { 'inboxId' => 12, 'tab' => 'business-hours' })

    expect(destino[:params]).to eq('inboxId' => '12', 'tab' => 'business-hours')
  end

  it 'diz o que falta quando a tela é de um registro e o id não veio' do
    expect { telas.destino('settings_inbox_show', {}) }
      .to raise_error(described_class::Recusada, /inboxId/)
  end

  it 'recusa tela que não está no mapa' do
    expect { telas.destino('super_admin_accounts', {}) }
      .to raise_error(described_class::Recusada, /não está no mapa/)
  end

  # O painel sempre usa a conta aberta; aceitar outra do modelo seria um botão
  # para outra conta.
  it 'nunca aceita o id da conta vindo do modelo' do
    destino = telas.destino('settings_inbox_show', { 'accountId' => '99', 'inboxId' => '12' })

    expect(destino[:params]).not_to have_key('accountId')
  end

  it 'descarta parâmetro que a tela não tem e valor que não é simples' do
    destino = telas.destino('settings_inbox_show', { 'inboxId' => '12', 'outro' => '1', 'tab' => { 'x' => 1 } })

    expect(destino[:params]).to eq('inboxId' => '12')
  end

  # `/agents/:agentId/:tab(test|knowledge|...)?`: o parâmetro chama `tab`, não
  # `tab(test|knowledge...)`. Lido errado, a aba nunca chegaria ao botão.
  it 'lê o nome do parâmetro que tem valores fechados no endereço' do
    destino = telas.destino('autonomia_agent_panel', { 'agentId' => '3', 'tab' => 'tune' })

    expect(destino[:params]).to eq('agentId' => '3', 'tab' => 'tune')
  end

  it 'aponta a tela de um registro que mora abaixo da lista', :aggregate_failures do
    expect(telas.de_um_registro('autonomia_agents_index').join).to include('autonomia_agent_panel (agentId)')
    expect(telas.de_um_registro('crm_handoff_settings_index').join).to include('crm_handoff_settings_edit (pipelineId)')
    expect(telas.de_um_registro('labels_list')).to eq([])
  end

  it 'segue o papel que o mapa exige para a tela', :aggregate_failures do
    expect { telas.destino('settings_inbox_show', { 'inboxId' => '1' }, permissoes: ['agent']) }
      .to raise_error(described_class::Recusada, /não abre para o perfil/)
    expect(telas.destino('settings_inbox_show', { 'inboxId' => '1' }, permissoes: ['administrator'])).to be_present
    # Função personalizada: vale a chave, como no painel.
    expect(telas.destino('settings_inbox_show', { 'inboxId' => '1' }, permissoes: %w[inbox_view custom_role])).to be_present
    expect(telas.destino('inbox_conversation', { 'conversation_id' => '1' }, permissoes: ['agent'])).to be_present
  end

  it 'só aceita o destaque que existe para aquela tela', :aggregate_failures do
    expect(telas.destino('labels_list', {}, 'settings-add-label')[:highlight]).to eq('settings-add-label')
    expect(telas.destino('labels_list', {}, 'botao-inventado')[:highlight]).to be_nil
  end
end
