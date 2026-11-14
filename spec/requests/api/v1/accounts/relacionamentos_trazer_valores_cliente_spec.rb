require 'rails_helper'

# #2896 — "Trazer minha lista": "Quais destes querem dizer cliente?". O código não adivinha mais o que a célula quer
# dizer: a pessoa escolhe, entre os valores da coluna que ela apontou, quais marcam cliente. A tela recebe os valores
# contados e devolve chaves (nunca o texto); sem a escolha, a lista não é trazida.
RSpec.describe 'Trazer minha lista: quais valores querem dizer cliente (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with trazer conferencia'

  # Colunas: 0 Nome, 1 Celular, 2 Cidade, 3 Cliente?. A linha 8 tem problema de telefone e a 9 escreve "Nao" sem acento.
  let(:planilha) do
    <<~CSV
      Nome;Celular;Cidade;Cliente?
      Ana Albuquerino;11987650001;Campinas;Sim
      Bruno Brandolim;11987650002;Santos;não
      Carla Carvalhedo;11987650003;;SIM
      Davi Dornelino;11987650004;;Sim desde 2019
      Elisa Esteveira;11987650005;;
      Fabio Ferreirinho;11987650006;Recife;  sim
      Gil Goncalvino;123;;Sim
      Hugo Honorato;11987650008;;Nao
      Iara Iglesias;11987650009;;Não
    CSV
  end
  let(:valores_da_planilha) { ['Sim', 'SIM', 'não', 'Não', 'Nao', 'desde 2019'] }
  let(:do_telefone) { { 'id' => 'telefone', 'coluna' => 'Celular', 'indice' => 1 } }

  # A chave de um valor é da planilha e da coluna: sem dizer, a última planilha enviada e a coluna "Cliente?".
  def chave(valor, coluna: 3, importacao: account.campaign_imports.order(:id).last)
    ContactImports::Trazer::Cliente.chave(importacao.id, coluna, valor)
  end

  def a_pergunta(corpo = response.parsed_body)
    corpo['perguntas'].find { |pergunta| pergunta['id'] == 'valores_cliente' }
  end

  def clientes_gravados
    account.contacts.where(contact_type: :customer).order(:name).pluck(:name)
  end

  describe 'a pergunta' do
    it 'aparece quando a pessoa aponta a coluna, com os valores contados do mais frequente ao menos, sem ler a planilha de novo' do
      importacao = ler_planilha

      expect { responder(importacao, clientes: 'algumas', coluna_cliente: 3) }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:ok)
      corpo = response.parsed_body
      expect(corpo['perguntas']).to eq(
        [{ 'id' => 'clientes' },
         { 'id' => 'valores_cliente', 'coluna' => 'Cliente?', 'indice' => 3, 'preenchidas' => 8,
           'valores' => [
             # "Sim", "SIM", "  sim" e o "Sim" da linha com problema são o mesmo valor; aparece a forma mais escrita.
             { 'chave' => chave('sim'), 'valor' => 'Sim', 'linhas' => 4 },
             { 'chave' => chave('não'), 'valor' => 'não', 'linhas' => 2 },
             # Empate: a ordem em que aparecem na planilha. "Nao" sem acento é outro valor.
             { 'chave' => chave('sim desde 2019'), 'valor' => 'Sim desde 2019', 'linhas' => 1 },
             { 'chave' => chave('nao'), 'valor' => 'Nao', 'linhas' => 1 }
           ],
           'outros' => nil },
         do_telefone]
      )
      expect(corpo['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 3)
      expect(corpo['resumo']).to include('entram' => 8, 'clientes' => 0)
      expect(corpo['exemplos'].pluck('cliente')).to eq([false, false, false])
      expect(corpo).to eq(ler(importacao))
    end

    it 'é a mesma para quem marcou a coluna como "cliente" pela tela das colunas' do
      importacao = ler_planilha

      expect { trocar(importacao, 3, destino: 'cliente') }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:ok)
      expect(a_pergunta).to include('coluna' => 'Cliente?', 'indice' => 3, 'preenchidas' => 8)
      expect(a_pergunta['valores'].pluck('valor', 'linhas')).to eq([['Sim', 4], ['não', 2], ['Sim desde 2019', 1], ['Nao', 1]])
    end

    it 'não existe com "sim, todas" nem com "ainda não"' do
      importacao = ler_planilha

      responder(importacao, clientes: 'ainda_nao')
      expect(a_pergunta).to be_nil
      expect(response.parsed_body['resumo']).to include('clientes' => 0)

      responder(importacao, clientes: 'sim_todas')
      expect(a_pergunta).to be_nil
      expect(response.parsed_body['resumo']).to include('entram' => 8, 'clientes' => 8)

      # Com "sim, todas", a coluna marcada pela tela das colunas não traz a pergunta.
      trocar(importacao, 3, destino: 'cliente')
      expect(a_pergunta).to be_nil
      expect(response.parsed_body['respostas']).to eq('clientes' => 'sim_todas')
      expect(response.parsed_body['resumo']).to include('clientes' => 8)
    end

    it 'mostra no máximo 20 valores e diz quantos ficaram de fora' do
      linhas = (1..25).map { |numero| "Pessoa #{numero};119876501#{format('%02d', numero)};;valor #{numero}" }
      importacao = ler_planilha("Nome;Celular;Cidade;Cliente?\n#{linhas.join("\n")}\nMais Uma;11987650199;;valor 7\n")

      responder(importacao, clientes: 'algumas', coluna_cliente: 3)

      expect(a_pergunta).to include('preenchidas' => 26, 'outros' => { 'valores' => 5, 'linhas' => 5 })
      expect(a_pergunta['valores'].size).to eq(20)
      expect(a_pergunta['valores'].first).to eq('chave' => chave('valor 7'), 'valor' => 'valor 7', 'linhas' => 2)
      expect(a_pergunta['valores'].pluck('valor').last(2)).to eq(['valor 19', 'valor 20'])
    end
  end

  describe 'PATCH leituras/:id/respostas com valores_cliente' do
    it '"toda linha com algo escrito": marca quem tem a célula preenchida, e o resumo diz quantas das que entram' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)

      expect { responder(importacao, valores_cliente: { modo: 'preenchidas' }) }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:ok)
      corpo = response.parsed_body
      expect(corpo['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 3, 'valores_cliente' => { 'modo' => 'preenchidas' })
      # Das 8 que entram, a Elisa não tem nada escrito; o Gil tem, mas a linha dele tem problema e não entra.
      expect(corpo['resumo']).to include('entram' => 8, 'clientes' => 7)
      expect(corpo['exemplos'].pluck('cliente')).to eq([true, true, true])
      expect(a_pergunta(corpo)).to be_present
    end

    it 'os valores escolhidos: só chaves e modo ficam guardados, nunca o texto da célula' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)

      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim'), chave('sim desde 2019')] })

      expect(response).to have_http_status(:ok)
      escolha = { 'modo' => 'valores', 'chaves' => [chave('sim'), chave('sim desde 2019')] }
      expect(response.parsed_body['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 3, 'valores_cliente' => escolha)
      # Ana, Carla, Davi e Fabio entram como clientes; o Gil só entra depois de consertado.
      expect(response.parsed_body['resumo']).to include('entram' => 8, 'clientes' => 4)
      expect(response.parsed_body['exemplos'].pluck('cliente')).to eq([true, false, true])
      expect(importacao.reload.options['trazer'])
        .to eq('destinos' => { '3' => 'cliente' }, 'respostas' => { 'clientes' => 'algumas', 'valores_cliente' => escolha })
      expect([importacao.options, importacao.validation_summary].to_json).not_to include(*valores_da_planilha)

      consertar(importacao, 8, valor: '11987650007')
      expect(ler(importacao)['resumo']).to include('entram' => 9, 'clientes' => 5)
    end

    # A tela atualiza "entram" e "clientes" sem ler a conferência inteira de novo.
    it 'quem mexe numa linha recebe quantas das que entram viram cliente, a mesma conta do resumo' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim')] })
      expect(response.parsed_body['resumo']).to include('entram' => 8, 'clientes' => 3)

      # O Gil tem "Sim" na coluna: consertado, entra e é cliente.
      consertar(importacao, 8, valor: '11987650007')
      expect(response.parsed_body).to include('entram' => 9, 'clientes' => 4)
      expect(ler(importacao)['resumo']).to include('entram' => 9, 'clientes' => 4)
      deixar_de_fora(importacao, 8)
      expect(response.parsed_body).to include('entram' => 8, 'clientes' => 3)
      reabrir(importacao, 8)
      expect(response.parsed_body).to include('entram' => 8, 'clientes' => 3)
      expect(ler(importacao)['resumo']).to include('entram' => 8, 'clientes' => 3)

      # Com "sim, todas", toda linha que entra é cliente.
      responder(importacao, clientes: 'sim_todas')
      consertar(importacao, 8, valor: '11987650007')
      expect(response.parsed_body).to include('entram' => 9, 'clientes' => 9)
    end

    it 'aceita a resposta junto com "algumas" e a coluna, num pedido só' do
      importacao = ler_planilha

      responder(importacao, clientes: 'algumas', coluna_cliente: 3, valores_cliente: { modo: 'preenchidas' })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['respostas'])
        .to eq('clientes' => 'algumas', 'coluna_cliente' => 3, 'valores_cliente' => { 'modo' => 'preenchidas' })

      # Com a coluna já apontada, as chaves dela valem no mesmo pedido.
      responder(importacao, clientes: 'algumas', coluna_cliente: 3, valores_cliente: { modo: 'valores', chaves: [chave('não')] })
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['respostas']['valores_cliente']).to eq('modo' => 'valores', 'chaves' => [chave('não')])
      expect(response.parsed_body['resumo']).to include('clientes' => 2)
    end

    it 'recusa, sem mudar nada, o modo que não existe, a escolha vazia e a chave que não é de um valor da coluna' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      antes = importacao.reload.options['trazer']

      [{ modo: 'talvez' }, { modo: 'valores' }, { modo: 'valores', chaves: [] }, { chaves: [chave('sim')] },
       { modo: 'valores', chaves: [chave('sim'), chave('talvez')] }, { modo: 'valores', chaves: ['Sim'] }].each do |escolha|
        responder(importacao, valores_cliente: escolha)

        expect(response).to have_http_status(:unprocessable_entity), escolha.inspect
        expect(response.parsed_body).to eq('error' => 'resposta_desconhecida')
      end
      expect(importacao.reload.options['trazer']).to eq(antes)
    end

    # A pessoa ainda não viu os valores da coluna nova: a escolha deles vai num pedido depois da troca, nunca junto.
    it 'recusa a escolha de valores no mesmo pedido que troca a coluna, mesmo com a chave certa de um valor da coluna nova' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      antes = importacao.reload.options['trazer']
      de_campinas = chave('campinas', coluna: 2)

      responder(importacao, clientes: 'algumas', coluna_cliente: 2, valores_cliente: { modo: 'valores', chaves: [de_campinas] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'resposta_desconhecida')
      expect(importacao.reload.options['trazer']).to eq(antes)

      # A mesma chave vale depois que a troca mostrou os valores da coluna nova.
      responder(importacao, clientes: 'algumas', coluna_cliente: 2)
      expect(a_pergunta['valores'].first).to eq('chave' => de_campinas, 'valor' => 'Campinas', 'linhas' => 1)
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [de_campinas] })
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['resumo']).to include('clientes' => 1)
    end

    # Com a chave igual em toda parte, qualquer conta serviria de dicionário e duas colunas trocariam chave entre si.
    it 'a chave é da planilha e da coluna: o mesmo texto noutra planilha ou noutra coluna tem outra chave, e a de fora é recusada' do
      duas_colunas = "Nome;Celular;Ativo?;Cliente?\nAna Albuquerino;11987650001;Sim;Sim\nBruno Brandolim;11987650002;Sim;não\n"
      primeira = ler_planilha(duas_colunas)
      responder(primeira, clientes: 'algumas', coluna_cliente: 3)
      da_primeira = a_pergunta['valores'].first
      segunda = ler_planilha(duas_colunas)
      responder(segunda, clientes: 'algumas', coluna_cliente: 3)
      da_segunda = a_pergunta['valores'].first

      expect([da_primeira, da_segunda].map { |valor| valor.slice('valor', 'linhas') }).to eq([{ 'valor' => 'Sim', 'linhas' => 1 }] * 2)
      expect(da_primeira['chave']).to eq(chave('sim', importacao: primeira))
      expect(da_segunda['chave']).to eq(chave('sim', importacao: segunda))
      expect(da_primeira['chave']).not_to eq(da_segunda['chave'])
      # A chave do "Sim" da outra planilha não vale nesta.
      responder(segunda, valores_cliente: { modo: 'valores', chaves: [da_primeira['chave']] })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'resposta_desconhecida')

      # Nem a do "Sim" da outra coluna da mesma planilha.
      responder(segunda, clientes: 'algumas', coluna_cliente: 2)
      da_outra_coluna = a_pergunta['valores'].first
      expect(da_outra_coluna).to eq('chave' => chave('sim', coluna: 2, importacao: segunda), 'valor' => 'Sim', 'linhas' => 2)
      expect(da_outra_coluna['chave']).not_to eq(da_segunda['chave'])
      responder(segunda, valores_cliente: { modo: 'valores', chaves: [da_segunda['chave']] })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'resposta_desconhecida')
      expect(segunda.reload.options['trazer']['respostas']).to eq('clientes' => 'algumas')
    end

    it 'recusa com "pergunta_desconhecida" quando não há coluna que diga quem é cliente' do
      importacao = ler_planilha

      [{ valores_cliente: { modo: 'preenchidas' } }, { clientes: 'sim_todas', valores_cliente: { modo: 'preenchidas' } },
       { clientes: 'ainda_nao', valores_cliente: { modo: 'preenchidas' } }].each do |respostas|
        responder(importacao, **respostas)

        expect(response).to have_http_status(:unprocessable_entity), respostas.inspect
        expect(response.parsed_body).to eq('error' => 'pergunta_desconhecida')
      end
      expect(importacao.reload.options['trazer']).to eq({})

      # Com "sim, todas" a pergunta não existe, mesmo com a coluna marcada pela tela das colunas.
      responder(importacao, clientes: 'sim_todas')
      trocar(importacao, 3, destino: 'cliente')
      responder(importacao, valores_cliente: { modo: 'preenchidas' })
      expect(response.parsed_body).to eq('error' => 'pergunta_desconhecida')
    end
  end

  describe 'a escolha acompanha a coluna' do
    it 'trocar a coluna que diz quem é cliente, ou mandá-la para outro destino, apaga a escolha' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3, valores_cliente: { modo: 'preenchidas' })

      # Para outro destino: não há mais coluna, e a pergunta some com a escolha.
      trocar(importacao, 3, destino: 'informacao')
      expect(response.parsed_body['respostas']).to eq({})
      expect(a_pergunta).to be_nil
      expect(importacao.reload.valores_cliente).not_to be_attached

      # De volta: a pergunta volta sem resposta.
      trocar(importacao, 3, destino: 'cliente')
      expect(response.parsed_body['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 3)
      expect(a_pergunta).to include('indice' => 3, 'preenchidas' => 8)

      # Outra coluna passa a dizer quem é cliente: só uma diz, e a escolha da antiga não vale para a nova.
      responder(importacao, valores_cliente: { modo: 'preenchidas' })
      trocar(importacao, 2, destino: 'cliente')
      expect(response.parsed_body['colunas'].pluck('destino').last(2)).to eq(%w[cliente informacao])
      expect(response.parsed_body['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 2)
      expect(a_pergunta['valores'].pluck('valor', 'linhas')).to eq([['Campinas', 1], ['Santos', 1], ['Recife', 1]])
      expect(response.parsed_body['resumo']).to include('clientes' => 0)

      # Pela pergunta "São clientes?" também.
      responder(importacao, valores_cliente: { modo: 'preenchidas' })
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      expect(response.parsed_body['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 3)
      responder(importacao, valores_cliente: { modo: 'preenchidas' })
      responder(importacao, clientes: 'ainda_nao')
      expect(response.parsed_body['respostas']).to eq('clientes' => 'ainda_nao')
      expect(importacao.reload.options['trazer']['respostas']).to eq('clientes' => 'ainda_nao')
      expect(importacao.valores_cliente).not_to be_attached
    end

    it 'a coluna que deixa de ser guardada leva junto a contagem e a escolha' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim')] })
      expect(importacao.reload.valores_cliente).to be_attached

      trocar(importacao, 3, destino: 'nao_guardar')

      expect(response.parsed_body['respostas']).to eq({})
      expect(importacao.reload.valores_cliente).not_to be_attached
      expect(importacao.options['trazer']).to include('destinos' => { '3' => 'nao_guardar' })
      expect(importacao.options['trazer']['respostas']).not_to have_key('valores_cliente')
    end

    it 'a planilha lida de novo mantém a escolha enquanto os valores escolhidos existem' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim'), chave('nao')] })
      antes = a_pergunta

      # Tirar a coluna de cidade e trazê-la de volta lê a planilha de novo.
      trocar(importacao, 2, destino: 'nao_guardar')
      expect { trocar(importacao, 2, destino: 'cidade') }.to have_enqueued_job(CampaignImports::ValidateJob).once
      ler_de_novo

      corpo = ler(importacao)
      expect(a_pergunta(corpo)).to eq(antes)
      expect(corpo['respostas']['valores_cliente']).to eq('modo' => 'valores', 'chaves' => [chave('sim'), chave('nao')])
      expect(corpo['resumo']).to include('clientes' => 4)
    end

    it 'o valor escolhido que sumiu da planilha lida de novo derruba a escolha: a pergunta volta sem resposta' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim'), chave('nao')] })
      importacao.original_file.attach(io: StringIO.new(planilha.sub("Hugo Honorato;11987650008;;Nao\n", '')), filename: 'Clientes 2025.csv',
                                      content_type: 'text/csv')

      perform_enqueued_jobs { CampaignImports::ValidateJob.perform_later(importacao) }

      corpo = ler(importacao)
      expect(corpo['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 3)
      expect(a_pergunta(corpo)['valores'].pluck('valor')).to eq(['Sim', 'não', 'Sim desde 2019'])
      expect(corpo['resumo']).to include('clientes' => 0)
      trazer(importacao)
      expect(response.parsed_body).to eq('error' => 'falta_valores_cliente')
    end

    # Só os 20 valores mais frequentes são mostrados: o que saiu deles a pessoa não vê mais marcado.
    it 'o valor escolhido que cai para "outros" na planilha lida de novo também derruba a escolha' do
      linhas = (1..20).map { |numero| "Pessoa #{numero};119876501#{format('%02d', numero)};;valor #{numero}" }
      importacao = ler_planilha("Nome;Celular;Cidade;Cliente?\n#{linhas.join("\n")}\n")
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('valor 20')] })
      expect(response.parsed_body['resumo']).to include('entram' => 20, 'clientes' => 1)
      expect(a_pergunta).to include('outros' => nil)
      # A planilha nova tem um valor a mais, antes de todos: o "valor 20" passa a ser o 21º.
      nova = "Nome;Celular;Cidade;Cliente?\nPessoa Nova;11987650199;;valor 0\n#{linhas.join("\n")}\n"
      importacao.original_file.attach(io: StringIO.new(nova), filename: 'Clientes 2025.csv', content_type: 'text/csv')

      perform_enqueued_jobs { CampaignImports::ValidateJob.perform_later(importacao) }

      corpo = ler(importacao)
      expect(a_pergunta(corpo)).to include('preenchidas' => 21, 'outros' => { 'valores' => 1, 'linhas' => 1 })
      expect(a_pergunta(corpo)['valores'].pluck('valor')).not_to include('valor 20')
      expect(corpo['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 3)
      expect(corpo['resumo']).to include('entram' => 21, 'clientes' => 0)
      trazer(importacao)
      expect(response.parsed_body).to eq('error' => 'falta_valores_cliente')
    end

    describe 'quando a mudança faz a planilha lida de novo não dar leitura' do
      # Colunas: 0 Nome, 1 Celular, 2 Obs. Com a coluna Obs no lugar do telefone ninguém tem contato que valha.
      let(:planilha) { "Nome;Celular;Obs\nAna Albuquerino;11987650001;x\nCarla Carvalhedo;(11) 2345-678;y\n" }

      it 'a mudança é desfeita e a coluna de antes volta com a contagem e a escolha que tinha' do
        importacao = ler_planilha
        responder(importacao, clientes: 'algumas', coluna_cliente: 2)
        escolha = { 'modo' => 'valores', 'chaves' => [chave('x', coluna: 2)] }
        responder(importacao, valores_cliente: escolha)
        antes = ler(importacao)
        expect(a_pergunta(antes)['valores'].pluck('valor', 'linhas')).to eq([['x', 1], ['y', 1]])
        expect(antes['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 2, 'valores_cliente' => escolha)
        expect(antes['resumo']).to include('entram' => 1, 'clientes' => 1)

        # A coluna que dizia quem é cliente vira o telefone: a escolha e a contagem dela saem, e a leitura nova falha.
        trocar(importacao, 2, destino: 'telefone')
        expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
        expect(importacao.reload.options['trazer']['respostas']).not_to have_key('valores_cliente')
        ler_de_novo

        expect(ler(importacao)).to eq(antes.merge('aviso' => 'mudanca_desfeita'))
        expect(importacao.reload.options['trazer']).to include('destinos' => { '2' => 'cliente' })
        expect(importacao.options['trazer']['respostas']).to include('valores_cliente' => escolha)
        expect(importacao.valores_cliente).to be_attached
        trazer(importacao)
        expect(response).to have_http_status(:ok)
      end
    end

    it 'a planilha lida de novo conta os valores da coluna que voltou de "não guardar" para "cliente"' do
      importacao = ler_planilha
      trocar(importacao, 3, destino: 'nao_guardar')

      expect { responder(importacao, clientes: 'algumas', coluna_cliente: 3) }.to have_enqueued_job(CampaignImports::ValidateJob).once
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      ler_de_novo

      expect(a_pergunta(ler(importacao))['valores'].pluck('valor', 'linhas')).to eq([['Sim', 4], ['não', 2], ['Sim desde 2019', 1], ['Nao', 1]])
    end
  end

  describe 'POST leituras/:id/trazer' do
    def confirmar_pela_rota_antiga(importacao)
      post "/api/v1/accounts/#{account.id}/contact_imports/#{importacao.id}/confirm", headers: cabecalhos(admin)
    end

    it 'nunca traz adivinhando: sem a escolha recusa com "falta_valores_cliente", e a rota antiga de confirmar também recusa' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)

      expect { trazer(importacao) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'falta_valores_cliente')
      expect { confirmar_pela_rota_antiga(importacao) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unprocessable_entity)
      expect(importacao.reload).to be_ready_to_confirm
      expect(account.contacts).to be_empty
    end

    # A escolha guardada só vale com os valores que a coluna tem agora: o "Trazer" confere de novo, sob a trava.
    it 'recusa com "falta_valores_cliente" a escolha que aponta um valor que a coluna não tem mais, sem gravar nada' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim'), chave('nao')] })
      # A contagem refeita sem o "Nao" do Hugo (linha 9), por fora da leitura da planilha, que apagaria a escolha.
      importacao.campaign_import_rows.find_by!(row_number: 9).update!(extra_values: {})
      ContactImports::Trazer::ValoresDeCliente.new(importacao.reload).contar(3)
      expect(a_pergunta(ler(importacao))['valores'].pluck('valor')).to eq(['Sim', 'não', 'Sim desde 2019'])

      expect { trazer(importacao) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'falta_valores_cliente')
      expect { confirmar_pela_rota_antiga(importacao) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unprocessable_entity)
      expect(importacao.reload).to be_ready_to_confirm
      expect(account.contacts).to be_empty

      # A pessoa escolhe de novo entre os valores de agora, e a lista é trazida.
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim')] })
      trazer(importacao)
      expect(response).to have_http_status(:ok)
    end

    # O Excel costuma deixar um espaço que não quebra linha (U+00A0) colado no valor: é o mesmo valor.
    it 'o valor com espaço que não quebra linha, ou com espaço a mais, é o mesmo valor e marca cliente na gravação' do
      colado = "\u00A0"
      importacao = ler_planilha(<<~CSV)
        Nome;Celular;Cidade;Cliente?
        Ana Albuquerino;11987650001;;Sim
        Bruno Brandolim;11987650002;;Sim#{colado}
        Carla Carvalhedo;11987650003;;#{colado}Sim#{colado}#{colado}
        Davi Dornelino;11987650004;;Sim  desde#{colado}2019
        Elisa Esteveira;11987650005;;não
      CSV
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)

      expect(a_pergunta['valores']).to eq(
        [{ 'chave' => chave('sim'), 'valor' => 'Sim', 'linhas' => 3 },
         { 'chave' => chave('sim desde 2019'), 'valor' => 'Sim desde 2019', 'linhas' => 1 },
         { 'chave' => chave('não'), 'valor' => 'não', 'linhas' => 1 }]
      )
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim')] })
      expect(response.parsed_body['resumo']).to include('entram' => 5, 'clientes' => 3)
      trazer(importacao)
      gravar_a_lista

      expect(importacao.reload).to be_completed
      expect(clientes_gravados).to eq(['Ana Albuquerino', 'Bruno Brandolim', 'Carla Carvalhedo'])
    end

    # De um grupo de linhas da mesma pessoa entra uma só: a conta de clientes segue a linha que ficou.
    it 'conta os clientes pela linha repetida que a pessoa manteve, e não pela que saiu no lugar dela' do
      importacao = ler_planilha(<<~CSV)
        Nome;Celular;Cidade;Cliente?
        Ana Albuquerino;11987650001;;Sim
        Bruno Brandolim;11987650002;;Sim
        Ana Outra;11987650001;;não
      CSV
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim')] })
      expect(response.parsed_body['resumo']).to include('entram' => 2, 'clientes' => 2)

      # Ficar com a linha 4 ("não") tira a linha 2 ("Sim"), que estava aprovada.
      consertar(importacao, 4, ficar_com: 4)
      expect(response.parsed_body).to include('entram' => 2, 'clientes' => 1)
      expect(ler(importacao)['resumo']).to include('entram' => 2, 'clientes' => 1)
      # E a linha que ficou conta pelo valor dela.
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('não')] })
      expect(response.parsed_body['resumo']).to include('entram' => 2, 'clientes' => 1)
      responder(importacao, valores_cliente: { modo: 'preenchidas' })
      expect(response.parsed_body['resumo']).to include('entram' => 2, 'clientes' => 2)
      reabrir(importacao, 4)
      expect(response.parsed_body).to include('entram' => 2, 'clientes' => 2)

      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim')] })
      consertar(importacao, 4, ficar_com: 4)
      trazer(importacao)
      gravar_a_lista
      expect(clientes_gravados).to eq(['Bruno Brandolim'])
      expect(account.contacts.order(:name).pluck(:name)).to eq(['Ana Outra', 'Bruno Brandolim'])
    end

    it 'grava como cliente só quem tem um dos valores que a pessoa escolheu' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3, telefone: 'da_pessoa')
      responder(importacao, valores_cliente: { modo: 'valores', chaves: [chave('sim'), chave('sim desde 2019')] })
      consertar(importacao, 8, valor: '11987650007')

      trazer(importacao)
      expect(response).to have_http_status(:ok)
      gravar_a_lista

      expect(importacao.reload).to be_completed
      expect(account.contacts.count).to eq(9)
      expect(clientes_gravados).to eq(['Ana Albuquerino', 'Carla Carvalhedo', 'Davi Dornelino', 'Fabio Ferreirinho', 'Gil Goncalvino'])
      # A coluna que diz quem é cliente não vira informação da pessoa.
      expect(account.contacts.find_by!(name: 'Ana Albuquerino').custom_attributes).to eq('cidade' => 'Campinas')
    end

    it '"toda linha com algo escrito" grava como cliente quem tem a célula preenchida, diga ela o que disser' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3, valores_cliente: { modo: 'preenchidas' })

      trazer(importacao)
      gravar_a_lista

      expect(account.contacts.count).to eq(8)
      expect(account.contacts.where.not(contact_type: :customer).pluck(:name)).to eq(['Elisa Esteveira'])
    end

    it 'com "sim, todas" ou "ainda não" traz sem a pergunta' do
      importacao = ler_planilha
      responder(importacao, clientes: 'ainda_nao')

      trazer(importacao)
      expect(response).to have_http_status(:ok)
      gravar_a_lista

      expect(account.contacts.count).to eq(8)
      expect(clientes_gravados).to eq([])
    end
  end

  describe 'o arquivo da contagem' do
    it 'guarda os valores fora das opções da importação e some no prazo da planilha' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 3)

      expect(importacao.reload.valores_cliente).to be_attached
      expect(JSON.parse(importacao.valores_cliente.download)).to include('coluna' => 3, 'preenchidas' => 8)

      prazo = CampaignImports::Config.original_file_retention
      travel_to((prazo + 1.hour).from_now) do
        perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { CampaignImports::PurgeExpiredFilesJob.perform_now }
      end

      expect(importacao.reload.valores_cliente).not_to be_attached
    end
  end
end
