require 'rails_helper'

# #2896 — "Trazer minha lista": quantas pessoas entram sem o telefone que estava escrito na planilha (`semTelefone`).
# O número é de quem entra de fato (ContactImports::Trazer::QuemEntra): acompanha cada conserto, cada linha deixada de
# fora e cada troca de linha repetida, na resposta de quem mexe na linha e no resumo da leitura. Todos os dados são
# inventados.
RSpec.describe 'Trazer minha lista: quem entra sem o telefone da planilha (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with trazer conferencia'

  # Linha 3: sem nome, com e-mail bom e o celular sem DDD. Consertado o nome, ela entra só com o e-mail.
  let(:sem_nome_e_sem_ddd) do
    <<~CSV
      Nome;Celular;E-mail
      Ana Albuquerino;11987650001;ana.albuquerino@exemplo.com.br
      ;98765-0002;bruno.brandolim@exemplo.com.br
      Carla Carvalhedo;;carla.carvalhedo@exemplo.com.br
    CSV
  end
  # As linhas 2 e 3 entram só com o e-mail (celular sem DDD, telefone fixo). A 4 e a 5 repetem o e-mail delas com outro
  # nome: a 4 traz um celular bom; a 5, um celular sem DDD.
  let(:repetidas_pelo_email) do
    <<~CSV
      Nome;Celular;E-mail
      Ana Albuquerino;98765-0001;ana.albuquerino@exemplo.com.br
      Bruno Brandolim;(11) 3333-0002;bruno.brandolim@exemplo.com.br
      Ana Outra;11987650004;ana.albuquerino@exemplo.com.br
      Bruno Outro;97650-0005;bruno.brandolim@exemplo.com.br
    CSV
  end

  # [quantas entram sem o telefone da planilha, quantas entram], na resposta de quem mexeu numa linha.
  def da_resposta
    response.parsed_body.values_at('semTelefone', 'entram')
  end

  def do_resumo(importacao)
    ler(importacao)['resumo'].values_at('semTelefone', 'entram')
  end

  it 'a linha consertada que entra só com o e-mail passa a contar; deixada de fora ou reaberta, deixa de contar' do
    importacao = ler_planilha(sem_nome_e_sem_ddd)
    expect(ler(importacao)['problemas'].pluck('linha', 'tipo')).to eq([[3, 'nome']])
    # A Carla não tinha telefone na planilha: nada se perde, e ela não conta.
    expect(do_resumo(importacao)).to eq([0, 2])

    consertar(importacao, 3, valor: 'Bruno Brandolim')
    expect(response).to have_http_status(:ok)
    expect(da_resposta).to eq([1, 3])
    expect(do_resumo(importacao)).to eq([1, 3])

    deixar_de_fora(importacao, 3)
    expect(da_resposta).to eq([0, 2])
    reabrir(importacao, 3)
    expect(da_resposta).to eq([0, 2])
    consertar(importacao, 3, valor: 'Bruno Brandolim')
    expect(da_resposta).to eq([1, 3])

    # Do telefone fica só a marca: o que estava escrito na célula não vai para o arquivo dos consertos, para as opções
    # nem para o resumo da leitura.
    guardado = ContactImports::Trazer::Consertos.new(importacao.reload).ler
    expect(guardado[3]).to include('sem_telefone' => true, 'valores' => { 'name' => 'Bruno Brandolim' })
    expect([guardado, importacao.options, importacao.validation_summary].to_json).not_to include('98765-0002', '987650002')
    expect(importacao.validation_summary).not_to have_key('sem_telefone')

    trazer(importacao)
    gravar_a_lista
    expect(account.contacts.pluck(:name, :phone_number))
      .to contain_exactly(['Ana Albuquerino', '+5511987650001'], ['Bruno Brandolim', nil], ['Carla Carvalhedo', nil])
  end

  it 'ler a planilha de novo mantém a conta: o conserto é conferido outra vez e a marca continua' do
    importacao = ler_planilha(sem_nome_e_sem_ddd)
    consertar(importacao, 3, valor: 'Bruno Brandolim')

    perform_enqueued_jobs { CampaignImports::ValidateJob.perform_later(importacao) }

    expect(estados(importacao)).to eq(3 => 'guardado')
    expect(do_resumo(importacao)).to eq([1, 3])
    expect(ContactImports::Trazer::Consertos.new(importacao.reload).ler[3]).to include('sem_telefone' => true)
  end

  # A linha com o telefone sem DDD E o e-mail errado aparece como problema de telefone: é o telefone que a tela pede, e
  # o e-mail não é aceito no lugar dele. Consertado o telefone, ela entra com ele.
  it 'a linha com telefone sem DDD e e-mail errado pede o telefone: consertada, entra com ele e não conta' do
    importacao = ler_planilha("Nome;Celular;E-mail\nAna Albuquerino;11987650001;\nDavi Dornelino;98765-0003;davi.dornelino.exemplo.com.br\n")
    expect(ler(importacao)['problemas'].pluck('linha', 'tipo')).to eq([[3, 'telefone']])

    consertar(importacao, 3, valor: 'davi.dornelino@exemplo.com.br')
    expect(response).to have_http_status(:unprocessable_entity)
    consertar(importacao, 3, valor: '11987650003')
    expect(da_resposta).to eq([0, 2])
  end

  # A linha aprovada que sai no lugar de uma repetida não entra: deixa de contar. A repetida que fica conta se ela
  # mesma entra sem o telefone que tem escrito.
  it 'na troca de linha repetida, conta só quem entra: a aprovada que saiu não conta, a repetida que ficou sem telefone conta' do
    importacao = ler_planilha(repetidas_pelo_email)
    expect(ler(importacao)['problemas'].pluck('linha', 'tipo', 'outraLinha')).to eq([[4, 'duplicada', 2], [5, 'duplicada', 3]])
    expect(do_resumo(importacao)).to eq([2, 2])

    # Fica a linha 4, que tem celular bom; a 2 sai. Sobra o Bruno da linha 3.
    consertar(importacao, 4, ficar_com: 4)
    expect(da_resposta).to eq([1, 2])
    # Fica a linha 5, que entra só com o e-mail; a 3 sai.
    consertar(importacao, 5, ficar_com: 5)
    expect(da_resposta).to eq([1, 2])
    expect(do_resumo(importacao)).to eq([1, 2])
    # A pessoa volta atrás na Ana: fica a linha 2, sem o telefone que estava escrito.
    consertar(importacao, 4, ficar_com: 2)
    expect(da_resposta).to eq([2, 2])
    expect(do_resumo(importacao)).to eq([2, 2])

    trazer(importacao)
    gravar_a_lista
    expect(account.contacts.pluck(:name, :phone_number)).to contain_exactly(['Ana Albuquerino', nil], ['Bruno Outro', nil])
  end

  # A mesma pessoa em duas linhas sem conflito vira uma só: fica contado o número que alguma delas tinha escrito.
  it 'nas linhas juntadas da mesma pessoa, conta quem ficou sem o telefone que uma delas tinha' do
    linhas = ['Nome;Celular;E-mail', 'Ana Albuquerino;98765-0001;ana.albuquerino@exemplo.com.br', 'Ana Albuquerino;;ana.albuquerino@exemplo.com.br',
              'Bruno Brandolim;;bruno.brandolim@exemplo.com.br', 'Bruno Brandolim;(11) 3333-0004;bruno.brandolim@exemplo.com.br',
              'Carla Carvalhedo;98765-0005;carla.carvalhedo@exemplo.com.br', 'Carla Carvalhedo;(11) 98765-0005;carla.carvalhedo@exemplo.com.br']
    importacao = ler_planilha("#{linhas.join("\n")}\n")

    # A Ana e o Bruno ficam sem o número que estava numa das linhas; a Carla fica com o telefone da outra linha dela.
    expect(ler(importacao)['resumo']).to include('juntadas' => 3, 'comProblema' => 0, 'entram' => 3, 'semTelefone' => 2)
    expect(conferido(importacao).pluck(:name, :phone_number))
      .to eq([['Ana Albuquerino', nil], ['Bruno Brandolim', nil], ['Carla Carvalhedo', '+5511987650005']])
  end

  # Trazer assim mesmo não perde o telefone para sempre: a planilha corrigida, trazida de novo por esta tela, acha a
  # pessoa pelo e-mail e completa o telefone que faltava (CampaignImports::ContactRow e
  # CampaignImports::ContactBlankFields).
  it 'a planilha corrigida, trazida de novo, completa o telefone de quem entrou só com o e-mail' do
    importacao = ler_planilha("Nome;Celular;E-mail\nAna Albuquerino;98765-0001;ana.albuquerino@exemplo.com.br\n")
    expect(do_resumo(importacao)).to eq([1, 1])
    trazer(importacao)
    expect(response.parsed_body).to eq('trazidaId' => importacao.id)
    gravar_a_lista
    expect(account.contacts.sole).to have_attributes(name: 'Ana Albuquerino', phone_number: nil, email: 'ana.albuquerino@exemplo.com.br')

    corrigida = ler_planilha("Nome;Celular;E-mail\nAna Albuquerino;(11) 98765-0001;ana.albuquerino@exemplo.com.br\n")
    expect(do_resumo(corrigida)).to eq([0, 1])
    trazer(corrigida)
    expect(response.parsed_body).to eq('trazidaId' => corrigida.id)
    gravar_a_lista

    expect(account.contacts.sole).to have_attributes(name: 'Ana Albuquerino', phone_number: '+5511987650001', email: 'ana.albuquerino@exemplo.com.br')
  end
end
