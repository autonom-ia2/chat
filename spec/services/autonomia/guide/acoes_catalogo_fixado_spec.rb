require 'rails_helper'

# O catálogo de ações do Guia é DERIVADO do roteador (todas as 468 rotas de
# escrita da conta), então ele cresce sozinho
# quando alguém cria uma rota. É isso que o torna completo — e é isso que o
# torna perigoso: uma rota nova que fale com cliente, rotacione credencial ou
# mande dado para fora entraria sem ninguém decidir nada.
#
# Este teste é a trava. Ele compara o catálogo de agora com a lista conferida em
# `spec/fixtures/autonomia/guide/acoes_catalogo.txt`. Mexeu em rota, ele falha, e
# alguém olha o que entrou antes de o Guia poder executar.
#
# Para atualizar, depois de conferir item a item o que entrou:
#   bundle exec rails runner 'File.write("spec/fixtures/autonomia/guide/acoes_catalogo.txt",
#     Autonomia::Guide::Acoes.new(account: Account.new(id: 1), user: nil).catalogo.join("\n") + "\n")'
RSpec.describe Autonomia::Guide::Acoes do
  let(:fixado) do
    Rails.root.join('spec/fixtures/autonomia/guide/acoes_catalogo.txt').read.split("\n").reject(&:blank?)
  end
  let(:agora) { described_class.new(account: Account.new(id: 1), user: nil).catalogo }

  it 'não ganha ação nova sem alguém decidir', :aggregate_failures do
    entraram = agora - fixado
    sairam = fixado - agora

    expect(entraram).to be_empty, 'Rotas de escrita novas entraram sozinhas no catálogo do Guia. Não é ' \
                                  'erro: é para você saber o que o Guia passou a poder executar. Confira ' \
                                  "e atualize a lista fixada:\n#{entraram.join("\n")}"
    expect(sairam).to be_empty, "Ações sumiram do catálogo:\n#{sairam.join("\n")}"
  end
end
