require 'rails_helper'

# #2896 — "Trazer minha lista" com uma planilha parecida com a que uma corretora pequena exporta, pelas rotas da tela:
# enviar, conferir, consertar e trazer; e a mesma planilha de novo, que não duplica ninguém. Todos os dados são inventados.
#
# A planilha (300 linhas, separadas por ponto e vírgula, com a marca de UTF-8 que o Excel põe no começo):
#   Nome do Cliente; Celular; E-mail; CPF/CNPJ; Cidade; Data de Nascimento
# - linhas 2 a 241: 240 pessoas, com o celular escrito de quatro jeitos, e-mail em duas de cada três, a cidade vazia em
#   uma de cada quatro e a data em dd/mm/aaaa. As 20 primeiras a conta já tinha, pelo telefone;
# - 242 a 261: as pessoas 21 a 40 de novo, com o nome em maiúsculas e o celular escrito de outro jeito (a mesma pessoa);
# - 262 a 271: o celular das pessoas 41 a 50 com outro nome (repetida: a pessoa escolhe com qual fica);
# - 272 a 281: telefone que não é celular, sem e-mail;
# - 282 a 287: e-mail sem arroba, sem telefone;
# - 288 a 293: sem telefone e sem e-mail;
# - 294 a 297: sem nome, com celular;
# - 298 a 301: telefone fixo e e-mail bom (entra só com o e-mail);
# - 302: uma linha em branco no fim.
RSpec.describe 'Trazer minha lista: a planilha de uma corretora, duas vezes (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with trazer conferencia'

  let(:cidades) { ['São Paulo', 'Santo André', 'Guarulhos'] }
  let(:planilha) do
    linhas = pessoas + as_mesmas_de_novo + repetidas_com_outro_nome + com_telefone_ruim + com_email_ruim + sem_contato + sem_nome + so_com_email
    texto = CSV.generate(col_sep: ';') do |csv|
      csv << ['Nome do Cliente', 'Celular', 'E-mail', 'CPF/CNPJ', 'Cidade', 'Data de Nascimento']
      linhas.each { |linha| csv << linha }
      csv << ['', '', '', '', '', '']
    end
    "﻿#{texto}"
  end

  before do
    account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'data_de_nascimento',
                                                 attribute_display_name: 'Data de Nascimento', attribute_display_type: :date)
    # As 20 primeiras pessoas da planilha já são contatos da conta, com outro nome; as 5 primeiras já têm cidade.
    (1..20).each do |numero|
      create(:contact, account: account, name: "Antigo #{numero}", phone_number: "+55#{celular(numero)}", email: nil,
                       additional_attributes: numero <= 5 ? { 'city' => 'Sorocaba' } : {})
    end
  end

  # 11 9765X-XXXX: o DDD e nove dígitos.
  def celular(numero)
    format('119765%05d', numero)
  end

  # O mesmo celular, de quatro jeitos que a planilha de verdade traz.
  def celular_escrito(numero, jeito = numero)
    ddd, primeira, segunda = celular(numero).then { |digitos| [digitos[0, 2], digitos[2, 5], digitos[7, 4]] }
    jeitos = ["(#{ddd}) #{primeira}-#{segunda}", "#{ddd} #{primeira} #{segunda}", "#{ddd}#{primeira}#{segunda}", "+55 #{ddd} #{primeira}-#{segunda}"]
    jeitos[jeito % 4]
  end

  def nome(numero)
    format('Cliente %03d Conceição', numero)
  end

  def email(numero)
    format('cliente.%03d@exemplo.com.br', numero)
  end

  def documento(numero)
    (numero % 25).zero? ? format('00.000.%03d/0001-00', numero) : format('000.000.%03d-00', numero)
  end

  def cidade(numero)
    (numero % 4).zero? ? '' : cidades[numero % 3]
  end

  # A pessoa 9 tem uma data que não existe; uma de cada dez não tem data.
  def nascimento(numero)
    return '31/02/1990' if numero == 9
    return '' if (numero % 10).zero?

    format('%<dia>02d/%<mes>02d/%<ano>04d', dia: (numero % 28) + 1, mes: (numero % 12) + 1, ano: 1950 + (numero % 50))
  end

  def pessoas
    (1..240).map do |numero|
      [nome(numero), celular_escrito(numero), (numero % 3).zero? ? '' : email(numero), documento(numero), cidade(numero), nascimento(numero)]
    end
  end

  def as_mesmas_de_novo
    (21..40).map { |numero| [nome(numero).upcase, celular_escrito(numero, numero + 1), email(numero), '', '', ''] }
  end

  def repetidas_com_outro_nome
    (41..50).map { |numero| ["Maria Outra #{numero}", celular_escrito(numero, numero + 2), '', '', 'Osasco', ''] }
  end

  def com_telefone_ruim
    (1..10).map do |numero|
      ["Telefone Ruim #{numero}", numero.odd? ? format('(11) 3333-%04d', numero) : format('97650-9%03d', numero), '', '', '', '']
    end
  end

  def com_email_ruim
    (1..6).map { |numero| ["Email Ruim #{numero}", '', "email.ruim.#{numero}.exemplo.com.br", '', '', ''] }
  end

  def sem_contato
    (1..6).map { |numero| ["Sem Contato #{numero}", '', '', documento(900 + numero), 'Barueri', ''] }
  end

  def sem_nome
    (1..4).map { |numero| ['', celular_escrito(600 + numero), '', '', '', ''] }
  end

  def so_com_email
    (1..4).map do |numero|
      ["Fixo Com Email #{numero}", format('(11) 3222-%04d', numero), "fixo.com.email.#{numero}@exemplo.com.br", '', 'Diadema', '']
    end
  end

  # A coluna do nome tem um título que o leitor não conhece ("Nome do Cliente"): a pessoa diz na tela que ela é o nome,
  # e a planilha é lida de novo.
  def ler_e_apontar_o_nome
    importacao = ler_planilha
    expect(ler(importacao)['colunas'].pluck('nome', 'destino')).to eq(
      [['Nome do Cliente', 'informacao'], %w[Celular telefone], %w[E-mail email], ['CPF/CNPJ', 'informacao'], %w[Cidade informacao],
       ['Data de Nascimento', 'informacao']]
    )
    trocar(importacao, 0, destino: 'nome')
    expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
    ler_de_novo
    importacao
  end

  def pessoa(numero)
    account.contacts.find_by!(phone_number: "+55#{celular(numero)}")
  end

  def repetidos(coluna)
    account.contacts.where.not(coluna => [nil, '']).group(coluna).having('COUNT(*) > 1').count
  end

  # Um exemplo só, de propósito: é a mesma planilha do começo ao fim, e depois de novo.
  it 'envia, confere, conserta e traz; a mesma planilha de novo não duplica ninguém' do # rubocop:disable RSpec/ExampleLength
    importacao = ler_e_apontar_o_nome

    # Conferir: 300 linhas viram 280 (20 eram a mesma pessoa de outra linha); 36 precisam da pessoa.
    leitura = ler(importacao)
    expect(leitura['colunas'].pluck('nome', 'destino')).to eq(
      [['Nome do Cliente', 'nome'], %w[Celular telefone], %w[E-mail email], ['CPF/CNPJ', 'informacao'], %w[Cidade informacao],
       ['Data de Nascimento', 'informacao']]
    )
    expect(leitura['resumo']).to eq('total' => 280, 'novas' => 224, 'completadas' => 20, 'comProblema' => 36, 'juntadas' => 20,
                                    'semTelefone' => 4, 'entram' => 244, 'clientes' => 0)
    expect(leitura['problemas'].pluck('linha', 'tipo')).to eq(
      (262..271).map { |linha| [linha, 'duplicada'] } + (272..281).map { |linha| [linha, 'telefone'] } +
      (282..287).map { |linha| [linha, 'email'] } + (288..293).map { |linha| [linha, 'sem_contato'] } + (294..297).map { |linha| [linha, 'nome'] }
    )

    # As respostas e as colunas: todas são clientes e a cidade vai para a cidade.
    responder(importacao, clientes: 'sim_todas')
    expect(response).to have_http_status(:ok)
    trocar(importacao, 4, destino: 'cidade')
    expect(response).to have_http_status(:ok)

    # Consertar o que precisa: um de cada tipo, e uma linha fica de fora.
    consertar(importacao, 262, ficar_com: 262)
    consertar(importacao, 272, valor: '(11) 97650-9001')
    deixar_de_fora(importacao, 273)
    consertar(importacao, 282, valor: 'email.bom.1@exemplo.com.br')
    consertar(importacao, 288, valor: '11976509002')
    consertar(importacao, 294, valor: 'Gilberto Nomeado')
    leitura = ler(importacao)
    expect(leitura['problemas'].pluck('linha', 'estado').reject { |_linha, estado| estado == 'aberto' }).to eq(
      [[262, 'guardado'], [272, 'guardado'], [273, 'deixado'], [282, 'guardado'], [288, 'guardado'], [294, 'guardado']]
    )
    # As 244 da leitura, mais as cinco consertadas, menos a linha 42, que deu lugar à repetida que a pessoa manteve.
    expect(leitura['resumo']).to include('entram' => 248, 'clientes' => 248)

    # Trazer.
    trazer(importacao)
    expect(response.parsed_body).to eq('trazidaId' => importacao.id)
    gravar_a_lista
    expect(importacao.reload).to be_completed
    get "#{base}/listas/#{importacao.id}/andamento", headers: cabecalhos(admin)
    expect(response.parsed_body).to eq('porcentagem' => 100, 'situacao' => 'pronto', 'total' => 248, 'novas' => 228, 'completadas' => 20)
    expect(account.contacts.count).to eq(248)
    expect(repetidos(:phone_number)).to be_empty
    expect(repetidos(:email)).to be_empty
    expect(account.contacts.pluck(:contact_type).uniq).to eq(['customer'])

    # O celular fica igual, escrito do jeito que for; a célula vazia não vira nada.
    expect((101..104).map { |numero| pessoa(numero).phone_number }).to eq((101..104).map { |numero| "+55#{celular(numero)}" })
    expect(pessoa(104)).to have_attributes(name: 'Cliente 104 Conceição', email: 'cliente.104@exemplo.com.br')
    expect(pessoa(104).additional_attributes).not_to include('city')
    expect(pessoa(105)).to have_attributes(email: nil, additional_attributes: include('city' => 'São Paulo'))
    # A data em dd/mm/aaaa entra como data; a que não existe e a célula vazia ficam de fora. O documento entra como veio.
    expect(pessoa(107).custom_attributes).to eq('cpfcnpj' => '000.000.107-00', 'data_de_nascimento' => '1957-12-24')
    expect(pessoa(9).custom_attributes).to eq('cpfcnpj' => '000.000.009-00')
    expect(pessoa(110).custom_attributes).to eq('cpfcnpj' => '000.000.110-00')
    expect(pessoa(125).custom_attributes).to include('cpfcnpj' => '00.000.125/0001-00')

    # Quem já existia é completado, nunca sobrescrito.
    expect(pessoa(1)).to have_attributes(name: 'Antigo 1', email: 'cliente.001@exemplo.com.br', additional_attributes: include('city' => 'Sorocaba'))
    expect(pessoa(6)).to have_attributes(name: 'Antigo 6', email: nil, additional_attributes: include('city' => 'São Paulo'))
    # A mesma pessoa em duas linhas vira uma só, com o e-mail que só a segunda linha tinha.
    expect(pessoa(21)).to have_attributes(name: 'Cliente 021 Conceição', email: 'cliente.021@exemplo.com.br')
    # A repetida que a pessoa manteve entra no lugar da outra; as que ficaram abertas não entram.
    expect(pessoa(41)).to have_attributes(name: 'Maria Outra 41', email: nil)
    expect(pessoa(42).name).to eq('Cliente 042 Conceição')
    expect(account.contacts.where("name LIKE 'Maria Outra%'").count).to eq(1)
    # As consertadas entram com o que a pessoa escreveu; a deixada de fora e as abertas, não.
    expect(account.contacts.find_by!(name: 'Telefone Ruim 1').phone_number).to eq('+5511976509001')
    expect(account.contacts.find_by!(name: 'Email Ruim 1').email).to eq('email.bom.1@exemplo.com.br')
    expect(account.contacts.find_by!(name: 'Sem Contato 1').phone_number).to eq('+5511976509002')
    expect(account.contacts.find_by!(name: 'Gilberto Nomeado').phone_number).to eq("+55#{celular(601)}")
    expect(account.contacts.where("name LIKE 'Telefone Ruim%' OR name LIKE 'Email Ruim%' OR name LIKE 'Sem Contato%'").count).to eq(3)
    expect(account.contacts.where(name: [nil, '']).count).to eq(0)
    # O telefone fixo não entra; a pessoa entra pelo e-mail.
    expect(account.contacts.find_by!(name: 'Fixo Com Email 1')).to have_attributes(phone_number: nil, email: 'fixo.com.email.1@exemplo.com.br')

    # A mesma planilha de novo: todo mundo que entra já é da conta, e ninguém é criado.
    de_novo = ler_e_apontar_o_nome
    expect(ler(de_novo)['resumo']).to eq('total' => 280, 'novas' => 0, 'completadas' => 244, 'comProblema' => 36, 'juntadas' => 20,
                                         'semTelefone' => 4, 'entram' => 244, 'clientes' => 0)
    trazer(de_novo)
    expect(response.parsed_body).to eq('trazidaId' => de_novo.id)
    gravar_a_lista
    expect(de_novo.reload).to be_completed
    get "#{base}/listas/#{de_novo.id}/andamento", headers: cabecalhos(admin)
    expect(response.parsed_body).to eq('porcentagem' => 100, 'situacao' => 'pronto', 'total' => 244, 'novas' => 0, 'completadas' => 244)
    expect(account.contacts.count).to eq(248)
    expect(repetidos(:phone_number)).to be_empty
    expect(repetidos(:email)).to be_empty
    # A segunda vez só completa: a repetida mantida continua com o nome dela e ganha o e-mail da linha 42.
    expect(pessoa(41)).to have_attributes(name: 'Maria Outra 41', email: 'cliente.041@exemplo.com.br')
    expect(pessoa(1)).to have_attributes(name: 'Antigo 1', additional_attributes: include('city' => 'Sorocaba'))
  end
end
