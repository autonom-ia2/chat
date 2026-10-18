import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ModelosDeEmailAPI from 'dashboard/api/modelosDeEmail';
import {
  montarModelo,
  preencherModelo,
  textoDoModelo,
} from 'dashboard/components-next/conversa-canal/email/modeloDeEmail';

// #1809 — o "Modelo de e-mail" do "+" na gaveta "Escrever", igual ao da resposta
// (#1786). O estado mora no `form` da gaveta (form.modeloDoEmail e
// form.valoresDoModelo), para trocar de contato ou de caixa zerar junto.
// - Conversa nova: o servidor preenche pelo CONTATO escolhido (contact_id +
//   inbox_id); sem conversa a IA não tem o que ler, e o resto vem vazio para a
//   pessoa preencher.
// - Continuando uma conversa (#1505): pela conversa, como na resposta. O histórico
//   (com ou sem modelo) fica no useNovaConversa.
// No envio vai o mesmo `email_modelo` da resposta; o servidor monta e limpa o
// HTML (ConversaCanal::ModeloNaResposta).
export function useModeloDoEmailNaGaveta({ form, contato, canal, destino }) {
  const { t } = useI18n();

  const abrir = id =>
    destino.value
      ? ModelosDeEmailAPI.abrir(id, destino.value.displayId)
      : ModelosDeEmailAPI.abrirParaContato(id, {
          contactId: contato.value.id,
          inboxId: canal.value.id,
        });

  // A resposta chega depois: só o último pedido conta. Trocar de contato ou de caixa,
  // tirar o modelo ou limpar o rascunho no meio invalida o que estava a caminho.
  let ultimoPedido = 0;
  const cancelar = () => {
    ultimoPedido += 1;
  };
  const escolher = async id => {
    ultimoPedido += 1;
    const pedido = ultimoPedido;
    const alvo = `${contato.value?.id}|${canal.value?.id}`;
    try {
      const { data } = await abrir(id);
      const html = await montarModelo({ mjml: data.mjml, html: data.html });
      if (!html) throw new Error('modelo vazio');
      const outro = alvo !== `${contato.value?.id}|${canal.value?.id}`;
      if (pedido !== ultimoPedido || outro) return;
      form.modeloDoEmail = {
        id: data.id,
        nome: data.nome,
        html,
        campos: data.campos,
      };
      form.valoresDoModelo = Object.fromEntries(
        data.campos.map(campo => [campo.chave, campo.valor])
      );
    } catch {
      if (pedido === ultimoPedido)
        useAlert(t('CONVERSA_CANAL.EMAIL.MODELO_FALHOU'));
    }
  };

  const campo = (chave, valor) => {
    form.valoresDoModelo = { ...form.valoresDoModelo, [chave]: valor };
  };

  const tirar = () => {
    cancelar();
    form.modeloDoEmail = null;
    form.valoresDoModelo = {};
  };

  // Na prévia "Como X recebe", campo vazio aparece destacado com o nome.
  const htmlDaPrevia = computed(() =>
    form.modeloDoEmail
      ? preencherModelo(form.modeloDoEmail.html, form.valoresDoModelo, {
          marcar: true,
        })
      : ''
  );

  // O que o envio leva: sem texto, sai só o modelo (o conteúdo vira o texto do
  // modelo, que o CRM e a IA leem), como na resposta.
  const noEnvio = mensagem => {
    if (!form.modeloDoEmail) return { mensagem, atributos: null };
    const html = preencherModelo(form.modeloDoEmail.html, form.valoresDoModelo);
    const soModelo = !String(mensagem || '').trim();
    return {
      mensagem: soModelo ? textoDoModelo(html) : mensagem,
      atributos: {
        email_modelo: {
          template_id: form.modeloDoEmail.id,
          html,
          so_modelo: soModelo,
        },
      },
    };
  };

  return { escolher, campo, tirar, cancelar, htmlDaPrevia, noEnvio };
}

// O que a caixa do e-mail da gaveta recebe por provide/inject: para quem vai e o
// modelo ({ para, modelo, valores, escolher, campo, tirar }).
export const EMAIL_DA_GAVETA = Symbol('emailDaGaveta');
