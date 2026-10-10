# Casos de controle (#1246), escritos DEPOIS do ajuste do prompt e nunca usados para ajustá-lo.
# Medem se o resultado da bateria principal generaliza para cabeçalhos e estruturas novos.
module BaseDeClientesEval::Casos::Controle
  extend BaseDeClientesEval::CasosDsl
  D = BaseDeClientesEval::Dados

  caso 'h01', 'Fone e correio eletrônico', nivel: 2,
                                           alvos: { phone: 'Fone', email: 'Correio eletrônico', name: 'Nome do Cliente' } do
    aba(['Nome do Cliente', 'Fone', 'Correio eletrônico'], 40, nome: 'Clientes') { [D.nome, D.celular, D.email] }
  end

  caso 'h02', 'Export de banco em snake_case', nivel: 2,
                                               alvos: { phone: 'cliente_celular', email: 'cliente_email', name: 'cliente_nome',
                                                        company: 'cliente_empresa' } do
    aba(%w[id cliente_nome cliente_celular cliente_email cliente_empresa created_at], 40) do |i|
      [i.to_s, D.nome, D.celular(:digitos), D.email, D.empresa, '2026-09-01 10:00:00']
    end
  end

  caso 'h03', 'Telefone residencial e celular abreviados', nivel: 2, opcoes: { col_sep: ';' },
                                                           alvos: { phone: 'TEL CEL', email: 'EMAIL', name: 'NOME' } do
    aba(['NOME', 'TEL RES', 'TEL CEL', 'EMAIL'], 40) { [D.nome.upcase, D.fixo, D.celular, D.email] }
  end

  caso 'h04', 'Whats, e-mail corporativo e organização', nivel: 2,
                                                         alvos: { phone: 'Whats', email: 'E-mail Corporativo', name: 'Contato',
                                                                  company: 'Organização' } do
    aba(['Contato', 'Whats', 'E-mail Corporativo', 'Organização'], 40) { [D.nome, D.celular, D.email, D.empresa] }
  end

  caso 'h05', 'CRM em inglês: Mobile, Work email, Account', nivel: 2,
                                                            alvos: { phone: 'Mobile', email: 'Work email', name: 'Full name',
                                                                     company: 'Account' } do
    aba(['Full name', 'Mobile', 'Work email', 'Account', 'Owner'], 40) { [D.nome, D.celular(:e164), D.email, D.empresa, D.nome] }
  end

  caso 'h06', 'Cabeçalho na linha 5 e primeira coluna vazia', nivel: 2, formato: 'xlsx',
                                                              alvos: { phone: 'Celular', email: 'E-mail', name: 'Nome' } do
    aba(['', 'Nome', 'Celular', 'E-mail'], 40, antes: [['', 'EMPRESA XYZ LTDA'], ['', 'Lista de clientes ativos'], [], []]) do
      ['', D.nome, D.celular, D.email]
    end
  end

  caso 'h07', 'Clínica: paciente, convênio e dentista', nivel: 3,
                                                        alvos: { phone: 'Celular', email: 'E-mail', name: 'Paciente', company: [nil, 'Convênio'] },
                                                        pode_perguntar: %i[company] do
    aba(%w[Paciente Convênio Celular E-mail Dentista], 40) do
      [D.nome, D.sorteio(%w[Amil Bradesco Odontoprev Particular]), D.celular, D.email, "Dr. #{D.nome}"]
    end
  end

  caso 'h08', 'Escola: aluno e responsável', nivel: 3,
                                             alvos: { phone: 'Celular do responsável', email: 'E-mail do responsável',
                                                      name: %w[Responsável Aluno] },
                                             pode_perguntar: %i[name] do
    aba(['Aluno', 'Responsável', 'Celular do responsável', 'E-mail do responsável', 'Turma'], 40) do
      [D.nome, D.nome, D.celular, D.email, '5º ano B']
    end
  end

  caso 'h09', 'Três telefones: fixo, celular e outro', nivel: 3,
                                                       alvos: { phone: 'Telefone 2', email: 'Email', name: 'Nome' },
                                                       pode_perguntar: %i[phone] do
    aba(['Nome', 'Telefone 1', 'Telefone 2', 'Telefone 3', 'Email'], 40) do
      [D.nome, D.fixo, D.chance(0.9) ? D.celular : vazio, D.chance(0.3) ? D.celular : vazio, D.email]
    end
  end

  caso 'h10', 'Só uma coluna de números', nivel: 3, alvos: { phone: 'Números' } do
    aba(['Números'], 40) { [D.celular_misto] }
  end

  caso 'h11', 'Celular com DDD e e-mail opcional', nivel: 2,
                                                   alvos: { phone: 'Celular (com DDD)', email: 'E-mail (opcional)', name: 'Nome' } do
    aba(['Nome', 'Celular (com DDD)', 'CPF/CNPJ', 'Data últ. compra', 'Valor total', 'E-mail (opcional)'], 40) do
      [D.nome, D.celular, D.chance(0.5) ? D.cpf : D.cnpj, D.data_br(0..2), D.valor_br, D.chance(0.4) ? D.email : vazio]
    end
  end

  caso 'h12', 'Excel: DDD+Celular como número, cabeçalho na linha 2', nivel: 3, formato: 'xlsx',
                                                                      alvos: { phone: 'DDD+Celular', email: 'Email', name: 'Nome' } do
    aba(%w[Nome DDD+Celular Email], 40, antes: [['Base 2026']]) do
      [D.nome, D::Celula.new(valor: D.celular_digitos.to_i, alcanca: true), D.chance(0.3) ? D.email : vazio]
    end
  end

  caso 'h13', 'Dois cabeçalhos iguais "Telefone"', nivel: 3, alvos: { phone: 'Telefone', email: 'Email', name: 'Nome' },
                                                   nota: 'O primeiro "Telefone" é fixo, o segundo é celular.' do
    aba(%w[Nome Telefone Telefone Email], 40) { [D.nome, D.fixo, D.celular, D.email] }
  end

  caso 'h14', 'Cabeçalhos com emoji', nivel: 2,
                                      alvos: { phone: '📱 WhatsApp', email: '✉️ Email', name: '👤 Nome', company: '🏢 Empresa' } do
    aba(['👤 Nome', '📱 WhatsApp', '✉️ Email', '🏢 Empresa'], 40) { [D.nome, D.celular, D.email, D.empresa] }
  end

  caso 'h15', 'Export de marketing com UTMs', nivel: 2,
                                              alvos: { phone: 'phone_number', email: 'email', name: 'first_name' } do
    aba(%w[created_at utm_source utm_campaign first_name last_name email phone_number city], 40) do
      ['2026-10-01T12:00:00Z', 'facebook', 'black-friday', D.primeiro_nome, D.sobrenome, D.email, D.celular(:e164), D.cidade]
    end
  end

  caso 'h16', 'Facebook Lead Ads (telefone com "p:")', nivel: 3,
                                                       alvos: { phone: 'phone_number', email: 'email', name: 'full_name' } do
    aba(%w[id created_time ad_id ad_name form_id full_name phone_number email qual_seu_interesse?], 40) do |i|
      [(900_000 + i).to_s, '2026-10-01T12:00:00-0300', D.digitos(15), 'Anúncio Outubro', D.digitos(15), D.nome,
       D::Celula.new(valor: "p:#{D.celular(:e164).valor}", alcanca: true), D.email, 'Seguro auto']
    end
  end
end
