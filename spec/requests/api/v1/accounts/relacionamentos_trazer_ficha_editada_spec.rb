require 'rails_helper'

# #2896 (fatia 3) — editar a ficha de quem a lista criou segura a pessoa no "Desfazer", por qualquer campo que a API de
# contatos aceita gravar. O resumo "a ficha como a lista deixou" (Relacionamentos::Trazer::PessoaCriada) tem de cobrir
# todos: o campo que ficar de fora deixa o Desfazer apagar uma pessoa que alguém editou.
#
# A lista dos campos sai do próprio controller, e não de uma cópia: o que `permitted_params` pede ao `permit` e o que o
# Enterprise acrescenta por fora dele (a empresa). O campo que a API passar a aceitar e não tiver uma edição aqui quebra
# o primeiro exemplo.
RSpec.describe 'Trazer minha lista: a ficha editada pela API segura a pessoa (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with lista trazida'

  let(:oficina) { account.companies.create!(name: 'Oficina Central') }
  # Uma edição por campo aceito: o corpo do PATCH de contatos.
  let(:edicoes) do
    {
      'name' => { name: 'Pessoa Renomeada' },
      'identifier' => { identifier: 'cliente-0042' },
      'email' => { email: 'pessoa.editada@exemplo.com.br' },
      'phone_number' => { phone_number: '+5511987650199' },
      'blocked' => { blocked: true },
      'company_id' => { company_id: oficina.id },
      'additional_attributes' => { additional_attributes: { description: 'Prefere ligação à tarde' } },
      'custom_attributes' => { custom_attributes: { plano: 'Ouro' } }
    }
  end
  # A foto fica de fora de propósito (#3005): não é coluna da ficha, e trocar a foto não segura a pessoa.
  let(:de_fora) { %w[avatar avatar_url] }
  # O bloqueio segura por outra regra (Relacionamentos::Trazer::QuemFica), não pelo resumo da ficha.
  let(:fora_do_resumo) { %w[blocked] }
  # Uma pessoa por edição, na ordem das edições, e uma a mais, em quem ninguém mexe.
  let(:telefones) { Array.new(edicoes.size + 1) { |indice| format('119876501%02d', indice) } }
  let(:nomes) { %w[Alfa Beta Gama Delta Epsilon Zeta Eta Teta Iota Kapa] }
  let(:planilha_das_pessoas) do
    linhas = telefones.each_with_index.map { |telefone, indice| "Pessoa #{nomes.fetch(indice)},#{telefone}" }
    "Nome,Celular\n#{linhas.join("\n")}\n"
  end

  # Os nomes que `permitted_params` pede ao `permit`, lidos da chamada de verdade, mais o que ele devolve além disso
  # quando o pedido traz a empresa (Enterprise::Api::V1::Accounts::ContactsController).
  def aceitos_pela_api
    pedidos = []
    controller = Api::V1::Accounts::ContactsController.new
    controller.params = ActionController::Parameters.new(company_id: oficina.id)
    allow(controller.params).to receive(:permit).and_wrap_original do |original, *filtros|
      pedidos.concat(filtros)
      original.call(*filtros)
    end
    devolvidos = Current.set(account: account) { controller.send(:permitted_params).keys }
    (pedidos.flat_map { |filtro| filtro.is_a?(Hash) ? filtro.keys : [filtro] }.map(&:to_s) + devolvidos).uniq
  end

  def da_linha(indice)
    account.contacts.find_by!(phone_number: "+55#{telefones.fetch(indice)}")
  end

  def editar(quem, corpo)
    patch "/api/v1/accounts/#{account.id}/contacts/#{quem.id}", params: corpo, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'cada campo que a API de contatos aceita gravar tem uma edição aqui, ou está de fora com o motivo escrito' do
    expect(aceitos_pela_api).to match_array(edicoes.keys + de_fora)
  end

  it 'editar qualquer um desses campos pela API segura a pessoa que a lista criou; a intocada sai' do
    importacao = trazer_lista(planilha_das_pessoas, trazer: {})
    criada = Relacionamentos::Trazer::PessoaCriada.new(importacao)
    intocada = da_linha(edicoes.size)
    expect(previa(importacao)).to eq(tira: telefones.size, ficam: 0, devolve: 0)

    editadas = edicoes.each_with_index.to_h do |(campo, corpo), indice|
      quem = da_linha(indice)
      editar(quem, corpo)
      [campo, quem]
    end

    editadas.except(*fora_do_resumo).each do |campo, quem|
      expect(criada.tocadas([quem.id])).to contain_exactly(quem.id), "editar #{campo} não mudou o resumo da ficha"
    end
    expect(criada.tocadas([intocada.id])).to be_empty
    expect(previa(importacao)).to eq(tira: 1, ficam: edicoes.size, devolve: 0)

    desfazer(importacao)

    expect(account.contacts.where(id: editadas.values.map(&:id)).count).to eq(edicoes.size)
    expect(account.contacts.exists?(intocada.id)).to be(false)
  end
end
