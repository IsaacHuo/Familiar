# Familiar Website

Familiar 的 Vue 3 + Vite 官方网站，部署到 GitHub Pages。

## 本地开发

```bash
npm install
npm run dev
```

## 构建

```bash
npm run build
```

构建产物输出到 `dist/`。GitHub Actions 会在 `main` 分支的 `website/**` 发生变化时自动构建并部署。

## App Store Connect URL

- Marketing URL: `https://isaachuo.github.io/Familiar/`
- Privacy Policy URL: `https://isaachuo.github.io/Familiar/privacy/`
- Support URL: `https://isaachuo.github.io/Familiar/support/`

首次部署前，在 GitHub 仓库的 **Settings → Pages → Build and deployment → Source** 中选择 **GitHub Actions**。

## 技术与隐私

- Vue 3 + Vite 多页面构建，保留干净的 `/privacy/` 与 `/support/` URL。
- 无网站分析、广告脚本、Cookie 或外部字体。
- 图片与样式均由 GitHub Pages 同源托管。
- `vite.config.js` 的 `base` 当前为 `/Familiar/`；该路径区分大小写。若以后绑定根域名，需要同步改为 `/` 并更新页面 canonical、manifest、sitemap 和 404 链接。
