require 'rails_helper'

# #3211 (rodada 1): o Guia nunca grava o login da seguradora (a senha ficaria na conversa) e pede confirmação para
# contratar o agente pronto (a semeadura da base é paga pela conta, e o desfazer não devolve).
RSpec.describe Autonomia::Guide::Acoes do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:guia) { described_class.new(account: conta, user: admin) }
  let(:gravar_acesso) { 'POST autonomia/agents/:agent_id/acesso_da_seguradora' }
  let(:contratar) { 'POST autonomia/contratados/:modelo' }

  it 'gravar o login da seguradora é só na tela: fora do catálogo e do formato, com o caminho da tela', :aggregate_failures do
    expect(described_class::SO_NA_TELA).to include(gravar_acesso => 'acesso_da_seguradora')
    expect(guia.catalogo).not_to include(gravar_acesso)
    expect(Autonomia::Guide::Formatos::RotasDeEscrita.todas.map(&:acao)).not_to include(gravar_acesso)
    I18n.with_locale(:pt_BR) do
      expect { guia.conferir!(gravar_acesso, { 'agent_id' => 1, 'login' => 'corretor.teste', 'senha' => 's3nha-teste' }) }
        .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.only_on_screen.acesso_da_seguradora'))
    end
  end

  it 'contratar está no catálogo e pede confirmação', :aggregate_failures do
    expect(guia.catalogo).to include(contratar)
    expect(described_class::SEM_DESFAZER).to include(contratar)
    expect(guia.desfazivel?(contratar)).to be(false)
  end
end
