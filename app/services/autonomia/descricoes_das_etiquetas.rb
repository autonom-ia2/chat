# #2435: a descrição que a conta escreveu em cada etiqueta, para a IA ler a etiqueta pelo critério escrito
# ("vip": "cliente com mais de 3 apólices"), e não só pelo nome. Só entram as etiquetas que têm descrição: a etiqueta
# sem descrição continua indo só pelo nome, como antes.
#
# A descrição que é o próprio nome escrito de outro jeito fica de fora. É o que o G29 (#2702) grava quando a automação
# cria a etiqueta a partir de um dado (nome do anúncio, valor de formulário): texto que pode vir de terceiro e que não
# diz critério nenhum, só repete o nome.
module Autonomia::DescricoesDasEtiquetas
  module_function

  # { 'vip' => 'cliente com mais de 3 apólices' } das etiquetas da conta com esses nomes, na ordem dos nomes.
  def de(account, titulos)
    return {} if account.nil? || titulos.blank?

    escritas = account.labels.where(title: titulos).where.not(description: [nil, '']).pluck(:title, :description).to_h
    titulos.filter_map do |titulo|
      descricao = escritas[titulo].to_s.strip
      [titulo, descricao] if criterio?(titulo, descricao)
    end.to_h
  end

  def criterio?(titulo, descricao)
    descricao.present? && Autonomia::Automacao::EtiquetaDoTexto.de(descricao) != titulo
  end
end
