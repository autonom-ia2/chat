require 'rails_helper'

# E4 (#2897) — as leituras da carteira de seguros, no formato que a tela lê: a aba Seguros (página, grupos, busca,
# filtros, ordem), um seguro, a história dele e os seguros da ficha da pessoa. As escritas ficam em
# relacionamentos_seguros_escritas_spec.rb; a metade de função personalizada e a ficha da empresa, em
# spec/enterprise/requests/relacionamentos/seguros_spec.rb. Tudo fictício.
RSpec.describe 'Carteira de seguros: leituras', type: :request do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:marina) { pessoa('Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) do
    criar_apolice(marina, numero: 'EX-001234', inicio_vigencia: Date.new(2025, 12, 16), fim_vigencia: Date.new(2026, 12, 16),
                          valor_centavos: 341_000, bem: 'Carro Exemplo 2022')
  end
  let(:leituras_sem_seguro) { %w[seguros seguros/todos seguros/contagens seguros/resumo seguros/opcoes_de_filtro] }
  let(:leituras_de_um) { ["seguros/#{seguro.id}", "seguros/#{seguro.id}/historia", "pessoas/#{marina.id}/seguros"] }
  let(:leituras) { leituras_sem_seguro + leituras_de_um }

  before do
    travel_to(agora)
    seguro
  end

  def pessoa(nome, conta: account, **dados)
    create(:contact, account: conta, name: nome, contact_type: :customer, **dados)
  end

  def ler(caminho, quem: agente, **params)
    get "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token
  end

  def itens(**params)
    ler('seguros', **params)
    response.parsed_body['itens']
  end

  def numeros(**params)
    itens(**params).pluck('numero')
  end

  describe 'em todas as leituras' do
    it 'responde 401 sem login' do
      leituras.each do |caminho|
        get "#{base}/#{caminho}"

        expect(response).to have_http_status(:unauthorized), caminho
      end
    end

    it 'atende o agente comum e o administrador' do
      [agente, admin].each do |quem|
        leituras.each do |caminho|
          ler(caminho, quem: quem)

          expect(response).to have_http_status(:ok), "#{caminho} (#{quem.id})"
        end
      end
    end

    it 'responde 404 com a chave da carteira desligada, e também sem as telas novas de Relacionamentos' do
      %w[carteira_seguros relacionamentos_novo].each do |chave|
        account.disable_features!(chave)

        (leituras + ["seguros/#{seguro.id}/pdf"]).each do |caminho|
          ler(caminho)

          expect(response).to have_http_status(:not_found), "#{caminho} sem #{chave}"
        end
        account.enable_features!(chave)
      end
    end

    it 'responde 404 em conta fora do segmento: nicho geral e seguros que não é corretora' do
      [%w[geral], %w[seguros saude_beneficios]].each do |nicho, perfil|
        Autonomia::Agents::Nicho.atribuir(account, nicho: nicho, perfil: perfil)
        account.save!

        (leituras + ["seguros/#{seguro.id}/pdf"]).each do |caminho|
          ler(caminho)

          expect(response).to have_http_status(:not_found), "#{caminho} em #{nicho}"
        end
      end
    end

    it 'diz no payload da conta se ela tem a carteira' do
      tem = lambda do
        get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token
        response.parsed_body['carteira_seguros']
      end

      expect(tem.call).to be(true)
      account.disable_features!('carteira_seguros')
      expect(tem.call).to be(false)
    end
  end

  describe 'isolamento entre contas' do
    let(:outra_conta) { conta_com_carteira }
    let(:de_fora) { pessoa('Bruno de Outra Conta', conta: outra_conta) }
    let!(:seguro_de_fora) { guardar_pdf_na(criar_apolice(de_fora, numero: 'EX-777777')) }

    it 'responde 404 para o seguro, a história e o PDF de outra conta, e para o que não existe' do
      partes = ['', '/historia', '/pdf']

      [seguro_de_fora.id, 0].each do |id|
        partes.each do |parte|
          ler("seguros/#{id}#{parte}", quem: admin)

          expect(response).to have_http_status(:not_found), "#{id}#{parte}"
        end
      end
    end

    it 'responde 404 para os seguros de uma pessoa de outra conta' do
      ler("pessoas/#{de_fora.id}/seguros", quem: admin)

      expect(response).to have_http_status(:not_found)
    end

    it 'não mostra nem conta seguro de outra conta, na lista, em "Marcar todas", nos grupos, no resumo e nos filtros' do
      seguro_de_fora.update!(seguradora: 'Outra Seguradora Exemplo', seguradora_chave: 'outraseguradoraexemplo', tipo: 'vida')

      expect(numeros).to eq(['EX-001234'])
      ler('seguros/todos')
      expect(response.parsed_body['itens'].pluck('id')).to eq([seguro.id])
      ler('seguros/contagens')
      expect(response.parsed_body['todos']).to eq(1)
      ler('seguros/resumo')
      expect(response.parsed_body['total']).to eq(1)
      ler('seguros/opcoes_de_filtro')
      expect(response.parsed_body).to eq('tipos' => ['auto'], 'seguradoras' => ['Seguradora Exemplo'], 'cuida' => [])
    end
  end

  describe 'um seguro' do
    let(:esperado) do
      {
        'id' => seguro.id, 'pessoaId' => marina.id,
        'pessoa' => { 'id' => marina.id, 'name' => 'Marina Exemplo', 'phone_number' => '+5511900000023', 'opted_out_at' => nil,
                      'blocked' => false, 'contact_type' => 'customer', 'thumbnail' => '' },
        'segurado' => { 'tipo' => 'pessoa', 'id' => marina.id, 'nome' => 'Marina Exemplo', 'documento' => nil },
        'tipo' => 'auto', 'ramoOriginal' => nil, 'seguradora' => 'Seguradora Exemplo', 'numero' => 'EX-001234', 'valor' => 3410.0,
        'bem' => 'Carro Exemplo 2022', 'comeca' => '2025-12-16', 'termina' => '2026-12-16', 'selo' => 'ativo', 'dias' => 34,
        'origem' => { 'tipo' => 'planilha', 'arquivo' => nil, 'em' => agora.to_i },
        'temPdf' => false, 'canceladoEm' => nil, 'corrigidoAMao' => [],
        'renovadoEm' => nil, 'motivo' => nil, 'motivoEscrito' => nil, 'parcelaAbertaEm' => nil, 'renovacao' => nil, 'endosso' => nil,
        'apoliceNova' => false,
        'deFora' => false, 'corretora' => '', 'lembreteEm' => nil
      }
    end

    it 'vem no formato da tela: datas da vigência em AAAA-MM-DD, valor em reais, selo e dias prontos' do
      ler("seguros/#{seguro.id}")

      expect(response.parsed_body).to eq(esperado)
    end

    it 'é o mesmo objeto na lista e na ficha da pessoa' do
      expect(itens).to eq([esperado])
      ler("pessoas/#{marina.id}/seguros")
      expect(response.parsed_body).to eq([esperado])
    end

    it 'diz a planilha de onde veio, se tem PDF, quando foi cancelado e o que foi corrigido à mão' do
      planilha = create_campaign_import(account: account, user: admin, content: 'nome', filename: 'carteira-exemplo.csv')
      seguro.update!(campaign_import: planilha, cancelado_em: agora - 1.hour, corrigido_a_mao: %w[valor], valor_centavos: nil,
                     inicio_vigencia: nil, ramo_original: 'Automóvel')
      guardar_pdf_na(seguro)

      ler("seguros/#{seguro.id}")

      expect(response.parsed_body).to include(
        'origem' => { 'tipo' => 'planilha', 'arquivo' => 'carteira-exemplo.csv', 'em' => agora.to_i }, 'temPdf' => true,
        'canceladoEm' => (agora - 1.hour).to_i, 'selo' => 'cancelado', 'corrigidoAMao' => %w[valor], 'valor' => nil, 'comeca' => nil,
        'ramoOriginal' => 'Automóvel'
      )
    end

    it 'às 22h da conta o seguro que vence hoje ainda está ativo, mesmo com o servidor já no dia seguinte' do
      seguro.update!(fim_vigencia: hoje)
      travel_to(Time.utc(2026, 11, 13, 1))

      ler("seguros/#{seguro.id}")
      expect(response.parsed_body.slice('selo', 'dias')).to eq('selo' => 'ativo', 'dias' => 0)
      expect(numeros(grupo: 'vence_7_dias')).to eq(['EX-001234'])

      travel_to(Time.utc(2026, 11, 13, 4))

      ler("seguros/#{seguro.id}")
      expect(response.parsed_body.slice('selo', 'dias')).to eq('selo' => 'vencido', 'dias' => -1)
      expect([numeros(grupo: 'vence_7_dias'), numeros(grupo: 'vencido')]).to eq([[], ['EX-001234']])
    end

    it 'responde 422, sem repetir o que foi mandado, para parâmetro que a leitura não conhece' do
      (leituras_de_um + %w[seguros/resumo seguros/opcoes_de_filtro]).each do |caminho|
        ler(caminho, busca: 'Marina Exemplo')

        expect(response).to have_http_status(:unprocessable_entity), caminho
        expect(response.parsed_body).to eq('error' => 'pedido_invalido')
      end
    end
  end

  describe 'a história de um seguro' do
    it 'vem do mais novo para o mais velho, com quem fez e o que mudou; o valor que mudou vai em reais' do
      seguro.eventos.create!(tipo: 'chegou_planilha', quando: agora - 3.days, valores: { arquivo: 'carteira-exemplo.csv' })
      seguro.eventos.create!(tipo: 'corrigido', quando: agora - 1.day, user: admin, valores: { campos: %w[valor termina] },
                             mudancas: [{ campo: 'valor', antes: 300_000, depois: 341_000 },
                                        { campo: 'termina', antes: '2026-12-01', depois: '2026-12-16' }])

      ler("seguros/#{seguro.id}/historia")

      expect(response.parsed_body).to eq(
        [
          { 'tipo' => 'corrigido', 'quando' => (agora - 1.day).to_i, 'quem' => { 'id' => admin.id, 'nome' => admin.name },
            'valores' => { 'campos' => %w[valor termina] }, 'acao' => nil,
            'mudancas' => [{ 'campo' => 'valor', 'antes' => 3000.0, 'depois' => 3410.0 },
                           { 'campo' => 'termina', 'antes' => '2026-12-01', 'depois' => '2026-12-16' }] },
          { 'tipo' => 'chegou_planilha', 'quando' => (agora - 3.days).to_i, 'quem' => nil,
            'valores' => { 'arquivo' => 'carteira-exemplo.csv' }, 'acao' => nil, 'mudancas' => nil }
        ]
      )
    end
  end

  describe 'os seguros da pessoa' do
    it 'vêm na ordem de urgência: vencido, ativo do que termina antes, cancelado por último; só os dela' do
      criar_apolice(marina, numero: 'EX-VENCIDO', fim_vigencia: hoje - 10)
      criar_apolice(marina, numero: 'EX-CANCELADO', fim_vigencia: hoje + 5, cancelado_em: agora)
      criar_apolice(marina, numero: 'EX-LOGO', fim_vigencia: hoje + 3)
      criar_apolice(pessoa('Caio Exemplo'), numero: 'EX-DO-CAIO')

      ler("pessoas/#{marina.id}/seguros")

      expect(response.parsed_body.pluck('numero', 'selo')).to eq(
        [%w[EX-VENCIDO vencido], %w[EX-LOGO ativo], %w[EX-001234 ativo], %w[EX-CANCELADO cancelado]]
      )
    end

    it 'pessoa sem seguro vem com a lista vazia' do
      ler("pessoas/#{pessoa('Caio Exemplo').id}/seguros")

      expect(response.parsed_body).to eq([])
    end
  end

  describe 'a aba Seguros' do
    # Com o seguro da Marina (termina em 34 dias): um de cada lado de cada corte.
    let(:carteira) do
      { 'EX-HOJE' => { fim_vigencia: hoje }, 'EX-EM-7' => { fim_vigencia: hoje + 7 }, 'EX-EM-8' => { fim_vigencia: hoje + 8 },
        'EX-EM-91' => { fim_vigencia: hoje + 91 }, 'EX-ONTEM' => { fim_vigencia: hoje - 1 },
        'EX-CANCELADO' => { fim_vigencia: hoje + 5, cancelado_em: agora } }
    end

    def montar_carteira
      carteira.each_with_index do |(numero, campos), indice|
        criar_apolice(pessoa("Pessoa #{numero}", phone_number: "+551190000010#{indice}"), numero: numero, **campos)
      end
      criar_apolice(pessoa('Sem Telefone Exemplo'), numero: 'EX-SEM-TELEFONE', fim_vigencia: hoje + 200)
    end

    it 'conta cada grupo como a tabela do selo manda: os de vencimento acumulam e só contam seguro que ainda vale' do
      montar_carteira

      ler('seguros/contagens')

      expect(response.parsed_body).to eq('todos' => 8, 'vence_7_dias' => 2, 'vence_30_dias' => 3, 'vence_90_dias' => 4, 'em_renovacao' => 0,
                                         'vencido' => 1, 'sem_telefone' => 1)
    end

    it 'mostra em cada grupo os seguros dele, e o selo de cada um bate com o grupo' do
      montar_carteira
      por_grupo = {
        'vence_7_dias' => %w[EX-HOJE EX-EM-7], 'vence_30_dias' => %w[EX-HOJE EX-EM-7 EX-EM-8],
        'vence_90_dias' => %w[EX-HOJE EX-EM-7 EX-EM-8 EX-001234], 'vencido' => %w[EX-ONTEM], 'sem_telefone' => %w[EX-SEM-TELEFONE]
      }

      por_grupo.each { |grupo, esperados| expect(numeros(grupo: grupo)).to eq(esperados), grupo }
      expect(itens(grupo: 'vencido').pluck('selo')).to eq(%w[vencido])
      expect(itens(grupo: 'vence_90_dias').pluck('selo').uniq).to eq(%w[ativo])
    end

    it 'sem pedir ordem, quem ainda vale vem antes, do que termina mais cedo; depois os outros, do que terminou há menos tempo' do
      montar_carteira

      expect(itens.pluck('numero', 'selo', 'dias')).to eq(
        [['EX-HOJE', 'ativo', 0], ['EX-EM-7', 'ativo', 7], ['EX-EM-8', 'ativo', 8], ['EX-001234', 'ativo', 34], ['EX-EM-91', 'ativo', 91],
         ['EX-SEM-TELEFONE', 'ativo', 200], ['EX-CANCELADO', 'cancelado', 5], ['EX-ONTEM', 'vencido', -1]]
      )
    end

    it 'ordena pelo nome do segurado, sem diferença de acento nem de maiúscula, e pelos que começaram há menos tempo' do
      criar_apolice(pessoa('álvaro Exemplo'), numero: 'EX-ALVARO', inicio_vigencia: nil)
      criar_apolice(pessoa('Zélia Exemplo'), numero: 'EX-ZELIA', inicio_vigencia: Date.new(2026, 9, 1))

      expect(numeros(ordem: 'nome')).to eq(%w[EX-ALVARO EX-001234 EX-ZELIA])
      expect(numeros(ordem: 'mais_novos')).to eq(%w[EX-ZELIA EX-001234 EX-ALVARO])
    end

    it 'busca pelo nome da pessoa, pelo número da apólice (com ou sem pontuação) e pelo bem' do
      criar_apolice(pessoa('Caio Exemplo'), numero: 'EX-555000', bem: 'Casa Exemplo')
      buscas = { 'marína' => %w[EX-001234], 'ex-001234' => %w[EX-001234], 'ex001234' => %w[EX-001234], '001234' => %w[EX-001234],
                 'carro exemplo' => %w[EX-001234], 'caio' => %w[EX-555000], 'casa' => %w[EX-555000], 'exemplo' => %w[EX-001234 EX-555000],
                 'ninguém com este nome' => [], '---' => [] }

      buscas.each { |busca, esperados| expect(numeros(busca: busca, ordem: 'nome').sort).to eq(esperados), busca }
    end

    it 'filtra por tipo e por seguradora, e a seguradora escrita de outro jeito é a mesma' do
      criar_apolice(pessoa('Caio Exemplo'), numero: 'EX-VIDA', tipo: 'vida', seguradora: 'Outra Seguradora Exemplo')
      criar_apolice(pessoa('Dora Exemplo'), numero: 'EX-CAIXA', seguradora: 'SEGURADORA EXEMPLO')

      expect(numeros(filtros: { tipo: 'vida' })).to eq(%w[EX-VIDA])
      expect(numeros(filtros: { seguradora: 'seguradora exemplo' }).sort).to eq(%w[EX-001234 EX-CAIXA])
      expect(numeros(filtros: { tipo: 'auto', seguradora: 'Outra Seguradora Exemplo' })).to eq([])
      expect(numeros(filtros: { tipo: '', seguradora: '' }).size).to eq(3)
      ler('seguros/contagens', filtros: { tipo: 'vida' })
      expect(response.parsed_body['todos']).to eq(1)
      ler('seguros/opcoes_de_filtro')
      expect(response.parsed_body).to eq('tipos' => %w[auto vida], 'seguradoras' => ['Outra Seguradora Exemplo', 'SEGURADORA EXEMPLO'],
                                         'cuida' => [])
    end

    it 'pagina de 25 em 25 e diz se tem mais' do
      25.times { |n| criar_apolice(marina, numero: "EX-PAG-#{n}", fim_vigencia: hoje + 100 + n) }

      ler('seguros')
      primeira = response.parsed_body
      ler('seguros', pagina: 2)
      segunda = response.parsed_body

      expect([primeira['itens'].size, primeira['total'], primeira['temMais']]).to eq([25, 26, true])
      expect([segunda['itens'].pluck('numero'), segunda['total'], segunda['temMais']]).to eq([['EX-PAG-24'], 26, false])
    end

    it '"Marcar todas" traz a consulta inteira, sem página, só com o que a ação em grupo lê de cada seguro' do
      26.times { |n| criar_apolice(marina, numero: "EX-TODOS-#{n}", fim_vigencia: hoje + 100 + n) }

      ler('seguros/todos', busca: 'ex-todos')
      corpo = response.parsed_body

      expect([corpo['total'], corpo['itens'].size]).to eq([26, 26])
      expect(corpo['itens'].first).to eq(
        'id' => Carteira::Apolice.find_by!(numero: 'EX-TODOS-0').id, 'pessoaId' => marina.id,
        'pessoa' => { 'id' => marina.id, 'name' => 'Marina Exemplo', 'phone_number' => '+5511900000023', 'blocked' => false,
                      'opted_out_at' => nil }
      )
    end

    it 'o resumo conta a carteira inteira e os que vencem em até 7 dias; sem renovação em curso, os números dela vêm zerados' do
      montar_carteira

      ler('seguros/resumo')

      expect(response.parsed_body).to eq('total' => 8, 'vence7' => 2, 'vence7EmRenovacao' => 0, 'emRenovacao' => 0, 'aggerLigado' => false)
    end

    it 'responde 422, sem repetir o que foi pedido, para grupo, ordem, página, filtro ou formato que a carteira não conhece' do
      pedidos = [{ grupo: 'nao_renovaram_60' }, { grupo: 'parcela_atrasada' }, { grupo: 'clientes' }, { ordem: 'ultima_conversa' },
                 { pagina: 0 }, { pagina: 'dois' }, { filtros: { tipo: 'moto' } }, { filtros: { cuida: 'Marina Exemplo' } },
                 { filtros: { cuida: '0' } }, { filtros: 'tudo' }, { grupo: %w[todos vencido] }]

      %w[seguros seguros/todos seguros/contagens].each do |caminho|
        pedidos.each do |pedido|
          ler(caminho, **pedido)

          expect(response).to have_http_status(:unprocessable_entity), "#{caminho} #{pedido}"
          expect(response.parsed_body).to eq('error' => 'pedido_invalido')
        end
      end
    end

    it 'não faz uma consulta a mais por seguro (pessoa, foto, planilha e PDF)' do
      planilha = create_campaign_import(account: account, user: admin, content: 'nome', filename: 'carteira-exemplo.csv')
      criar = lambda do |n|
        dona = create(:contact, :with_avatar, account: account, name: "Pessoa #{n}", contact_type: :customer)
        guardar_pdf_na(criar_apolice(dona, campaign_import: planilha))
      end
      2.times(&criar)
      cabecalhos = agente.create_new_auth_token
      pedir = -> { get "#{base}/seguros", headers: cabecalhos }
      pedir.call
      com_tres = consultas_da_carteira(&pedir)
      3.times { |n| criar.call(n + 2) }

      expect(consultas_da_carteira(&pedir)).to eq(com_tres)
      expect(response.parsed_body['itens'].size).to eq(6)
      expect(response.parsed_body['itens'].last(5).pluck('temPdf')).to all(be(true))
      expect(response.parsed_body['itens'].last(5).map { |item| item.dig('pessoa', 'thumbnail') }).to all(be_present)
    end
  end
end
