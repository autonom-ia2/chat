# Grava a chave de leitura na ficha vigente de um agente do painel de desempenho (#2301), a partir de um arquivo fora
# do repositório (a chave é dado da conta: nunca entra no git). Grava também o hash da instrução que o agente usa hoje,
# para o painel avisar quando ela mudar (só para agente nosso; o robô de outro sistema fica sem hash).
#
#   bundle exec rails runner script/desempenho/chave.rb <conta> <agente|robo> <id do sujeito> <arquivo.md>
#
# - Atualiza a ficha de maior versão; não cria versão nova.
# - Nunca imprime o conteúdo do arquivo: só o tamanho, a versão da ficha e se o hash foi gravado.
module ChaveDeLeitura
  module_function

  def rodar(argumentos)
    conta, tipo, id, caminho = argumentos
    abort('uso: chave.rb <conta> <agente|robo> <id do sujeito> <arquivo.md>') if [conta, tipo, id, caminho].any?(&:blank?)
    abort('tipo: agente ou robo') unless Autonomia::Desempenho::Sujeito::TIPOS.include?(tipo)

    gravar(Account.find(conta), tipo, id.to_i, File.read(caminho, encoding: 'UTF-8'))
  rescue ActiveRecord::RecordNotFound, Errno::ENOENT => e
    abort("#{e.class.name}: conta ou arquivo não encontrado")
  end

  def gravar(account, tipo, id, chave)
    abort('o arquivo está vazio') if chave.strip.empty?
    ficha = Autonomia::Desempenho::Ficha.vigente(account, tipo, id)
    abort('este agente não tem ficha') if ficha.nil?

    instrucao = Autonomia::Desempenho::Ficha.hash_da_instrucao(account, tipo, id)
    ficha.update!(chave_de_leitura: chave, instrucao_hash: instrucao)
    puts "ficha versão #{ficha.versao}: chave com #{chave.size} caracteres; hash da instrução #{instrucao ? 'gravado' : 'vazio'}"
  end
end

ChaveDeLeitura.rodar(ARGV)
