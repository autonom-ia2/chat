# O leitor de apólice em PDF (E6, #2899). Recebe o caminho de um PDF e devolve o que leu dele
# (Carteira::Leitor::Resultado). NÃO grava nada: nem apólice, nem pessoa, nem item de leitura. Quem chama decide.
#
#   resultado = Carteira::Leitor.new(account: account, ocr: true).ler(caminho, documento: '123.456.789-00')
#   resultado.lido?      # => true
#   resultado.campos     # => { 'seguradora' => '...', 'numero' => '...', 'fim_vigencia' => '2027-11-12', ... }
#   resultado.duvidas    # => ['bem', 'corretora']           (os campos que ficaram em "não achei")
#   resultado.a_confirmar # => ['segurado_telefone']         (vieram com valor, mas só valem depois de alguém confirmar)
#   resultado.recusa     # => nil | 'leitura_desligada' | 'nao_e_apolice' | 'nao_deu_para_ler'
#
# Passos:
# 1. a conta precisa ter a leitura liberada (Carteira::Leitor::Liberado); sem a chave, `leitura_desligada`, sem abrir
#    o arquivo e sem chamar o modelo. Quem pergunta ao modelo (Carteira::Leitor::Campos) confere a chave de novo;
# 2. texto por página, sem IA, e a escolha das páginas por valor exato: o CPF/CNPJ quando quem chama já sabe quem é o
#    segurado (`documento:`, com as páginas vizinhas), senão o nome (`nome:`), senão as primeiras páginas
#    (Carteira::Leitor::Paginas);
# 3. página escolhida sem texto: OCR local só dela, e só com `ocr: true` (quem passa isso roda em job);
# 4. só as páginas escolhidas vão ao modelo, que responde num esquema fechado se é uma apólice e o que está em cada
#    campo, com "não achei" por campo (Carteira::Leitor::Campos). Cada valor é conferido contra o que está escrito,
#    inteiro, numa das páginas enviadas (Carteira::Leitor::Ancora);
# 5. telefone e e-mail só da página do CPF/CNPJ do segurado (Carteira::Leitor::ContatoDoSegurado), e sempre "a
#    confirmar": quem recebe mostra para a pessoa confirmar antes de gravar na ficha.
#
# Nunca levanta por causa do arquivo ou do modelo: arquivo que não existe, grande demais, com senha ou quebrado, PDF
# sem texto, conta sem a IA configurada e falha do modelo viram `nao_deu_para_ler`, com o `motivo` para registro. Erro
# de programação sobe.
#
# A IA é a da conta (Carteira::Leitor::Campos). `cliente:` troca o cliente (a bateria com gabarito e os specs).
#
# Nada do PDF vai para log: só a conta, o motivo e a contagem de páginas.
#
# PARA QUEM FOR CHAMAR DE UM JOB (E6.2 em diante):
# - o argumento do job é só o id do item da leitura (Carteira::LeituraItem). O job busca o item, baixa o PDF dele e
#   tira `documento:` e `nome:` do que já está no banco. CPF, CNPJ, nome, telefone e caminho de arquivo NUNCA são
#   argumento de job: argumento de job fica gravado na fila e aparece em log e em painel;
# - `ocr: true` só dentro de job. Rasterizar e ler uma página leva segundos e usa processo externo; dentro de uma
#   requisição o leitor é chamado sem OCR (o padrão), e a página sem texto simplesmente não é lida;
# - o Resultado não vai para log, cache nem argumento de outro job: `campos` é dado de cliente. O que pode sair dele
#   para `totais` e para log são a recusa, o motivo e as contagens.
class Carteira::Leitor
  def initialize(account:, ocr: false, cliente: nil)
    @account = account
    @ocr = ocr
    @cliente = cliente
  end

  def ler(caminho, documento: nil, nome: nil)
    return Resultado.recusado(Resultado::DESLIGADA) unless Liberado.para?(@account)

    paginas = Paginas.new(caminho, documento: documento, nome: nome, ocr: @ocr)
    ler_as_paginas(paginas)
  rescue Paginas::Ilegivel
    nao_deu(:pdf_ilegivel, paginas)
  rescue Campos::Desligada
    Resultado.recusado(Resultado::DESLIGADA)
  rescue Campos::SemIa
    nao_deu(:sem_ia, paginas)
  rescue Campos::Falhou
    nao_deu(:modelo_falhou, paginas, enviadas: paginas.escolhidas)
  end

  private

  def ler_as_paginas(paginas)
    escolhidas = paginas.escolhidas
    return nao_deu(:sem_texto, paginas) if escolhidas.empty?

    lido = Campos.new(account: @account, cliente: @cliente).ler(escolhidas)
    enviadas = escolhidas.map(&:numero)
    return Resultado.recusado(Resultado::NAO_E_APOLICE, paginas_total: paginas.total, paginas_enviadas: enviadas) unless lido.e_apolice

    contato = ContatoDoSegurado.new(escolhidas, documento: lido.campos['segurado_documento'], numero: lido.campos['numero'])
    Resultado.lido(campos: lido.campos.merge(contato.call(lido.resposta)), paginas_total: paginas.total, paginas_enviadas: enviadas)
  end

  def nao_deu(motivo, paginas, enviadas: [])
    Rails.logger.warn("[carteira][leitor] account_id=#{@account.id} nao_deu_para_ler motivo=#{motivo} paginas=#{paginas&.total.inspect}")
    Resultado.recusado(Resultado::NAO_DEU, motivo: motivo, paginas_total: paginas&.total, paginas_enviadas: enviadas.map(&:numero))
  end
end
