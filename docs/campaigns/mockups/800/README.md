# Proposta de campanhas de e-mail

Protótipo navegável para a revisão de UI/UX solicitada na issue [#800](https://github.com/autonom-ia2/chat/issues/800). Não é a implementação do produto. Não chama APIs da plataforma, banco, IA ou serviços de envio.

## Abrir e avaliar

Abra `index.html` em um navegador. Os scripts e estilos são locais. Para servir por HTTP:

```sh
python3 -m http.server 34780 --bind 127.0.0.1 --directory docs/campaigns/mockups/800
```

Abra `http://127.0.0.1:34780/`. Use as quatro abas da faixa superior para avaliar lista, editor, modelos e revisão. Os números, remetentes, destinatários e campanhas são ilustrativos.

## Caminhos para experimentar

1. Na lista, clique em **Disparar** na campanha pronta. Confira a revisão e a confirmação final; a confirmação é simulada.
2. Clique em **Disparar** no rascunho incompleto. Veja o motivo e o botão **Completar o e-mail**. Preencher somente o assunto não conclui o conteúdo.
3. Abra **Modelos**, filtre por objetivo ou busque um nome. Abra uma prévia e use um modelo no editor do protótipo.
4. Alterne entre **Biblioteca** e **Meus modelos**. Os dois modelos da equipe são fictícios; os 14 layouts da biblioteca são arquivos originais do projeto.
5. No editor, altere assunto e texto de prévia, consulte o menu de personalização, veja as opções de IA e alterne desktop/celular.
6. Na revisão, veja os endereços fora do envio e alterne entre enviar agora e agendar.

## O que é simulado

Navegação, pesquisa, filtros, prévias, seleção de modelo e estado do assunto funcionam localmente. Salvamento, envio de teste, confirmação do disparo/agendamento, IA, edição de blocos, importação e manipulação de dados são demonstrações visuais. Nenhum e-mail é enviado e nenhum registro é alterado. Recarregar restaura os dados iniciais. As imagens dos modelos originais dependem dos endereços externos já presentes nesses arquivos.

## Capturas

As capturas são JPEGs reais do navegador, sem montagem ou geração de imagem. Foram obtidas do protótipo em 1440 × 900 usando a capacidade CDP do navegador, que captura a página inteira na dimensão de teste sem o corte da janela de exibição. A dimensão temporária foi restaurada após a revisão.

- `previews/01-campanhas.jpg`
- `previews/02-editor.jpg`
- `previews/03-modelos.jpg`
- `previews/04-revisao.jpg`
- `previews/05-pendencia.jpg`

Há também validação de layout em 390 × 844. O relatório de interações e geometria fica em `browser-report.json`. Não houve transbordamento horizontal ou corte de texto nos comandos principais avaliados. Isso valida o protótipo; não substitui os testes da futura implementação.

## Fontes e construção

- Identidade e estrutura da plataforma: ativo `public/brand-assets/hub2you-icon.png`, cores da família azul da marca e tipografia do sistema.
- Galeria: links relativos aos 14 HTMLs de `db/seeds/email_templates/`, sem alteração ou duplicação no Git; o pacote portátil materializa os arquivos originais. Licença MIT de Mailteorite preservada em `assets/templates/LICENSE`.
- Nomes e categorias da galeria: rótulos em português para facilitar a escolha. O conteúdo dos arquivos originais não foi traduzido ou reescrito nesta etapa.
- Ícones: Lucide Contributors, licença ISC, extraídos da dependência existente `@iconify-json/lucide`. Origem e licença: https://github.com/lucide-icons/lucide.
- E-mail “Novidades Chat2You”: ilustração nova de design com dados fictícios, em `assets/email-demo.html`.
- Estilos do protótipo: utilitários Tailwind; `mockup.css` é gerado. Os estilos internos dos 14 e-mails originais pertencem aos arquivos de conteúdo licenciados.

Para regenerar ativos, execute `node docs/campaigns/mockups/800/prepare-assets.cjs <caminho-de-@iconify-json/lucide/icons.json>`. Para gerar o CSS, execute o Tailwind existente com `-c docs/campaigns/mockups/800/tailwind.config.cjs -i docs/campaigns/mockups/800/input.css -o docs/campaigns/mockups/800/mockup.css --minify`.

## Aprovação e implementação

A revisão completa e os limites das evidências estão em `docs/audit/800-email-campaigns-uiux.md`. Esta etapa entrega o desenho para aprovação. Depois, implementar nos componentes existentes, conferir as regras reais e as permissões, investigar o catálogo no ambiente e obter evidência do produto construído antes de merge/deploy.
