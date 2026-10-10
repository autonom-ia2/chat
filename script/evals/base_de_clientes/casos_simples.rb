# Nível 1 da bateria (#1246): planilhas limpas, só muda o formato do arquivo e o idioma do cabeçalho.
module BaseDeClientesEval::Casos::Simples
  extend BaseDeClientesEval::CasosDsl
  D = BaseDeClientesEval::Dados

  caso 'c01', 'CSV simples com vírgula', nivel: 1, alvos: { phone: 'Telefone', email: 'Email', name: 'Nome' } do
    aba(%w[Nome Telefone Email], 40) { [D.nome, D.celular, D.email] }
  end

  caso 'c02', 'XLSX simples com empresa', nivel: 1, formato: 'xlsx',
                                          alvos: { phone: 'Celular', email: 'E-mail', name: 'Nome', company: 'Empresa' } do
    aba(%w[Nome Celular E-mail Empresa], 40) { [D.nome, D.celular, D.email, D.empresa] }
  end

  caso 'c03', 'Export do Excel BR: ponto e vírgula, Windows-1252', nivel: 1, opcoes: { col_sep: ';', encoding: 'Windows-1252' },
                                                                   alvos: { phone: 'Celular', email: 'E-mail', name: 'Nome' } do
    aba(%w[Nome Celular E-mail Cidade], 40) { [D.nome, D.celular, D.email, D.cidade] }
  end

  caso 'c04', 'Cabeçalhos em inglês', nivel: 1, alvos: { phone: 'Phone', email: 'Email', name: 'Name', company: 'Company' } do
    aba(%w[Name Phone Email Company], 40) { [D.nome, D.celular(:e164), D.email, D.empresa] }
  end

  caso 'c05', 'Só WhatsApp, sem e-mail', nivel: 1, alvos: { phone: 'WhatsApp', name: 'Cliente' } do
    aba(%w[Cliente WhatsApp], 40) { [D.nome, D.celular(:digitos)] }
  end

  caso 'c06', 'Só e-mail, sem telefone', nivel: 1,
                                         alvos: { email: 'Endereço de e-mail', name: 'Nome completo', company: 'Empresa' } do
    aba(['Nome completo', 'Endereço de e-mail', 'Empresa'], 40) { [D.nome, D.email, D.empresa] }
  end

  caso 'c07', 'Maiúsculas e abreviações', nivel: 1,
                                          alvos: { phone: 'CEL', email: 'E-MAIL', name: 'NOME COMPLETO', company: 'EMPRESA' } do
    aba(['NOME COMPLETO', 'CEL', 'E-MAIL', 'EMPRESA'], 40) { [D.nome.upcase, D.celular, D.email, D.empresa.upcase] }
  end

  caso 'c08', 'Separado por tabulação', nivel: 1, opcoes: { col_sep: "\t" }, alvos: { phone: 'Celular', email: 'Email', name: 'Nome' } do
    aba(%w[Nome Celular Email], 40) { [D.nome, D.celular, D.email] }
  end

  caso 'c09', 'Separado por barra vertical, com aspas', nivel: 1, opcoes: { col_sep: '|', force_quotes: true },
                                                        alvos: { phone: 'Telefone', email: 'Email', name: 'Nome' } do
    aba(%w[Nome Telefone Email], 40) { [D.nome, D.celular, D.email] }
  end
end
