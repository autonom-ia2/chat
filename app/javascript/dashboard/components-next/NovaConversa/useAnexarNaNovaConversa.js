import { useFileUpload } from 'dashboard/composables/useFileUpload';

// #1459 — anexar na gaveta: o envio do arquivo é o mesmo da tela antiga
// (useFileUpload) e cada arquivo entra na lista `anexos` (v-model da gaveta).
// #1809 — usado pelo "Anexar arquivo" (site) e pelo "+" do e-mail novo. O arquivo
// escolhido no "+" não traz `id`; ganha um aqui, para a lista poder tirar só ele.
let ultimoId = 0;
const comId = recurso => {
  if (recurso.id) return recurso;
  ultimoId += 1;
  return { ...recurso, id: `anexo-${ultimoId}` };
};

export const useAnexarNaNovaConversa = anexos => {
  const { onFileUpload } = useFileUpload({
    attachFile: ({ blob, file }) => {
      if (!file) return;
      const leitor = new FileReader();
      leitor.readAsDataURL(file.file);
      leitor.onloadend = () => {
        anexos.value = [
          ...anexos.value,
          {
            resource: blob || comId(file),
            isPrivate: false,
            thumb: leitor.result,
            blobSignedId: blob?.signed_id,
          },
        ];
      };
    },
  });
  return { onFileUpload };
};
