# #2896 (fatia 3): o que os specs do "Desfazer" de "Trazer minha lista" têm em comum. Uma conta com Empresas ligada, duas
# pessoas que ela já tinha e uma planilha pequena (dados inventados) que completa as duas e cria a terceira:
# - Ana já existia, achada pelo telefone: a lista põe o e-mail, a cidade, o plano, a empresa (que a lista cria) e a marca
#   de cliente;
# - Bruno já existia sem nome e sem telefone, achado pelo e-mail: a lista põe o nome, o telefone, a cidade, o plano e a
#   marca de cliente;
# - Carla nasce com a lista, e a empresa dela também.
RSpec.shared_context 'with lista trazida' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  # Colunas: 0 Nome, 1 Celular, 2 E-mail, 3 Empresa, 4 Cidade, 5 Fone 2, 6 Plano.
  let(:planilha) do
    <<~CSV
      Nome,Celular,E-mail,Empresa,Cidade,Fone 2,Plano
      Ana Albuquerino,11987650001,ana.albuquerino@exemplo.com.br,Padaria Bom Dia,Campinas,1133330001,Ouro
      Bruno Brandolim,11987650002,bruno.brandolim@exemplo.com.br,,Santos,,Prata
      Carla Carvalhedo,11987650003,,Mercado Sol,,1133330003,
    CSV
  end
  # A cidade vai para a cidade, o "Fone 2" para o telefone da empresa, e a resposta é "sim, todas são clientes".
  let(:conferencia) { { 'destinos' => { '4' => 'cidade', '5' => 'telefone_da_empresa' }, 'respostas' => { 'clientes' => 'sim_todas' } } }
  let(:ana) { create(:contact, account: account, name: 'Ana A.', phone_number: '+5511987650001') }
  let(:bruno) { create(:contact, account: account, name: '', email: 'bruno.brandolim@exemplo.com.br') }

  # As duas pessoas existem antes de a lista entrar, mesmo no exemplo que não fala delas.
  before do
    account.enable_features!('companies')
    ana
    bruno
  end

  # A lista já gravada. trazer: as marcas da conferência.
  def trazer_lista(texto = planilha, trazer: conferencia, conta: account, quem: user)
    importacao = create_contact_import(account: conta, user: quem, content: texto)
    importacao.update!(options: importacao.options.merge('trazer' => trazer))
    ContactImports::Validator.new(importacao).perform
    import_contacts!(importacao)
  end

  # A importação da tela antiga ("Importar contatos"), sem a marca de "Trazer minha lista": a pessoa escolhe as colunas.
  # texto: uma planilha com Nome, Celular e E-mail, nessa ordem.
  def importar_pela_tela_antiga(texto)
    importacao = create_contact_import(account: account, user: user, content: texto)
    import_contacts!(validate_contact_import(importacao, { 'name' => 0, 'phone' => 1, 'email' => 2, 'company' => nil }))
  end

  def pessoa(nome, conta: account)
    conta.contacts.find_by!(name: nome)
  end

  # Os campos que a lista anotou como preenchidos nesta pessoa (ou na empresa da linha dela).
  def anotados(de_quem)
    Relacionamentos::CampoPreenchido.where(contact_id: de_quem.id).pluck(:campo)
  end

  def previa(importacao)
    Relacionamentos::Trazer::PreviaDoDesfazer.new(importacao.reload).call
  end

  # O clique e o job, um depois do outro.
  def desfazer(importacao, quem: user)
    pedido = Relacionamentos::Trazer::Desfazer.new(importacao).pedir
    raise "o desfazer foi recusado: #{pedido.erro}" if pedido.erro

    Relacionamentos::Trazer::Desfazer.new(importacao.reload, quem: quem).call
    importacao.reload
  end
end
