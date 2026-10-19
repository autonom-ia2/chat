// Pastas da caixa de e-mail no menu (#1809): o que o menu aberto (ForkSidebarFolha) e o
// balão do menu recolhido (SidebarCollapsedPopover, do Chatwoot) usam em comum.
// (`useCaixaDeEmailNova`, em caixaDeEmailNova.js, diz qual caixa é de e-mail com a chave.)
// - `comPastasNoBalao`: devolve o item do menu com as caixas de e-mail desenhando também
//   as pastas, pelo próprio `component` que o balão já respeita (sem editar o balão).
import { h } from 'vue';
import { caixaDaFolha } from './caixaDeEmailNova';
import PastasDoEmailNoMenu from './PastasDoEmailNoMenu.vue';

const comPastas = (folha, ehEmailNova) => {
  if (!ehEmailNova(caixaDaFolha(folha))) return folha;
  const original = folha.component;
  return {
    ...folha,
    component: propriedades =>
      h('span', { class: 'flex flex-col w-full min-w-0 gap-1' }, [
        typeof original === 'function'
          ? original(propriedades)
          : original || h('span', { class: 'truncate' }, folha.label),
        h(PastasDoEmailNoMenu, { folha, compacto: true }),
      ]),
  };
};

export const comPastasNoBalao = (item, ehEmailNova) => ({
  ...item,
  children: (item.children || []).map(filho =>
    filho.children
      ? {
          ...filho,
          children: filho.children.map(neto => comPastas(neto, ehEmailNova)),
        }
      : comPastas(filho, ehEmailNova)
  ),
});
