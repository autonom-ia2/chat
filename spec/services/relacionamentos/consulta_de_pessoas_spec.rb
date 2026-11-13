require 'rails_helper'

# #2894 — a consulta da aba Pessoas da Lista nova de Relacionamentos. A regra é a da demonstração da tela
# (relacionamentos/fonte/grupos.js e listaFonte.js): os mesmos dados dão o mesmo grupo, busca, filtro, ordem e página.
RSpec.describe Relacionamentos::ConsultaDePessoas do
  let(:account) { create(:account) }
  let(:agora) { Time.zone.parse('2026-11-11 12:00:00') }

  before { travel_to(agora) }

  def pessoa(nome, **dados)
    create(:contact, account: account, name: nome, contact_type: :lead, **dados)
  end

  def consulta(**pedido)
    described_class.new(account, pedido)
  end

  def nomes(**pedido)
    consulta(**pedido).itens.map(&:name)
  end

  def consultas_feitas(&)
    feitas = 0
    contar = ->(*, dados) { feitas += 1 unless dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name]) }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    feitas
  end

  describe 'quem entra na lista' do
    # Ao salvar, o contato com telefone vira lead (Contacts::SyncAttributes); o tipo antigo só existe em dado já gravado.
    def visitante(nome, **dados)
      contato = create(:contact, account: account, name: nome, **dados)
      contato.update_columns(contact_type: 0) # rubocop:disable Rails/SkipsModelValidations
    end

    before do
      pessoa('Ana Albuquerino')
      visitante('Visitante do site')
      visitante('Visitante com telefone', phone_number: '+5511910310001')
    end

    it 'usa a mesma base da lista de contatos de hoje: visitante anônimo fica de fora' do
      expect(nomes).to contain_exactly('Ana Albuquerino', 'Visitante com telefone')
    end

    it 'com o CRM novo ligado, só lead e cliente, como a lista de contatos de hoje' do
      account.enable_features!('crm_v2')

      expect(nomes).to contain_exactly('Ana Albuquerino')
    end
  end

  describe 'isolamento entre contas' do
    it 'nunca mostra gente de outra conta, nem na lista, nem na contagem, nem em "todas"' do
      pessoa('Ana Albuquerino')
      create(:contact, account: create(:account), name: 'Ana de outra conta', contact_type: :customer)

      expect(nomes).to contain_exactly('Ana Albuquerino')
      expect(consulta.contagens).to include('todos' => 1, 'clientes' => 0)
      expect(consulta.todos.pluck(:name)).to contain_exactly('Ana Albuquerino')
    end
  end

  describe 'grupos' do
    it 'separa quem falou há pouco de quem sumiu nos limites exatos de 30 e 90 dias' do
      { 'há 29 dias' => 29.days, 'há 30 dias' => 30.days, 'há 30 dias e 1 segundo' => 30.days + 1.second,
        'há 31 dias' => 31.days, 'há 89 dias' => 89.days, 'há 90 dias' => 90.days,
        'há 90 dias e 1 segundo' => 90.days + 1.second, 'há 91 dias' => 91.days }.each do |nome, tempo|
        pessoa(nome, last_activity_at: agora - tempo)
      end
      pessoa('nunca conversou')

      expect(nomes(grupo: 'falou_ha_pouco')).to contain_exactly('há 29 dias', 'há 30 dias')
      expect(nomes(grupo: 'sumiu_1_a_3_meses'))
        .to contain_exactly('há 30 dias e 1 segundo', 'há 31 dias', 'há 89 dias', 'há 90 dias')
      expect(nomes(grupo: 'sumiu_mais_de_3_meses')).to contain_exactly('há 90 dias e 1 segundo', 'há 91 dias')
      expect(nomes(grupo: 'nunca_conversou')).to contain_exactly('nunca conversou')
    end

    it 'cliente e "não quer mensagens" cruzam com os grupos de conversa' do
      pessoa('Cliente que sumiu', contact_type: :customer, last_activity_at: agora - 40.days)
      pessoa('Recusou e nunca falou', opted_out_at: agora - 3.days, opt_out_source: 'manual')
      pessoa('Só lead', last_activity_at: agora - 1.day)

      expect(nomes(grupo: 'clientes')).to contain_exactly('Cliente que sumiu')
      expect(nomes(grupo: 'nao_quer_mensagens')).to contain_exactly('Recusou e nunca falou')
      expect(nomes(grupo: 'sumiu_1_a_3_meses')).to contain_exactly('Cliente que sumiu')
      expect(nomes(grupo: 'nunca_conversou')).to contain_exactly('Recusou e nunca falou')
      expect(nomes(grupo: 'todos')).to contain_exactly('Cliente que sumiu', 'Recusou e nunca falou', 'Só lead')
    end

    it 'sem grupo, mostra todos' do
      pessoa('Ana Albuquerino')
      pessoa('Bruno Brandolim', last_activity_at: agora - 200.days)

      expect(nomes).to contain_exactly('Ana Albuquerino', 'Bruno Brandolim')
      expect(nomes(grupo: '')).to contain_exactly('Ana Albuquerino', 'Bruno Brandolim')
    end
  end

  describe 'busca' do
    before do
      pessoa('João Albuquerino', email: 'joao.albuquerino@exemplo.com.br', phone_number: '+5511910310001',
                                 custom_attributes: { cpf: '123.456.789-00' })
      pessoa('Nádia Brandolim', email: 'nadia@exemplo.com.br', phone_number: '+5511910310002',
                                additional_attributes: { company_name: 'Padaria Pão de Açúcar' })
      pessoa('Loja 0002', custom_attributes: { cpf: '98765432100' })
    end

    it 'acha pelo nome sem acento e sem maiúscula, nos dois sentidos' do
      expect(nomes(busca: 'joao')).to contain_exactly('João Albuquerino')
      expect(nomes(busca: '  JOÃO alb ')).to contain_exactly('João Albuquerino')
      expect(nomes(busca: 'nadia')).to contain_exactly('Nádia Brandolim')
    end

    it 'acha pelo e-mail' do
      expect(nomes(busca: 'nadia@exemplo')).to contain_exactly('Nádia Brandolim')
    end

    it 'acha pela empresa' do
      expect(nomes(busca: 'pao de acucar')).to contain_exactly('Nádia Brandolim')
    end

    it 'acha pelo telefone comparando só os dígitos' do
      expect(nomes(busca: '(11) 91031-0001')).to contain_exactly('João Albuquerino')
      expect(nomes(busca: '910310002')).to contain_exactly('Nádia Brandolim')
    end

    it 'acha pelo CPF com ou sem pontuação' do
      expect(nomes(busca: '12345678900')).to contain_exactly('João Albuquerino')
      expect(nomes(busca: '123.456.789-00')).to contain_exactly('João Albuquerino')
      expect(nomes(busca: '987.654.321-00')).to contain_exactly('Loja 0002')
    end

    it 'só número não procura no nome, como na tela' do
      expect(nomes(busca: '0002')).to contain_exactly('Nádia Brandolim')
    end

    it 'sem letra nem número não acha ninguém' do
      expect(nomes(busca: '---')).to be_empty
      expect(consulta(busca: '---').contagens).to include('todos' => 0)
    end

    it 'trata % e _ como texto, não como curinga' do
      expect(nomes(busca: 'jo_o')).to be_empty
      expect(nomes(busca: 'j%o')).to be_empty
    end
  end

  describe 'filtros' do
    let(:empresa) { create(:company, account: account, name: 'Mercearia Ourivesco') }

    before do
      pessoa('Da empresa', company_id: empresa.id)
      pessoa('Com etiqueta').update_labels(%w[feira site])
      pessoa('De Campinas', additional_attributes: { city: 'Campinas' })
      pessoa('Chegou há 7 dias', created_at: agora - 7.days)
      pessoa('Chegou há 8 dias', created_at: agora - 8.days)
      pessoa('Chegou há 31 dias', created_at: agora - 31.days)
      pessoa('Chegou há 91 dias', created_at: agora - 91.days)
    end

    it 'filtra por empresa' do
      expect(nomes(filtros: { empresa: empresa.id.to_s })).to contain_exactly('Da empresa')
    end

    it 'filtra por etiqueta, pelo nome exato' do
      expect(nomes(filtros: { etiqueta: 'feira' })).to contain_exactly('Com etiqueta')
      expect(nomes(filtros: { etiqueta: 'feir' })).to be_empty
    end

    it 'filtra por cidade' do
      expect(nomes(filtros: { cidade: 'Campinas' })).to contain_exactly('De Campinas')
    end

    it 'filtra por quando chegou, com o dia do limite dentro' do
      chegaram = ['Da empresa', 'Com etiqueta', 'De Campinas', 'Chegou há 7 dias']

      expect(nomes(filtros: { chegou_em: 'ultimos_7' })).to match_array(chegaram)
      expect(nomes(filtros: { chegou_em: 'ultimos_30' })).to match_array(chegaram + ['Chegou há 8 dias'])
      expect(nomes(filtros: { chegou_em: 'ultimos_90' })).to match_array(chegaram + ['Chegou há 8 dias', 'Chegou há 31 dias'])
    end

    it 'filtro vazio quer dizer qualquer' do
      expect(consulta(filtros: { empresa: '', etiqueta: '', cidade: '', chegou_em: '' }).total).to eq(7)
    end

    it 'junta filtros, busca e grupo' do
      pessoa('Cliente de Campinas', contact_type: :customer, additional_attributes: { city: 'Campinas' })

      expect(nomes(grupo: 'clientes', busca: 'campinas', filtros: { cidade: 'Campinas' })).to contain_exactly('Cliente de Campinas')
    end
  end

  describe 'ordem' do
    before do
      pessoa('Érica', last_activity_at: agora - 2.days, created_at: agora - 9.days)
      pessoa('ana', last_activity_at: agora - 1.day, created_at: agora - 8.days)
      pessoa('Bruno', created_at: agora - 1.day)
      pessoa('Ana', last_activity_at: agora - 2.days, created_at: agora - 3.days)
    end

    it 'por padrão, a última conversa primeiro; quem nunca conversou no fim e o empate pela ordem de chegada' do
      expect(nomes).to eq(%w[ana Érica Ana Bruno])
      expect(nomes(ordem: 'ultima_conversa')).to eq(%w[ana Érica Ana Bruno])
    end

    it 'por nome, sem diferença de acento nem de maiúscula' do
      expect(nomes(ordem: 'nome')).to eq(%w[ana Ana Bruno Érica])
    end

    it 'os mais novos primeiro' do
      expect(nomes(ordem: 'mais_novos')).to eq(%w[Bruno Ana ana Érica])
    end
  end

  describe 'página' do
    before do
      stub_const('Relacionamentos::Consulta::POR_PAGINA', 2)
      %w[Ana Bruno Carla Diego Elisa].each { |nome| pessoa(nome) }
    end

    it 'devolve uma página por vez, com o total e se tem mais' do
      primeira = consulta(ordem: 'nome', pagina: '1')
      terceira = consulta(ordem: 'nome', pagina: '3')

      expect(primeira.itens.map(&:name)).to eq(%w[Ana Bruno])
      expect([primeira.total, primeira.tem_mais?]).to eq([5, true])
      expect(terceira.itens.map(&:name)).to eq(%w[Elisa])
      expect([terceira.total, terceira.tem_mais?]).to eq([5, false])
    end

    it 'página além do fim vem vazia, com o total certo' do
      alem = consulta(pagina: '9')

      expect(alem.itens).to be_empty
      expect([alem.total, alem.tem_mais?]).to eq([5, false])
    end

    it 'no empate da última conversa, as páginas juntas não repetem nem pulam ninguém' do
      mesma_hora = agora - 3.days
      empatados = %w[Fábio Gabriela Hugo].map { |nome| pessoa(nome, last_activity_at: mesma_hora) }
      paginas = %w[1 2].flat_map { |pagina| consulta(grupo: 'falou_ha_pouco', pagina: pagina).itens.map(&:id) }

      expect(paginas).to eq(empatados.map(&:id))
    end

    it 'no empate do nome, as páginas juntas não repetem nem pulam ninguém' do
      xaras = Array.new(3) { pessoa('Zambelli') }
      paginas = %w[1 2].flat_map { |pagina| consulta(busca: 'zambelli', ordem: 'nome', pagina: pagina).itens.map(&:id) }

      expect(paginas).to eq(xaras.map(&:id))
    end

    it '"todas" ignora a página e traz só o que as ações em grupo leem' do
      todas = consulta(ordem: 'nome', pagina: '2').todos

      expect(todas.pluck(:name)).to eq(%w[Ana Bruno Carla Diego Elisa])
      expect(todas.first.keys).to eq(%i[id name phone_number blocked opted_out_at])
    end
  end

  describe 'contagens' do
    let(:pedido) { { busca: 'brandolim', filtros: { cidade: 'Campinas' } } }
    let(:esperado) do
      { 'todos' => 5, 'clientes' => 2, 'falou_ha_pouco' => 1, 'sumiu_1_a_3_meses' => 2, 'sumiu_mais_de_3_meses' => 1,
        'nunca_conversou' => 1, 'nao_quer_mensagens' => 1 }
    end

    before do
      de_campinas = { additional_attributes: { city: 'Campinas' } }
      pessoa('Ana Brandolim', last_activity_at: agora - 5.days, contact_type: :customer, **de_campinas)
      pessoa('Bruno Brandolim', last_activity_at: agora - 45.days, contact_type: :customer, **de_campinas)
      pessoa('Carla Brandolim', last_activity_at: agora - 60.days, **de_campinas)
      pessoa('Diego Brandolim', last_activity_at: agora - 120.days, **de_campinas)
      pessoa('Elisa Brandolim', opted_out_at: agora - 2.days, opt_out_source: 'manual', **de_campinas)
      pessoa('Fábio Brandolim', last_activity_at: agora - 5.days, additional_attributes: { city: 'Santos' })
      pessoa('Gabriela Carvalhedo', last_activity_at: agora - 5.days, **de_campinas)
    end

    it 'conta cada grupo respeitando a busca e os filtros' do
      expect(consulta(**pedido).contagens).to eq(esperado)
    end

    it 'o número de cada grupo é o total da lista daquele grupo' do
      contagens = consulta(**pedido).contagens

      esperado.each_key do |grupo|
        expect(consulta(grupo: grupo, **pedido).total).to eq(contagens.fetch(grupo)), "grupo #{grupo}"
      end
    end

    it 'faz uma consulta só' do
      contando = consulta(**pedido)

      expect(consultas_feitas { contando.contagens }).to eq(1)
    end
  end

  describe 'pedido inválido' do
    let(:alem_do_teto) { (Relacionamentos::Consulta::PAGINA_MAXIMA + 1).to_s }

    it 'recusa grupo, ordem, página, período e empresa que não existem, dizendo qual' do
      { { grupo: 'vips' } => 'grupo desconhecido: vips', { ordem: 'aleatoria' } => 'ordem desconhecida: aleatoria',
        { pagina: '0' } => 'pagina inválida: 0', { pagina: 'dois' } => 'pagina inválida: dois',
        { pagina: '99999999999999999999' } => 'pagina inválida: 99999999999999999999',
        { pagina: alem_do_teto } => "pagina inválida: #{alem_do_teto}",
        { filtros: { chegou_em: 'ontem' } } => 'chegou_em desconhecido: ontem',
        { filtros: { empresa: 'abc' } } => 'empresa inválida: abc' }.each do |pedido, mensagem|
        expect { consulta(**pedido) }.to raise_error(Relacionamentos::PedidoInvalido, mensagem)
      end
    end
  end

  it 'aceita até a última página que cabe no banco' do
    ultima = consulta(pagina: Relacionamentos::Consulta::PAGINA_MAXIMA.to_s)

    expect(ultima.itens.to_a).to be_empty
    expect(ultima.tem_mais?).to be(false)
  end

  describe 'o que vem carregado com cada pessoa' do
    it 'não faz uma consulta por pessoa para etiquetas e foto' do
      3.times { |n| pessoa("Pessoa #{n}").update_labels(%w[feira]) }
      ler = -> { consulta.itens.each { |item| [item.label_taggings.map(&:tag), item.avatar.attached?] } }
      com_tres = consultas_feitas(&ler)
      4.times { |n| pessoa("Outra #{n}").update_labels(%w[site]) }

      expect(consultas_feitas(&ler)).to eq(com_tres)
    end
  end

  # E4 (#2897) — o que a carteira de seguros soma à lista (Carteira::NaListaDePessoas). Tudo fictício.
  describe 'na conta com a carteira de seguros' do
    # 11/11/2026, 9h em São Paulo: para a conta, hoje é dia 11.
    let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo') }
    let(:hoje) { Date.new(2026, 11, 11) }

    def com_seguros(nome, *seguros)
      pessoa(nome).tap { |dona| seguros.each { |campos| criar_apolice(dona, **campos) } }
    end

    describe 'o grupo "Só tem um seguro"' do
      let(:ativo) { { fim_vigencia: hoje + 200 } }
      let(:vencido) { { fim_vigencia: hoje - 1 } }
      let(:cancelado) { { fim_vigencia: hoje + 200, cancelado_em: agora - 3.days } }
      let(:com_um) { ['Um ativo', 'Ativo e vencido', 'Ativo e cancelado', 'Vence hoje'] }

      before do
        com_seguros('Um ativo', ativo)
        com_seguros('Dois ativos', ativo, ativo)
        com_seguros('Ativo e vencido', ativo, vencido)
        com_seguros('Ativo e cancelado', ativo, cancelado)
        com_seguros('Vence hoje', { fim_vigencia: hoje })
        com_seguros('Só vencido', vencido)
        com_seguros('Só cancelado', cancelado)
        pessoa('Sem seguro')
      end

      it 'traz quem tem exatamente um seguro valendo: cancelado e vencido não contam' do
        expect(nomes(grupo: 'so_um_seguro')).to match_array(com_um)
      end

      it 'entra na contagem dos grupos, com o mesmo número da lista e na mesma consulta' do
        contando = consulta

        expect(contando.contagens).to include('todos' => 8, 'so_um_seguro' => 4)
        expect(consulta(grupo: 'so_um_seguro').total).to eq(4)
        expect(consultas_feitas { contando.contagens }).to eq(1)
      end

      it 'cruza com a busca, os filtros e "Marcar todas"' do
        expect(nomes(grupo: 'so_um_seguro', busca: 'ativo e')).to contain_exactly('Ativo e vencido', 'Ativo e cancelado')
        expect(consulta(grupo: 'so_um_seguro').todos.pluck(:name)).to match_array(com_um)
      end

      it 'vira o dia no fuso da conta: às 22h de São Paulo o seguro que vence hoje ainda conta' do
        travel_to(Time.utc(2026, 11, 12, 1))

        expect(nomes(grupo: 'so_um_seguro')).to include('Vence hoje')

        travel_to(Time.utc(2026, 11, 12, 4))

        expect(nomes(grupo: 'so_um_seguro')).not_to include('Vence hoje')
      end

      it 'não conta seguro de outra conta' do
        outra = conta_com_carteira
        de_fora = create(:contact, account: outra, name: 'Um ativo de fora', contact_type: :customer)
        criar_apolice(de_fora, **ativo)

        expect(nomes(grupo: 'so_um_seguro')).to match_array(com_um)
        expect(described_class.new(outra, grupo: 'so_um_seguro').itens.map(&:name)).to eq(['Um ativo de fora'])
      end
    end

    describe 'a busca pelos seguros' do
      before do
        com_seguros('Marina Exemplo', { numero: 'EX-001234', bem: 'Carro Exemplo 2022 placa ABC1D23' })
        com_seguros('Bruno Exemplo', { numero: 'EX-005678', bem: 'Apartamento na Praça Açaí' }, { numero: 'ZZ 9090', bem: nil })
        pessoa('Carla Sem Seguro', phone_number: '+5511910310001')
      end

      it 'acha a pessoa pelo número da apólice, com ou sem pontuação e só pelos dígitos' do
        expect(nomes(busca: 'EX-001234')).to contain_exactly('Marina Exemplo')
        expect(nomes(busca: 'ex001234')).to contain_exactly('Marina Exemplo')
        expect(nomes(busca: '001234')).to contain_exactly('Marina Exemplo')
        expect(nomes(busca: 'zz 9090')).to contain_exactly('Bruno Exemplo')
        expect(nomes(busca: 'ex-00')).to contain_exactly('Marina Exemplo', 'Bruno Exemplo')
      end

      it 'acha pelo texto do bem segurado, sem acento, e pela placa que estiver nele' do
        expect(nomes(busca: 'carro exemplo')).to contain_exactly('Marina Exemplo')
        expect(nomes(busca: 'abc1d23')).to contain_exactly('Marina Exemplo')
        expect(nomes(busca: 'praca acai')).to contain_exactly('Bruno Exemplo')
      end

      it 'continua achando pelo que a lista já procurava, e só número não procura no bem' do
        expect(nomes(busca: 'carla')).to contain_exactly('Carla Sem Seguro')
        expect(nomes(busca: '910310001')).to contain_exactly('Carla Sem Seguro')
        expect(nomes(busca: '2022')).to be_empty
        expect(nomes(busca: '---')).to be_empty
      end

      it 'a contagem dos grupos acompanha a busca pelos seguros' do
        expect(consulta(busca: 'EX-00').contagens).to include('todos' => 2, 'so_um_seguro' => 1)
      end

      it 'trata % e _ como texto, não como curinga' do
        expect(nomes(busca: 'EX_001234')).to be_empty
        expect(nomes(busca: 'EX%1234')).to be_empty
      end

      it 'não acha pessoa pelo seguro de outra conta' do
        outra = conta_com_carteira
        criar_apolice(create(:contact, account: outra, name: 'Dona de fora', contact_type: :customer), numero: 'FORA-4242')

        expect(nomes(busca: 'FORA-4242')).to be_empty
        expect(described_class.new(outra, busca: 'EX-001234').itens).to be_empty
      end
    end

    describe 'com a carteira desligada' do
      # A conta já tem seguros gravados; desligar a chave tem de devolver a lista de antes, inteira.
      before do
        com_seguros('Marina Exemplo', { numero: 'EX-001234', bem: 'Carro Exemplo 2022' })
        account.disable_features!('carteira_seguros')
      end

      def sql_de(&)
        feitas = []
        guardar = ->(*, dados) { feitas << dados[:sql] unless dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name]) }
        ActiveSupport::Notifications.subscribed(guardar, 'sql.active_record', &)
        feitas
      end

      it 'a lista não tem o grupo nem procura nos seguros' do
        expect(consulta.contagens.keys).to eq(described_class::GRUPOS.keys)
        expect { consulta(grupo: 'so_um_seguro') }.to raise_error(Relacionamentos::PedidoInvalido, 'grupo desconhecido: so_um_seguro')
        expect(nomes(busca: 'EX-001234')).to be_empty
        expect(nomes(busca: 'carro exemplo')).to be_empty
        expect(nomes(busca: 'marina')).to contain_exactly('Marina Exemplo')
      end

      it 'a consulta é a mesma de antes da carteira, letra por letra' do
        de_antes = described_class.base(account).where('TRUE').order(Arel.sql(Relacionamentos::Consulta.por_nome('contacts')))
                                  .offset(0).limit(Relacionamentos::Consulta::POR_PAGINA)

        expect(consulta(ordem: 'nome').itens.to_sql).to eq(de_antes.to_sql)
      end

      it 'faz o mesmo número de consultas de antes e nenhuma toca nos seguros' do
        lendo = consulta(busca: 'marina')
        feitas = { contagens: sql_de { lendo.contagens }, total: sql_de { lendo.total }, todos: sql_de { lendo.todos } }

        expect(feitas.transform_values(&:size)).to eq(contagens: 1, total: 1, todos: 1)
        expect(feitas.values.flatten.select { |sql| sql.include?('carteira_apolices') }).to be_empty
      end
    end
  end
end
