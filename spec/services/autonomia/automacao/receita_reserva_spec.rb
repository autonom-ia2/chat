require 'rails_helper'

# A reserva da caixa no "avisar" (#2552): o esquema aceita `se_nao_houver: caixa` (e só esse valor), no avisar e no
# resumir em aviso; a Receita recusa a reserva sem o responsável, que é quem ela substitui.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }

  before { account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens', 'automacao_ia') }

  def avisar(para) = { 'id' => 'a1', 'tipo' => 'avisar', 'texto' => ['Oi'], 'para' => para }

  def resumir(para) = { 'id' => 'r1', 'tipo' => 'resumir', 'le' => %w[mensagens_recentes], 'linhas' => 3, 'destino' => { 'avisar' => para } }

  def receita(passo) = { 'gatilho' => { 'tipo' => 'conversa.criada' }, 'passos' => [passo] }

  def problemas(passo) = described_class.new(receita(passo), conta: account).problemas

  def erro(passo) = I18n.t('autonomia.automacao.receita.reserva_sem_responsavel', passo: passo)

  it 'o esquema aceita a reserva da caixa no avisar e no resumir, e só com o valor caixa', :aggregate_failures do
    reserva = { 'responsavel' => true, 'se_nao_houver' => 'caixa' }

    expect(described_class.esquema_valido?(receita(avisar(reserva)))).to be(true)
    expect(described_class.esquema_valido?(receita(resumir(reserva)))).to be(true)
    expect(described_class.esquema_valido?(receita(avisar(reserva.merge('se_nao_houver' => 'time'))))).to be(false)
  end

  it 'a Receita aceita a reserva com o responsável e recusa sem ele', :aggregate_failures do
    expect(problemas(avisar({ 'responsavel' => true, 'se_nao_houver' => 'caixa' }))).to eq([])
    expect(problemas(avisar({ 'pessoas' => [create(:user, account: account).id], 'se_nao_houver' => 'caixa' }))).to eq([erro('a1')])
    expect(problemas(resumir({ 'se_nao_houver' => 'caixa', 'responsavel' => false }))).to include(erro('r1'))
  end
end
