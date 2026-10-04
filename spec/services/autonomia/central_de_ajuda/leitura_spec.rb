require 'rails_helper'

RSpec.describe Autonomia::CentralDeAjuda::Leitura do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:portal) { create(:portal, slug: 'plataforma', account: conta) }
  let(:video) do
    { 'arquivo' => '/central-de-ajuda/videos/02.04.mp4', 'legenda' => '/central-de-ajuda/videos/02.04.vtt',
      'poster' => '/central-de-ajuda/videos/02.04.jpg', 'duracao' => 12 }
  end
  let(:leitura) { described_class.new(account: conta, account_user: conta.account_users.find_by(user: admin)) }

  def artigo(id, titulo, central = {})
    create(:article, account: conta, portal: portal, slug: "plataforma-#{id.tr('.', '-')}", title: titulo,
                     description: "Sobre #{titulo}", content: 'Passo 1. Passo 2.', status: :published,
                     meta: { 'central' => { 'id' => id, 'me_leve_ate_la' => { 'rota' => 'inbox_view' } }.merge(central) })
  end

  describe '#resumo' do
    # O Guia lê `capitulos[].artigos[]` e usa `rota`: as chaves de antes ficam, as novas só se somam.
    it 'mantém as chaves de antes e soma video, poster e duracao' do
      resumo = leitura.resumo(artigo('02.04', 'Conectar o WhatsApp', 'video' => video))

      expect(resumo).to eq(id: '02.04', ref: '02-04', titulo: 'Conectar o WhatsApp', descricao: 'Sobre Conectar o WhatsApp',
                           capitulo: nil, rota: 'inbox_view', video: true,
                           poster: '/central-de-ajuda/videos/02.04.jpg', duracao: 12)
    end

    it 'diz que não tem vídeo, pôster nem duração quando o artigo não publicou vídeo' do
      resumo = leitura.resumo(artigo('02.05', 'Seus avisos'))

      expect(resumo.values_at(:video, :poster, :duracao)).to eq([false, nil, nil])
    end
  end

  # A ferramenta ler_da_central monta o texto do modelo com campos escolhidos do resumo: as chaves novas
  # não chegam ao modelo, e o que ele recebe fica igual ao de antes.
  describe 'o que a ferramenta ler_da_central entrega ao modelo' do
    let(:agente) do
      Autonomia::Agents::Agent.create!(account: conta, name: 'Guia', agent_type: 'custom', status: :active, enabled: false,
                                       instruction: 'Guia.', config: { 'with_knowledge' => false })
    end
    let(:operador) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }

    def ler_central(params)
      Autonomia::Agents::Tools::Native::GuiaCentral.new(agent: agente, params: params, operador: operador).call
    end

    before { artigo('02.04', 'Conectar o WhatsApp', 'video' => video) }

    it 'pela referência, devolve só título, ref e corpo' do
      expect(ler_central({ 'ref' => '02-04' })).to eq("Artigo 02-04 — Conectar o WhatsApp\n\nPasso 1. Passo 2.")
    end

    it 'pela busca, devolve a lista com ref, título e descrição e o corpo do primeiro' do
      expect(ler_central({ 'termo' => 'conectar whatsapp' })).to eq(
        "Resultados na Central de Ajuda:\n- 02-04 Conectar o WhatsApp — Sobre Conectar o WhatsApp\n\n" \
        "Artigo 02-04 — Conectar o WhatsApp\n\nPasso 1. Passo 2."
      )
    end
  end
end
