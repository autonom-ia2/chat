require 'rails_helper'

# #2594: o "Mudar campos do card" grava o valor de venda só para quem vê os valores (#2075). A tela do card tira o campo
# calada de quem não vê; a automação recusa ao salvar e ao ligar, com a frase, em vez de rodar sem gravar.
RSpec.describe Autonomia::Automacao::CampoProtegido do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:admin_na_conta) { AccountUser.find_by(account: account, user: admin) }
  let(:sem_chave) { pessoa_com(%w[automation_manage crm_manage_pipelines]) }
  let(:com_chave) { pessoa_com(%w[automation_manage crm_manage_pipelines sales_value_view]) }

  def pessoa_com(permissoes)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissoes)
    AccountUser.find_by(account: account, user: user).tap { |account_user| account_user.update!(custom_role: role) }
  end

  it 'acusa o valor no corpo plano e no envelope de quem não vê os valores', :aggregate_failures do
    expect(described_class.sem_permissao('PATCH crm/cards/:id', { 'value_cents' => 100 }, sem_chave)).to eq(%w[value_cents])
    expect(described_class.sem_permissao('PUT crm/cards/:id', { 'card' => { 'value_cents' => 100 } }, sem_chave))
      .to eq(%w[value_cents])
  end

  it 'deixa o valor de quem vê, o corpo sem valor e as outras ações', :aggregate_failures do
    expect(described_class.sem_permissao('PATCH crm/cards/:id', { 'value_cents' => 100 }, com_chave)).to be_empty
    expect(described_class.sem_permissao('PATCH crm/cards/:id', { 'value_cents' => 100 }, admin_na_conta)).to be_empty
    expect(described_class.sem_permissao('PATCH crm/cards/:id', { 'title' => 'Novo' }, sem_chave)).to be_empty
    expect(described_class.sem_permissao('POST crm/cards/:id/close', { 'value_cents' => 100 }, sem_chave)).to be_empty
  end

  describe 'no salvar da receita' do
    def problemas(corpo, account_user)
      passo = { 'id' => 'm1', 'tipo' => 'acao', 'acao' => 'PATCH crm/cards/:id', 'descricao' => 'Mudar campos do card',
                'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => corpo }
      receita = { 'gatilho' => { 'tipo' => 'card.criado' }, 'passos' => [passo] }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: account_user).problemas
    end

    let(:recusa) { I18n.t('autonomia.automacao.receita.campo_protegido', passo: 'm1', campo: 'value_cents') }

    it 'recusa o valor de quem não vê e aceita o de quem vê', :aggregate_failures do
      expect(problemas({ 'value_cents' => 150_000 }, sem_chave)).to include(recusa)
      expect(problemas({ 'value_cents' => 150_000 }, com_chave)).not_to include(recusa)
      expect(problemas({ 'title' => 'Renovação' }, sem_chave)).not_to include(recusa)
    end

    it 'não confere sem pessoa (o catálogo)' do
      expect(problemas({ 'value_cents' => 150_000 }, nil)).not_to include(recusa)
    end
  end
end
