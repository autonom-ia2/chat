require 'rails_helper'
load Rails.root.join('script/guia/varredura_esquemas.rb')

# AC-G5: a varredura conta o legado que o esquema recusaria, sem gravar nada e sem tirar dado do banco.
RSpec.describe VarreduraEsquemas do
  let(:conta) { create(:account) }
  let(:regra_boa) { create(:automation_rule, account: conta) }
  let(:regra_velha) { create(:automation_rule, account: conta) }
  let(:acoes_velhas) do
    [{ 'action_name' => 'send_message', 'action_params' => ['Olá, cliente@exemplo.com https://exemplo.com'] },
     { 'action_name' => 'assign_team', 'action_params' => ['7'] },
     { 'action_name' => 'add_label', 'action_params' => ['x'], 'chave_abcdefghijklmnopqrstuvwxyz0123456789' => 1 }]
  end

  before do
    regra_boa
    # rubocop:disable Rails/SkipsModelValidations
    regra_velha.update_column(:actions, acoes_velhas)
    # rubocop:enable Rails/SkipsModelValidations
  end

  it 'conta por coluna, conta, erro e ponteiro, sem valor do registro e sem gravar', :aggregate_failures do
    texto = nil
    expect { texto = described_class.new(['AutomationRule']).varrer.relatorio }.not_to(change { regra_velha.reload.updated_at })

    expect(texto).to include('AutomationRule#actions conferidos: 2', 'AutomationRule#actions recusados: 1',
                             "AutomationRule#actions conta #{conta.id}: 1", '/*/action_params/*', '/*/<REDACTED>')
    expect(texto).not_to include('cliente@exemplo.com', 'https://exemplo.com', 'Olá', 'abcdefghijklmnopqrstuvwxyz0123456789')
  end

  it 'não chama valid? nem save' do
    allow_any_instance_of(AutomationRule).to receive(:valid?).and_raise('não pode') # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(AutomationRule).to receive(:save).and_raise('não pode') # rubocop:disable RSpec/AnyInstance

    expect { described_class.new(['AutomationRule']).varrer }.not_to raise_error
  end
end
