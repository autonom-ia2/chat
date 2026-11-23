import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import path from 'path';
const r = p => path.resolve(__dirname, '..', p);
export default defineConfig({
  root: r('.'),
  plugins: [vue()],
  server: { port: 6184, strictPort: true },
  css: { preprocessorOptions: { scss: { api: 'modern-compiler' } } },
  resolve: {
    alias: {
      vue: 'vue/dist/vue.esm-bundler.js',
      components: r('app/javascript/dashboard/components'),
      next: r('app/javascript/dashboard/components-next'),
      v3: r('app/javascript/v3'),
      dashboard: r('app/javascript/dashboard'),
      helpers: r('app/javascript/shared/helpers'),
      shared: r('app/javascript/shared'),
      assets: r('app/javascript/dashboard/assets'),
    },
  },
});
