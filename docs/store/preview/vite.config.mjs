import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from '../../../vite.shared';

export default defineConfig({
  root: 'docs/store/preview',
  plugins: [vue(vueOptions)],
  define: { __INTLIFY_JIT_COMPILATION__: true },
  resolve: { alias: aliases },
  server: { host: '127.0.0.1', port: 5190, strictPort: true },
  build: { outDir: '../../../tmp/store-e1-preview-build', emptyOutDir: true },
});
