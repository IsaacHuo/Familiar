<script setup>
const base = import.meta.env.BASE_URL;
</script>

<template>
  <div>
    <header class="page-hero narrow">
      <p class="eyebrow"><span class="eyebrow-dot" aria-hidden="true"></span>帮助与支持</p>
      <h1>有什么可以帮你？</h1>
      <p>从连接模型到管理本地数据，这里整理了使用 Familiar 时最常见的问题与解决方法。</p>
    </header>

    <section class="support-grid container" aria-label="快速帮助">
      <article class="support-card">
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M7 10V7a5 5 0 0 1 10 0v3M5 10h14v11H5V10Z" stroke-linejoin="round" /><circle cx="12" cy="15" r="1" /></svg>
        </div>
        <h2>连接模型</h2>
        <p>准备所选服务的 API Key，在首次设置中验证后即可开始。</p>
      </article>
      <article class="support-card">
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M12 3 19 6v5.2c0 4.2-2.86 8-7 9.4-4.14-1.4-7-5.2-7-9.4V6l7-3Z" stroke-linejoin="round" /><path d="M9.5 11.8 11 13.3l3.8-4" stroke-linecap="round" stroke-linejoin="round" /></svg>
        </div>
        <h2>权限与隐私</h2>
        <p>系统权限只在对应功能需要时请求，并可随时从 iOS 设置撤销。</p>
      </article>
      <article class="support-card">
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M4 6h16M9 6V4h6v2M7 9v10h10V9M10 11v5M14 11v5" stroke-linecap="round" stroke-linejoin="round" /></svg>
        </div>
        <h2>管理数据</h2>
        <p>会话与附件保存在本机；API Key 可以在 Familiar 设置中清除。</p>
      </article>
    </section>

    <section class="faq-wrap container" aria-labelledby="faq-title">
      <div class="section-heading">
        <p class="section-kicker">常见问题</p>
        <h2 id="faq-title">先从这里开始。</h2>
        <p>多数连接和权限问题都可以在几步内解决。</p>
      </div>

      <div class="faq-list">
        <details>
          <summary>如何开始使用 Familiar？</summary>
          <div class="detail-content">
            <ol>
              <li>准备你要使用的模型服务账号和 API Key。</li>
              <li>打开 Familiar，在首次设置中选择服务和模型。</li>
              <li>输入 API Key 并完成连接验证。</li>
              <li>验证成功后，即可创建会话并发送第一条消息。</li>
            </ol>
          </div>
        </details>

        <details>
          <summary>我的 API Key 保存在什么地方？</summary>
          <div class="detail-content">
            <p>API Key 按服务商分别保存在当前设备的 iOS Keychain 中。Familiar 没有用于接收或同步这些 Key 的自有服务器。你可以在 App 设置中清除已保存的 Key。</p>
          </div>
        </details>

        <details>
          <summary>为什么连接验证失败或没有回答？</summary>
          <div class="detail-content">
            <ul>
              <li>确认 API Key 完整、有效，且属于当前选择的模型服务。</li>
              <li>检查服务账户是否有可用额度、账单状态是否正常。</li>
              <li>确认所选模型在你的账户或地区可用。</li>
              <li>检查网络连接，或稍后重试以排除服务商临时故障。</li>
              <li>使用自定义 endpoint 时，确认基础 URL、模型名称和兼容接口路径正确。</li>
            </ul>
          </div>
        </details>

        <details>
          <summary>Familiar 会收取模型使用费吗？</summary>
          <div class="detail-content">
            <p>Familiar 使用你自己的模型服务账户。API 调用产生的费用、额度和限速由对应服务商决定，不由 Familiar 代收或管理。发送请求前，请查看服务商的价格与用量设置。</p>
          </div>
        </details>

        <details>
          <summary>如何删除聊天记录和附件？</summary>
          <div class="detail-content">
            <p>删除 Familiar 中的会话会同时清理该会话关联的本地内容。若要移除模型服务凭证，请另外前往设置清除 API Key。删除本地数据不会撤回此前已经发送给第三方模型服务的请求。</p>
          </div>
        </details>

        <details>
          <summary>为什么需要相机、麦克风或语音识别权限？</summary>
          <div class="detail-content">
            <p>相机用于拍摄准备添加到消息草稿的照片；麦克风与 Apple Speech 用于将语音转换为可编辑文字。只有你主动使用这些入口时才会请求权限。你可以拒绝，文字聊天仍可继续使用。</p>
          </div>
        </details>

        <details>
          <summary>为什么需要日历或提醒事项权限？</summary>
          <div class="detail-content">
            <p>只有在你主动请求相关工具时，Familiar 才会请求对应权限。读取范围用于完成当前问题；创建事件或提醒事项前会展示预览并要求逐次确认。你可以在 iOS“设置”中随时撤销权限。</p>
          </div>
        </details>

        <details>
          <summary>语音输入是否完全在本机完成？</summary>
          <div class="detail-content">
            <p>Familiar 使用 Apple Speech，并在系统与当前语言支持时要求端侧识别，但无法保证所有设备和语言都完全在本机处理。Familiar 本身不保存语音录音。</p>
          </div>
        </details>

        <details>
          <summary>支持哪些系统版本？</summary>
          <div class="detail-content">
            <p>Familiar 最低支持 iOS 18，并针对 iPhone 设计。建议安装最新可用的 iOS 更新，以获得更好的安全性和系统组件兼容性。</p>
          </div>
        </details>

        <details>
          <summary>如何提交 Bug 或功能建议？</summary>
          <div class="detail-content">
            <p>请先搜索现有 GitHub Issues，确认是否已经有人报告；如没有，可创建新 Issue，并附上 Familiar 版本、iOS 版本、复现步骤和已隐藏敏感内容的截图。</p>
          </div>
        </details>
      </div>
    </section>

    <section class="support-cta container" aria-labelledby="contact-title">
      <div>
        <h2 id="contact-title">仍然需要帮助？</h2>
        <p>在 GitHub 提交问题，我们会根据你提供的复现信息进行排查。</p>
        <p class="safety-note">公开 Issue 中请勿提交 API Key、聊天内容、日历、提醒事项、文档或其他个人信息。</p>
      </div>
      <a class="button button-primary" href="https://github.com/IsaacHuo/familiar/issues/new" target="_blank" rel="noreferrer">
        提交问题
        <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M7 4h9v9M16 4 7 13" stroke-linecap="round" stroke-linejoin="round" /><path d="M13 10v5H4V6h5" stroke-linecap="round" stroke-linejoin="round" /></svg>
      </a>
    </section>

    <section class="cta container">
      <div class="cta-panel">
        <img :src="`${base}assets/app-icon.png`" alt="Familiar App 图标" width="74" height="74">
        <h2>想了解数据如何处理？</h2>
        <p>隐私政策详细说明了本机存储、第三方模型服务、系统权限和数据删除方式。</p>
        <a class="button button-primary" :href="`${base}privacy/`">阅读隐私政策</a>
      </div>
    </section>
  </div>
</template>
