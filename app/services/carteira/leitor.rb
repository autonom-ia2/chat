# O leitor de apólice em PDF (E6, #2899). Recebe o caminho de um PDF e devolve o que leu dele
# (Carteira::Leitor::Resultado). NÃO grava nada: nem apólice, nem pessoa, nem item de leitura. Quem chama decide.
#
#   resultado = Carteira::Leitor.new(account: account, ocr: true).ler(caminho, documento: '123.456.789-00')
#   resultado.lido?      # => true
#   resultado.campos     # => { 'seguradora' => '...', 'numero' => '...', 'fim_vigencia' => '2027-11-12', ... }
#   resultado.duvidas    # => ['bem', 'segurado_telefone']   (os campos que ficaram em "não achei")
#   resultado.recusa     # => nil | 'leitura_desligada' | 'nao_e_apolice' | 'nao_deu_para_ler'
#
# Passos:
# 1. a conta precisa ter a leitura liberada (Carteira::Leitor::Liberado); sem a chave, `leitura_desligada`, sem abrir
#    o arquivo e sem chamar o modelo;
# 2. texto por página, sem IA, e a escolha das páginas por valor exato: o CPF/CNPJ quando quem chama já sabe quem é o
#    segurado (`documento:`), senão o nome (`nome:`), senão as primeiras páginas (Carteira::Leitor::Paginas);
# 3. página escolhida sem texto: OCR local só dela, e só com `ocr: true` (quem passa isso roda em job);
# 4. só as páginas escolhidas vão ao modelo, que responde num esquema fechado se é uma apólice e o que está em cada
#    campo, com "não achei" por campo (Carteira::Leitor::Campos). Cada valor é conferido contra o texto das páginas;
# 5. telefone e e-mail só da página do CPF/CNPJ do segurado (Carteira::Leitor::ContatoDoSegurado).
#
# Nunca levanta por causa do arquivo ou do modelo: PDF ilegível, sem texto, conta sem a IA configurada e falha do
# modelo viram `nao_deu_para_ler`, com o `motivo` para registro. Erro de programação sobe.
#
# A IA é a da conta, pelo caminho da casa: a credencial do Kanban CRM (Autonomia::Prospecting::AiCredential, sem a
# chave da instalação) e o Crm::Ai::ResponsesClient, que registra o uso na Gestão IA. `cliente:` troca o cliente (a
# bateria com gabarito e os specs).
#
# Nada do PDF vai para log: só a conta, o motivo e a contagem de páginas.
class Carteira::Leitor
  # Uma nova tentativa do HTTP: roda em job, sem ninguém esperando na tela.
  NOVAS_TENTATIVAS = 1

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
  rescue Campos::Falhou
    nao_deu(:modelo_falhou, paginas, enviadas: paginas.escolhidas)
  end

  private

  def ler_as_paginas(paginas)
    escolhidas = paginas.escolhidas
    return nao_deu(:sem_texto, paginas) if escolhidas.empty?

    cliente = @cliente || cliente_da_conta
    return nao_deu(:sem_ia, paginas) if cliente.nil?

    lido = Campos.new(cliente).ler(escolhidas)
    enviadas = escolhidas.map(&:numero)
    return Resultado.recusado(Resultado::NAO_E_APOLICE, paginas_total: paginas.total, paginas_enviadas: enviadas) unless lido.e_apolice

    contato = ContatoDoSegurado.new(escolhidas, documento: lido.campos['segurado_documento']).call(lido.resposta)
    Resultado.lido(campos: lido.campos.merge(contato), paginas_total: paginas.total, paginas_enviadas: enviadas)
  end

  def cliente_da_conta
    credencial = Autonomia::Prospecting::AiCredential.new(account: @account).resolve
    return if credencial.blank?

    Crm::Ai::ResponsesClient.new(credential: credencial, feature: Campos::FEATURE, account: @account, max_retries: NOVAS_TENTATIVAS)
  end

  def nao_deu(motivo, paginas, enviadas: [])
    Rails.logger.warn("[carteira][leitor] account_id=#{@account.id} nao_deu_para_ler motivo=#{motivo} paginas=#{paginas&.total.inspect}")
    Resultado.recusado(Resultado::NAO_DEU, motivo: motivo, paginas_total: paginas&.total, paginas_enviadas: enviadas.map(&:numero))
  end
end
