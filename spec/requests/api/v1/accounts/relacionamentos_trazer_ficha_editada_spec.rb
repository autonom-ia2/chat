require 'rails_helper'

# #2896 (fatia 3) — editar a ficha de quem a lista criou segura a pessoa no "Desfazer", por qualquer caminho que a tela
# tem para editar: a API de contatos (campo a campo), a gaveta da ficha (que manda o nome da empresa como está escrito) e a
# relação (interessado, parceiro, não é negócio). O resumo "a ficha como a lista deixou"
# (Relacionamentos::Trazer::PessoaCriada) tem de cobrir todos: o que ficar de fora deixa o Desfazer apagar uma pessoa
# que alguém editou. As colunas, uma a uma, são cobradas em spec/services/relacionamentos/trazer/pessoa_criada_spec.rb.
#
# A lista dos campos da API sai do próprio controller, e não de uma cópia: o que `permitted_params` pede ao `permit` e o
# que o Enterprise acrescenta por fora dele (a empresa). O campo que a API passar a aceitar e não tiver uma edição aqui
# quebra o primeiro exemplo.
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
  # Uma pessoa por edição, na ordem das edições, e uma a mais, em quem ninguém mexe.
  let(:telefones) { Array.new(edicoes.size + 1) { |indice| format('119876501%02d', indice) } }
  let(:nomes) { %w[Alfa Beta Gama Delta Epsilon Zeta Eta Teta Iota Kapa] }
  let(:planilha_das_pessoas) do
    linhas = telefones.each_with_index.map { |telefone, indice| "Pessoa #{nomes.fetch(indice)},#{telefone}" }
    "Nome,Celular\n#{linhas.join("\n")}\n"
  end
  # Quatro pessoas que a lista cria na mesma empresa, que também nasce com a lista, e uma sem empresa.
  let(:planilha_da_gaveta) do
    <<~CSV
      Nome,Celular,Empresa
      Pessoa Digitada,11987650201,Mercado Sol
      Pessoa Apagada,11987650205,Mercado Sol
      Pessoa Salva,11987650202,Mercado Sol
      Pessoa Parceira,11987650203,Mercado Sol
      Pessoa Intocada,11987650204,
    CSV
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
    devolvidos = com_a_conta_em_vigor { controller.send(:permitted_params).keys }
    (pedidos.flat_map { |filtro| filtro.is_a?(Hash) ? filtro.keys : [filtro] }.map(&:to_s) + devolvidos).uniq
  end

  # O Enterprise lê a conta em `Current.account`. Só ela é mexida, e volta a ser a de antes.
  def com_a_conta_em_vigor
    conta_de_antes = Current.account
    Current.account = account
    yield
  ensure
    Current.account = conta_de_antes
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

    editadas.each do |campo, quem|
      expect(criada.tocadas([quem.id])).to contain_exactly(quem.id), "editar #{campo} não mudou o resumo da ficha"
    end
    expect(criada.tocadas([intocada.id])).to be_empty
    expect(previa(importacao)).to eq(tira: 1, ficam: edicoes.size, devolve: 0)

    desfazer(importacao)

    expect(account.contacts.where(id: editadas.values.map(&:id)).count).to eq(edicoes.size)
    expect(account.contacts.exists?(intocada.id)).to be(false)
  end

  describe 'a gaveta da ficha e a relação' do
    # O que a gaveta manda ao salvar (relacionamentos/ficha/informacoes.js#dadosParaSalvar): a ficha inteira, com o nome
    # da empresa como está escrito no campo e os campos vazios em branco.
    def salvar_pela_gaveta(quem, empresa:)
      editar(quem, { name: quem.name, phone_number: quem.phone_number, email: nil, custom_attributes: {},
                     additional_attributes: { city: '', company_name: empresa, social_profiles: {} } })
    end

    def marcar_relacao(quem, relacao)
      rota = "/api/v1/accounts/#{account.id}/crm/contacts/#{quem.id}/relacao"
      with_modified_env(CRM_KANBAN_ENABLED: 'true') do
        put rota, params: { relacao: relacao }, headers: user.create_new_auth_token, as: :json
      end
      expect(response).to have_http_status(:success)
    end

    it 'o nome da empresa trocado ou apagado e a relação mudada seguram a pessoa; salvar a gaveta sem mudar nada não segura' do
      account.enable_features!('contato_relacao')
      importacao = trazer_lista(planilha_da_gaveta, trazer: {})
      criada = Relacionamentos::Trazer::PessoaCriada.new(importacao)
      nomes_da_gaveta = ['Pessoa Digitada', 'Pessoa Apagada', 'Pessoa Salva', 'Pessoa Parceira', 'Pessoa Intocada']
      digitada, apagada, salva, parceira, intocada = nomes_da_gaveta.map { |nome| pessoa(nome) }
      todas = [digitada, apagada, salva, parceira, intocada].map(&:id)
      # A lista ligou a pessoa à empresa, e o nome da empresa ficou escrito na ficha: é o que a gaveta mostra no campo.
      expect(salva.additional_attributes).to include('company_name' => 'Mercado Sol')
      expect(previa(importacao)).to eq(tira: 5, ficam: 0, devolve: 0)

      salvar_pela_gaveta(digitada, empresa: 'Mercado do Sol Nascente')
      salvar_pela_gaveta(apagada, empresa: '')
      salvar_pela_gaveta(salva, empresa: 'Mercado Sol')
      marcar_relacao(parceira, 'parceiro')

      expect(digitada.reload.additional_attributes).to include('company_name' => 'Mercado do Sol Nascente')
      expect(apagada.reload.additional_attributes['company_name']).to be_blank
      expect(parceira.reload).to be_relacao_parceiro
      expect(criada.tocadas(todas)).to contain_exactly(digitada.id, apagada.id, parceira.id)
      expect(previa(importacao)).to eq(tira: 2, ficam: 3, devolve: 0)

      desfazer(importacao)

      expect(account.contacts.where(id: todas).ids).to contain_exactly(digitada.id, apagada.id, parceira.id)
    end
  end
end
