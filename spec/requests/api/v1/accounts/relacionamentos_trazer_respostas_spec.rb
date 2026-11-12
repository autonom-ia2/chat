require 'rails_helper'

# #2896 — "Trazer minha lista" (Fatia 2), a conferência: as respostas ("São clientes?" e de quem é o telefone duvidoso) e
# os destinos das colunas que não são alvo (cidade, telefone da empresa, cliente, informação com nome). As linhas com
# problema estão em relacionamentos_trazer_linhas_spec.rb; o trazer e quem pode entrar, em
# relacionamentos_trazer_trazer_spec.rb; o envio, a leitura e o histórico, em relacionamentos_trazer_spec.rb.
RSpec.describe 'Trazer minha lista: as respostas e as colunas da conferência (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with trazer conferencia'

  describe 'PATCH leituras/:id/respostas' do
    it 'a leitura pergunta se são clientes e de quem é o telefone que o sistema achou sem certeza' do
      corpo = ler(ler_planilha)

      expect(corpo['perguntas']).to eq([{ 'id' => 'clientes' }, { 'id' => 'telefone', 'coluna' => 'Celular', 'indice' => 1 }])
      expect(corpo['respostas']).to eq({})
      expect(corpo['colunas'][1]).to eq('indice' => 1, 'nome' => 'Celular', 'destino' => 'telefone', 'duvidosa' => true)
    end

    it '"sim, todas": todo mundo entra como cliente, sem ler a planilha de novo' do
      importacao = ler_planilha

      expect { responder(importacao, clientes: 'sim_todas') }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('id' => importacao.id, 'situacao' => 'pronta', 'respostas' => { 'clientes' => 'sim_todas' })
      expect(response.parsed_body['exemplos'].pluck('cliente')).to eq([true, true, true])
      expect(importacao.reload.options['trazer']).to eq('respostas' => { 'clientes' => 'sim_todas' })
    end

    it '"algumas": a coluna escolhida passa a dizer quem é cliente; outra resposta devolve a coluna para informação' do
      importacao = ler_planilha

      responder(importacao, clientes: 'algumas', coluna_cliente: 5)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 5)
      expect(response.parsed_body['colunas'][5]).to eq('indice' => 5, 'nome' => 'Cliente?', 'destino' => 'cliente')
      expect(response.parsed_body['exemplos'].pluck('cliente')).to eq([true, false, true])

      responder(importacao, clientes: 'algumas', coluna_cliente: 4)
      expect(response.parsed_body['colunas'].pluck('destino').last(3)).to eq(%w[cliente informacao informacao])
      expect(response.parsed_body['exemplos'].pluck('cliente')).to eq([false, false, false])

      responder(importacao, clientes: 'ainda_nao')
      expect(response.parsed_body['respostas']).to eq('clientes' => 'ainda_nao')
      expect(response.parsed_body['colunas'].pluck('destino').last(3)).to eq(%w[informacao informacao informacao])
      expect(response.parsed_body['exemplos'].pluck('cliente')).to eq([false, false, false])
    end

    it 'a resposta de quem é cliente acompanha as colunas: sem coluna cliente a pergunta volta sem resposta; com outra, é a nova' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 5, telefone: 'da_pessoa')

      # A pessoa manda a coluna "cliente" para outro lugar pela tela das colunas.
      trocar(importacao, 5, destino: 'informacao')
      expect(response.parsed_body['respostas']).to eq('telefone' => 'da_pessoa')
      expect(response.parsed_body['perguntas'].first).to eq('id' => 'clientes')
      expect(ler(importacao)['exemplos'].pluck('cliente')).to eq([false, false, false])

      # Outra coluna vira "cliente": é ela que a resposta mostra.
      trocar(importacao, 4, destino: 'cliente')
      expect(response.parsed_body['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 4, 'telefone' => 'da_pessoa')
      trocar(importacao, 4, destino: 'cidade')
      trocar(importacao, 5, destino: 'cliente')
      corpo = ler(importacao)
      expect(corpo['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 5, 'telefone' => 'da_pessoa')
      expect(corpo['exemplos'].pluck('cliente')).to eq([true, false, true])

      # Com duas colunas marcadas, a resposta continua na que a pessoa escolheu enquanto ela for "cliente".
      trocar(importacao, 4, destino: 'cliente')
      expect(response.parsed_body['respostas']).to include('clientes' => 'algumas', 'coluna_cliente' => 5)
      trocar(importacao, 5, destino: 'nao_guardar')
      expect(response.parsed_body['respostas']).to include('clientes' => 'algumas', 'coluna_cliente' => 4)
    end

    it 'a coluna marcada "cliente" pela tela das colunas vale como "algumas", menos quando a pessoa disse "sim, todas"' do
      importacao = ler_planilha

      trocar(importacao, 5, destino: 'cliente')
      expect(response.parsed_body['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 5)

      # "Ainda não" tira a coluna de "cliente"; marcada de novo, é ela que diz quem é.
      responder(importacao, clientes: 'ainda_nao')
      expect(response.parsed_body['respostas']).to eq('clientes' => 'ainda_nao')
      trocar(importacao, 5, destino: 'cliente')
      expect(response.parsed_body['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 5)

      # "Sim, todas" continua sendo a verdade com uma coluna marcada: todo mundo entra como cliente.
      responder(importacao, clientes: 'sim_todas')
      trocar(importacao, 5, destino: 'cliente')
      expect(response.parsed_body['respostas']).to eq('clientes' => 'sim_todas')
      expect(ler(importacao)['exemplos'].pluck('cliente')).to eq([true, true, true])
    end

    it 'recusa, sem mudar nada, a resposta que não existe e a coluna que não pode dizer quem é cliente' do
      importacao = ler_planilha

      [{ clientes: 'talvez' }, { telefone: 'do_vizinho' }, { clientes: 'sim_todas', telefone: 'do_vizinho' }].each do |respostas|
        responder(importacao, **respostas)

        expect(response).to have_http_status(:unprocessable_entity), respostas.inspect
        expect(response.parsed_body).to eq('error' => 'resposta_desconhecida')
      end
      [{ clientes: 'algumas' }, { clientes: 'algumas', coluna_cliente: 1 }, { clientes: 'algumas', coluna_cliente: 99 },
       { clientes: 'algumas', coluna_cliente: 'abc' }].each do |respostas|
        responder(importacao, **respostas)

        expect(response).to have_http_status(:unprocessable_entity), respostas.inspect
        expect(response.parsed_body).to eq('error' => 'coluna_desconhecida')
      end
      expect(importacao.reload.options['trazer']).to eq({})
    end

    it '"é da pessoa": a coluna deixa de ser duvidosa, sem ler a planilha de novo, e a pergunta continua respondida' do
      importacao = ler_planilha

      expect { responder(importacao, telefone: 'da_pessoa') }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['colunas'][1]).to eq('indice' => 1, 'nome' => 'Celular', 'destino' => 'telefone')
      expect(response.parsed_body['perguntas']).to eq([{ 'id' => 'clientes' }, { 'id' => 'telefone', 'coluna' => 'Celular', 'indice' => 1 }])
      expect(response.parsed_body['respostas']).to eq('telefone' => 'da_pessoa')
    end

    it '"é da empresa": a coluna vira telefone da empresa e a planilha é lida de novo; "é da pessoa" desfaz' do
      importacao = ler_planilha

      expect { responder(importacao, telefone: 'da_empresa') }.to have_enqueued_job(CampaignImports::ValidateJob).once
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')

      ler_de_novo
      corpo = ler(importacao)
      expect(corpo['colunas'][1]).to eq('indice' => 1, 'nome' => 'Celular', 'destino' => 'telefone_da_empresa')
      expect(corpo['perguntas'].last).to eq('id' => 'telefone', 'coluna' => 'Celular', 'indice' => 1)
      expect(corpo['respostas']).to eq('telefone' => 'da_empresa')
      # A Carla só tinha o telefone: sem ele, a linha dela fica sem contato.
      expect(corpo['resumo']).to eq('total' => 3, 'novas' => 2, 'completadas' => 0, 'comProblema' => 1, 'juntadas' => 0, 'entram' => 2)
      expect(corpo['problemas'].pluck('linha', 'tipo')).to eq([[4, 'sem_contato']])

      expect { responder(importacao, telefone: 'da_pessoa') }.to have_enqueued_job(CampaignImports::ValidateJob).once
      ler_de_novo
      corpo = ler(importacao)
      expect(corpo['colunas'][1]).to eq('indice' => 1, 'nome' => 'Celular', 'destino' => 'telefone')
      expect(corpo['respostas']).to eq('telefone' => 'da_pessoa')
      expect(corpo['resumo']).to include('comProblema' => 0)
    end

    it '"não usar": a coluna deixa de ser guardada e o valor dela sai das linhas' do
      importacao = ler_planilha

      responder(importacao, telefone: 'nao_usar')
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      ler_de_novo

      corpo = ler(importacao)
      expect(corpo['colunas'][1]).to eq('indice' => 1, 'nome' => 'Celular', 'destino' => 'nao_guardar')
      expect(corpo['respostas']).to eq('telefone' => 'nao_usar')
      expect(importacao.campaign_import_rows.pluck(:extra_values).flat_map(&:keys).uniq).to contain_exactly('Cidade', 'Cliente?', 'Fone 2')
    end

    it 'recusa tirar o telefone quando ele é a única coluna de contato, e não guarda a resposta' do
      importacao = ler_planilha("Nome;Celular;Empresa\nAna Albuquerino;11987650001;Padaria Bom Dia\n")

      %w[da_empresa nao_usar].each do |resposta|
        expect { responder(importacao, clientes: 'sim_todas', telefone: resposta) }.not_to have_enqueued_job(CampaignImports::ValidateJob)

        expect(response).to have_http_status(:unprocessable_entity), resposta
        expect(response.parsed_body).to eq('error' => 'sem_contato')
      end
      expect(importacao.reload).to be_ready_to_confirm
      expect(importacao.options['trazer']).to eq({})
    end

    it 'aceita de novo as mesmas respostas sem ler a planilha outra vez' do
      importacao = ler_planilha
      respostas = { clientes: 'algumas', coluna_cliente: 5, telefone: 'da_pessoa' }
      responder(importacao, **respostas)

      expect { responder(importacao, **respostas) }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 5, 'telefone' => 'da_pessoa')
    end

    it 'as duas respostas num pedido só: a planilha é lida de novo uma vez e as duas valem' do
      importacao = ler_planilha
      trocar(importacao, 5, destino: 'nao_guardar')

      expect { responder(importacao, clientes: 'algumas', coluna_cliente: 5, telefone: 'da_empresa') }
        .to have_enqueued_job(CampaignImports::ValidateJob).once
      ler_de_novo

      corpo = ler(importacao)
      expect(corpo['colunas'].pluck('destino')).to eq(%w[nome telefone_da_empresa email empresa informacao cliente informacao])
      expect(corpo['respostas']).to eq('clientes' => 'algumas', 'coluna_cliente' => 5, 'telefone' => 'da_empresa')
      expect(corpo['exemplos'].pluck('cliente')).to eq([true, false])
    end

    it 'recusa enquanto a planilha está sendo lida' do
      importacao = ler_planilha
      importacao.update!(status: :validating)

      responder(importacao, clientes: 'sim_todas')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'leitura_nao_pronta')
    end

    it 'a pergunta do telefone acompanha a coluna: trocado o telefone de coluna, a resposta antiga deixa de valer' do
      importacao = ler_planilha
      responder(importacao, telefone: 'da_pessoa')

      trocar(importacao, 6, destino: 'telefone')
      ler_de_novo
      corpo = ler(importacao)

      destinos = %w[nome informacao email empresa informacao informacao telefone]
      expect(corpo['colunas'].pluck('destino')).to eq(destinos)
      expect(corpo['perguntas']).to eq([{ 'id' => 'clientes' }])
      expect(corpo['respostas']).to eq({})

      # Responder agora não mexe na coluna antiga nem tira a que a pessoa escolheu.
      expect { responder(importacao, telefone: 'da_empresa') }.not_to have_enqueued_job(CampaignImports::ValidateJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'pergunta_desconhecida')
      expect(ler(importacao)['colunas'].pluck('destino')).to eq(destinos)
    end

    it 'só aceita o telefone da empresa com coluna de empresa na planilha e Empresas ligada na conta' do
      importacao = ler_planilha
      expect(ler(importacao)).to include('tem_empresa' => true)

      account.disable_features!('companies')
      expect(ler(importacao)).to include('tem_empresa' => false)
      pedidos = [-> { trocar(importacao, 6, destino: 'telefone_da_empresa') },
                 -> { responder(importacao, clientes: 'sim_todas', telefone: 'da_empresa') }]
      pedidos.each do |pedir|
        expect { pedir.call }.not_to have_enqueued_job(CampaignImports::ValidateJob)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'sem_empresa')
      end
      expect(importacao.reload.options['trazer']).to eq({})

      account.enable_features!('companies')
      sem_coluna = ler_planilha("Nome;Celular;E-mail;Fone 2\nAna Albuquerino;11987650001;ana@exemplo.com.br;1133330001\n")
      expect(ler(sem_coluna)).to include('tem_empresa' => false)
      trocar(sem_coluna, 3, destino: 'telefone_da_empresa')
      expect(response.parsed_body).to eq('error' => 'sem_empresa')
      responder(sem_coluna, telefone: 'da_empresa')
      expect(response.parsed_body).to eq('error' => 'sem_empresa')
      expect(sem_coluna.reload.options['trazer']).to eq({})
    end

    it 'a coluna de empresa deixa de ser empresa: o telefone da empresa volta a ser informação' do
      importacao = ler_planilha
      trocar(importacao, 6, destino: 'telefone_da_empresa')
      expect(response).to have_http_status(:ok)

      trocar(importacao, 3, destino: 'informacao')
      ler_de_novo
      corpo = ler(importacao)

      expect(corpo['colunas'].pluck('destino').values_at(3, 6)).to eq(%w[informacao informacao])
      expect(corpo).to include('tem_empresa' => false)
    end

    it 'guarda só códigos e índices: nenhum valor da planilha vai para as opções da importação' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 5, telefone: 'da_pessoa')
      trocar(importacao, 6, destino: 'telefone_da_empresa')

      expect(importacao.reload.options['trazer']).to eq(
        'destinos' => { '5' => 'cliente', '6' => 'telefone_da_empresa' },
        'respostas' => { 'clientes' => 'algumas', 'coluna_cliente' => 5, 'telefone' => 'da_pessoa', 'coluna_telefone' => 1 }
      )
      expect(importacao.options.to_json).not_to include(*valores_da_planilha)
    end
  end

  describe 'PATCH leituras/:id/colunas/:indice com os destinos que não são alvo' do
    it 'manda a coluna para a cidade, o telefone da empresa ou o cliente na hora, sem ler a planilha de novo' do
      importacao = ler_planilha

      { 4 => 'cidade', 6 => 'telefone_da_empresa', 5 => 'cliente' }.each do |indice, destino|
        expect { trocar(importacao, indice, destino: destino) }.not_to have_enqueued_job(CampaignImports::ValidateJob)

        expect(response).to have_http_status(:ok), destino
        expect(response.parsed_body).to include('id' => importacao.id, 'situacao' => 'pronta')
        expect(response.parsed_body['colunas'][indice]).to eq('indice' => indice, 'nome' => importacao.schema_resolution['columns'][indice]['header'],
                                                              'destino' => destino)
      end
      expect(importacao.reload.options['trazer']['destinos']).to eq('4' => 'cidade', '5' => 'cliente', '6' => 'telefone_da_empresa')
      expect(importacao.campaign_import_rows.order(:row_number).first.extra_values)
        .to eq('Cidade' => 'Campinas', 'Cliente?' => 'Sim', 'Fone 2' => '1133330001')
    end

    it 'a troca que vale na hora devolve a leitura inteira, igual à que o GET devolve' do
      importacao = ler_planilha
      responder(importacao, clientes: 'algumas', coluna_cliente: 5)

      # A coluna que era "cliente" vai para outro lugar: a resposta cai e a tela fica sabendo na mesma resposta.
      trocar(importacao, 5, destino: 'cidade')

      expect(response).to have_http_status(:ok)
      troca = response.parsed_body
      expect(troca).to include(
        'situacao' => 'pronta', 'tem_empresa' => true, 'respostas' => {},
        'perguntas' => [{ 'id' => 'clientes' }, { 'id' => 'telefone', 'coluna' => 'Celular', 'indice' => 1 }]
      )
      expect(troca['colunas'][5]).to eq('indice' => 5, 'nome' => 'Cliente?', 'destino' => 'cidade')
      expect(troca.keys).to include('arquivo', 'valores', 'resumo', 'exemplos', 'problemas', 'problemas_total', 'pagina', 'por_pagina')
      expect(troca).to eq(ler(importacao))

      # Com a planilha lida de novo a resposta continua sendo só "lendo".
      trocar(importacao, 6, destino: 'telefone')
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
    end

    it 'guarda o nome e o "para que serve" da informação, e os esquece quando a coluna vai para outro destino' do
      importacao = ler_planilha

      trocar(importacao, 4, destino: 'informacao', nome: '  Bairro  ', para_que_serve: 'Onde a pessoa mora')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['colunas'][4])
        .to eq('indice' => 4, 'nome' => 'Cidade', 'destino' => 'informacao',
               'campo' => { 'nome' => 'Bairro', 'para_que_serve' => 'Onde a pessoa mora' })

      trocar(importacao, 4, destino: 'informacao', para_que_serve: 'Bairro da entrega')
      expect(response.parsed_body['colunas'][4]['campo']).to eq('nome' => 'Bairro', 'para_que_serve' => 'Bairro da entrega')

      trocar(importacao, 4, destino: 'cidade')
      trocar(importacao, 4, destino: 'informacao')
      expect(response.parsed_body['colunas'][4]['campo']).to eq('nome' => 'Cidade', 'para_que_serve' => '')
    end

    # F6: o byte nulo não pode chegar ao banco (jsonb o recusa e a rota quebraria).
    it 'tira os caracteres de controle do nome e do "para que serve" da informação' do
      importacao = ler_planilha

      trocar(importacao, 4, destino: 'informacao', nome: "Bai\u0000rro\u0007", para_que_serve: "Onde a\u0000 pessoa\tmora\u007F")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['colunas'][4]['campo']).to eq('nome' => 'Bairro', 'para_que_serve' => 'Onde a pessoa mora')
      expect(importacao.reload.options['trazer']['campos']).to eq('4' => { 'nome' => 'Bairro', 'para_que_serve' => 'Onde a pessoa mora' })
    end

    it 'recusa o nome e o "para que serve" longos demais, sem guardar nada' do
      importacao = ler_planilha

      [{ nome: 'n' * 256 }, { para_que_serve: 'p' * 1001 }].each do |campo|
        trocar(importacao, 4, destino: 'informacao', **campo)

        expect(response).to have_http_status(:unprocessable_entity), campo.keys.inspect
        expect(response.parsed_body).to eq('error' => 'valor_invalido', 'motivo' => 'muito_longo')
      end
      expect(importacao.reload.options['trazer']).to eq({})

      trocar(importacao, 4, destino: 'informacao', nome: 'n' * 255, para_que_serve: 'p' * 1000)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['colunas'][4]['campo']).to eq('nome' => 'n' * 255, 'para_que_serve' => 'p' * 1000)
    end

    it 'lê a planilha de novo quando a coluna que não era guardada passa a ter destino' do
      importacao = ler_planilha
      trocar(importacao, 4, destino: 'nao_guardar')
      expect(importacao.campaign_import_rows.pluck(:extra_values).flat_map(&:keys)).not_to include('Cidade')

      expect { trocar(importacao, 4, destino: 'cidade') }.to have_enqueued_job(CampaignImports::ValidateJob).once
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      ler_de_novo

      expect(ler(importacao)['colunas'][4]).to include('destino' => 'cidade')
      expect(importacao.campaign_import_rows.order(:row_number).first.extra_values).to include('Cidade' => 'Campinas')
    end
  end

  describe 'a troca que deixaria a pessoa sem saída' do
    # G1: a própria coluna de empresa não pode virar telefone da empresa: depois da troca não haveria empresa.
    it 'recusa mandar a coluna de empresa para o telefone da empresa' do
      importacao = ler_planilha

      expect { trocar(importacao, 3, destino: 'telefone_da_empresa') }.not_to have_enqueued_job(CampaignImports::ValidateJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'sem_empresa')
      expect(importacao.reload).to be_ready_to_confirm
      expect(ler(importacao)['colunas'][3]).to include('destino' => 'empresa')
    end

    # Rodada 5: entre a troca e o começo da leitura nova, a leitura velha não pode ser trazida (outra aba, a API).
    it 'recusa o "Trazer" e a rota antiga de confirmar entre a troca que lê de novo e o começo da leitura' do
      importacao = ler_planilha
      trocar(importacao, 6, destino: 'telefone')
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      expect(importacao.reload).not_to be_ready_to_confirm

      expect { post "#{base}/leituras/#{importacao.id}/trazer", headers: cabecalhos(admin) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'leitura_nao_pronta')
      expect { post "/api/v1/accounts/#{account.id}/contact_imports/#{importacao.id}/confirm", headers: cabecalhos(admin) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unprocessable_entity)
      expect(importacao.reload).not_to be_ready_to_confirm

      # A leitura nova termina e a lista volta a poder ser trazida.
      ler_de_novo
      trazer(importacao)
      expect(response).to have_http_status(:ok)
    end

    # M5: a troca que faz a leitura falhar é desfeita pelo servidor, uma vez só.
    describe 'quando a planilha lida de novo não dá leitura' do
      # Colunas: 0 Nome, 1 Celular, 2 Obs. Com a coluna Obs no lugar do telefone ninguém tem contato que valha.
      let(:planilha) { "Nome;Celular;Obs\nAna Albuquerino;11987650001;x\nCarla Carvalhedo;(11) 2345-678;y\n" }

      it 'volta ao que era antes da troca, com o que a pessoa tinha consertado, e avisa; o aviso some na escrita seguinte' do
        importacao = ler_planilha
        consertar(importacao, 3, valor: '11987650003')
        antes = ler(importacao)
        expect(antes).not_to have_key('aviso')

        trocar(importacao, 2, destino: 'telefone')
        expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
        ler_de_novo

        expect(ler(importacao)).to eq(antes.merge('aviso' => 'mudanca_desfeita'))
        expect(response.parsed_body['problemas'].first).to include('linha' => 3, 'estado' => 'guardado', 'corrigido' => '+5511987650003')
        expect(importacao.reload.options['trazer']).to eq('aviso' => 'mudanca_desfeita')

        trocar(importacao, 2, destino: 'cidade')
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).not_to have_key('aviso')
        expect(ler(importacao)).not_to have_key('aviso')
        expect(importacao.reload.options['trazer']).to eq('destinos' => { '2' => 'cidade' })
      end

      it 'se a leitura refeita também falha, a lista fica como falhou, sem tentar de novo' do
        importacao = ler_planilha
        trocar(importacao, 2, destino: 'telefone')
        leituras = 0
        allow(CampaignImports::Parser).to receive(:new) do
          leituras += 1
          raise IOError
        end

        ler_de_novo

        expect(leituras).to eq(2)
        expect(ler(importacao)).to eq('id' => importacao.id, 'situacao' => 'falhou', 'erro' => 'leitura')
        expect(importacao.reload.options['trazer']).not_to have_key('anterior')
      end
    end
  end
end
