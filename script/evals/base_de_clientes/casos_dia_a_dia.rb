# Nível 2 da bateria (#1246): o que aparece todo dia — título em cima, colunas parecidas, export de
# outro sistema (Kommo, RD, Pipedrive, HubSpot), várias abas.
module BaseDeClientesEval::Casos::DiaADia
  extend BaseDeClientesEval::CasosDsl
  D = BaseDeClientesEval::Dados

  caso 'c10', 'Título e data antes do cabeçalho', nivel: 2, formato: 'xlsx',
                                                  alvos: { phone: 'Celular', email: 'E-mail', name: 'Nome' } do
    aba(%w[Nome Celular E-mail Status], 40,
        antes: [['Relatório de clientes — Outubro/2026'], ['Gerado em 10/10/2026 por Sistema X'], []]) do
      [D.nome, D.celular, D.email, D.status]
    end
  end

  caso 'c11', 'Telefone fixo e celular lado a lado', nivel: 2,
                                                     alvos: { phone: 'Celular', email: 'Email', name: 'Nome' } do
    aba(['Nome', 'Telefone fixo', 'Celular', 'Email'], 40) { [D.nome, D.fixo, D.celular, D.email] }
  end

  caso 'c12', 'Dois e-mails, um marcado como principal', nivel: 2,
                                                         alvos: { phone: 'Celular', email: 'E-mail principal', name: 'Nome' } do
    aba(['Nome', 'E-mail secundário', 'E-mail principal', 'Celular'], 40) { [D.nome, D.email, D.email, D.celular] }
  end

  caso 'c13', 'Nome e sobrenome separados', nivel: 2, alvos: { phone: 'Celular', email: 'Email', name: 'Nome' } do
    aba(%w[Nome Sobrenome Celular Email], 40) { [D.primeiro_nome, D.sobrenome, D.celular, D.email] }
  end

  caso 'c14', 'Razão social, CNPJ e contato', nivel: 2,
                                              alvos: { phone: 'Telefone', email: 'E-mail', name: 'Contato', company: 'Razão Social' } do
    aba(['Razão Social', 'CNPJ', 'Contato', 'Telefone', 'E-mail'], 40) { [D.empresa, D.cnpj, D.nome, D.celular, D.email] }
  end

  caso 'c15', 'Celular em todos os formatos, inclusive sem o 9', nivel: 2,
                                                                 alvos: { phone: 'Telefone', email: 'Email', name: 'Nome' } do
    aba(%w[Nome Telefone Email], 60) { [D.nome, D.celular_misto, D.chance(0.3) ? D.email : vazio] }
  end

  caso 'c16', 'Datas, valores e observações no meio', nivel: 2,
                                                      alvos: { phone: 'Celular', email: 'Email', name: 'Nome' } do
    aba(['Nome', 'Data de nascimento', 'Valor do contrato', 'Celular', 'Email', 'Observações'], 40) do
      [D.nome, D.data_br(18..70), D.valor_br, D.celular, D.email, D.chance(0.3) ? 'Cliente desde 2019, prefere WhatsApp' : '']
    end
  end

  caso 'c17', 'Cabeçalhos com erro de digitação', nivel: 2,
                                                  alvos: { phone: 'Telfone', email: 'Emial', name: 'Nme', company: 'Empressa' } do
    aba(%w[Nme Telfone Emial Empressa], 40) { [D.nome, D.celular, D.email, D.empresa] }
  end

  caso 'c18', 'Export do Kommo', nivel: 2,
                                 alvos: { phone: 'Telefone celular', email: ['Email comercial', 'Email pessoal'], name: 'Nome',
                                          company: 'Empresa do contato' },
                                 pode_perguntar: %i[email] do
    aba(['ID', 'Nome', 'Empresa do contato', 'Telefone comercial', 'Telefone celular', 'Email comercial', 'Email pessoal', 'Etapa',
         'Usuário responsável', 'Tags', 'Criado em'], 40) do |i|
      [(10_000 + i).to_s, D.nome, D.empresa, D.fixo, D.celular(:e164), D.chance(0.6) ? D.email : vazio, D.email, D.status,
       D.nome, 'lead-site', D.data_br(0..2)]
    end
  end

  caso 'c19', 'Export do RD Station', nivel: 2,
                                      alvos: { phone: 'Celular', email: 'Email', name: 'Nome', company: 'Empresa' } do
    aba(['Nome', 'Email', 'Telefone', 'Celular', 'Empresa', 'Cargo', 'Estágio no funil', 'Origem da primeira conversão',
         'Data da última conversão'], 40) do
      [D.nome, D.email, D.chance(0.5) ? D.fixo : vazio, D.celular, D.empresa, 'Gerente', 'Lead', 'Orgânico', D.data_br(0..1)]
    end
  end

  caso 'c20', 'Export do Pipedrive (pessoa, organização, negócio)', nivel: 2,
                                                                    alvos: { phone: 'Pessoa - Telefone', email: 'Pessoa - E-mail',
                                                                             name: 'Pessoa - Nome', company: 'Organização - Nome' } do
    aba(['Negócio - Título', 'Negócio - Valor', 'Negócio - Etapa', 'Negócio - Proprietário', 'Pessoa - Nome', 'Pessoa - Telefone',
         'Pessoa - E-mail', 'Organização - Nome'], 40) do
      [D.empresa, D.valor_br, 'Proposta enviada', D.nome, D.nome, D.celular, D.email, D.empresa]
    end
  end

  caso 'c21', 'Export do HubSpot em inglês', nivel: 2,
                                             alvos: { phone: 'Mobile Phone Number', email: 'Email', name: 'First Name',
                                                      company: 'Company Name' } do
    aba(['First Name', 'Last Name', 'Email', 'Phone Number', 'Mobile Phone Number', 'Company Name', 'Lifecycle Stage',
         'Contact owner'], 40) do
      [D.primeiro_nome, D.sobrenome, D.email, D.fixo, D.celular(:e164_espacos), D.empresa, 'customer', D.nome]
    end
  end

  caso 'c22', 'Consentimento ao lado do contato', nivel: 2,
                                                  alvos: { phone: 'Celular', email: 'E-mail', name: 'Nome' } do
    aba(['Nome', 'Celular', 'Aceita WhatsApp?', 'E-mail', 'Aceita e-mail?'], 40) { [D.nome, D.celular, D.sim_nao, D.email, D.sim_nao] }
  end

  caso 'c23', 'Várias abas: resumo, clientes e inativos', nivel: 2, formato: 'xlsx', aba_alvo: 1,
                                                          alvos: { phone: 'Celular', email: 'E-mail', name: 'Nome' } do
    [
      aba(%w[Indicador Valor], 4, nome: 'Resumo') { |i| [%w[Clientes Ativos Inativos Ticket][i], (i * 37).to_s] },
      aba(%w[Nome Celular E-mail Cidade], 50, nome: 'Clientes') { [D.nome, D.celular, D.email, D.cidade] },
      aba(%w[Nome Celular E-mail Motivo], 8, nome: 'Inativos') { [D.nome, D.celular, D.email, 'Cancelou'] }
    ]
  end

  caso 'c24', 'Linha de total no rodapé', nivel: 2, alvos: { phone: 'Celular', email: 'Email', name: 'Cliente' } do
    aba(%w[Cliente Celular Email], 48, antes: [['Carteira de clientes']], depois: [[], ['Total de clientes: 48', '', '']]) do
      [D.nome, D.celular, D.email]
    end
  end

  caso 'c25', 'Espanhol', nivel: 2,
                          alvos: { phone: 'Teléfono móvil', email: 'Correo electrónico', name: 'Nombre', company: 'Empresa' } do
    aba(['Nombre', 'Teléfono móvil', 'Correo electrónico', 'Empresa'], 40) { [D.nome, D.celular(:e164), D.email, D.empresa] }
  end

  caso 'c26', 'Vendedor e cliente na mesma linha', nivel: 2,
                                                   alvos: { phone: 'Celular do cliente', email: 'E-mail do cliente', name: 'Cliente',
                                                            company: 'Empresa' } do
    aba(['Vendedor', 'Cliente', 'Celular do cliente', 'E-mail do cliente', 'Empresa'], 40) do
      [D.nome, D.nome, D.celular, D.email, D.empresa]
    end
  end

  caso 'c27', 'Pessoas repetidas na planilha', nivel: 2, alvos: { phone: 'Celular', email: 'Email', name: 'Nome' },
                                               nota: 'Uma pessoa com duas compras aparece duas vezes.' do
    pessoas = Array.new(30) { [D.nome, D.celular, D.email] }
    aba(%w[Nome Celular Email Produto], 40) { |i| [*pessoas[i < 30 ? i : i - 30], ['Plano A', 'Plano B'][i % 2]] }
  end

  caso 'c28', 'Coluna "Contato" que guarda o telefone', nivel: 2,
                                                        alvos: { phone: 'Contato', email: 'Email', name: 'Nome' } do
    aba(%w[Nome Contato Email], 40) { [D.nome, D.celular, D.email] }
  end

  caso 'c29', 'Colunas vazias e sem nome no meio', nivel: 2, alvos: { phone: 'Celular', email: 'Email', name: 'Nome' } do
    aba(['Nome', '', 'Celular', '', '', 'Email', 'Obs'], 40) { [D.nome, '', D.celular, '', '', D.email, ''] }
  end
end
