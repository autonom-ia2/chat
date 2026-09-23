// Roteiro do vídeo de trajeto do artigo 08.07 — "Nota privada, @menção e
// resposta pronta pelo teclado". Seletores conferidos no código-fonte:
// - aba "Mensagem Privada" / "Responder": texto exato do rótulo da aba
//   (sem contador colado, ao contrário das abas de fila).
// - lista de sugestão (@menção e resposta pronta): as duas usam o mesmo
//   componente app/javascript/dashboard/components-next/preview-picker/
//   PreviewPicker.vue, cujo item de lista tem `data-index="0"` no primeiro
//   resultado — usamos isso em vez do nome da pessoa/atalho, que muda.
//
// Trajeto: tela de Conversas → aba Todos → abre um card qualquer → aba
// Mensagem Privada → digita @Bia (mostra a lista de menção) → escolhe a
// pessoa → volta para Responder → digita /boas-vindas (mostra a resposta
// pronta) → escolhe a resposta. Não envia nada (só demonstra, sem criar
// dado na conversa).

export const id = '08.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

// Cria (se não existir) a resposta pronta de demonstração e garante que a
// caixa de resposta comece sem assinatura pré-preenchida — senão o texto
// da assinatura ocupa o editor antes da digitação de /boas-vindas.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.canned_responses.find_or_create_by!(short_code: "boas-vindas") do |c|
  c.content = "Olá! Posso ajudar com o que você precisar."
end
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
config = (usuaria.ui_settings || {}).merge(
  "channel_api_signature_enabled" => false,
  "is_contact_sidebar_open" => false,
  "conversation_display_type" => "condensed"
)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Nota privada, menção e resposta pronta',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique na aba Todos',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(3) > a.text-button' },
    zoom: 1.5,
  },
  {
    legenda: 'Abra uma conversa qualquer',
    acao: 'mover e clicar',
    alvo: { seletor: '.conversation' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique na aba Mensagem Privada',
    acao: 'mover e clicar',
    alvo: { texto: 'Mensagem Privada' },
    zoom: 1.6,
  },
  {
    legenda: 'A mensagem será visível apenas para agentes',
    acao: 'parar',
    zoom: 1.4,
    duracaoMs: 900,
  },
  {
    legenda: 'Digite @ para mencionar alguém',
    acao: 'digitar',
    alvo: { seletor: '.ProseMirror' },
    texto: ['@Bia'],
    zoom: 1.6,
  },
  {
    legenda: 'Escolha a pessoa na lista',
    acao: 'mover e clicar',
    alvo: { seletor: '[data-index="0"]' },
    zoom: 1.5,
  },
  {
    legenda: 'Volte para a aba Responder',
    acao: 'mover e clicar',
    alvo: { texto: 'Responder' },
    zoom: 1.6,
  },
  {
    legenda: 'Digite / e o atalho',
    acao: 'digitar',
    alvo: { seletor: '.ProseMirror' },
    texto: ['/boas-vindas'],
    zoom: 1.6,
  },
  {
    legenda: 'Escolha a resposta pronta',
    acao: 'mover e clicar',
    alvo: { seletor: '[data-index="0"]' },
    zoom: 1.5,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1800,
  },
];
