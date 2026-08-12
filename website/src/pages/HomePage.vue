<script setup>
const base = import.meta.env.BASE_URL;
</script>

<template>
  <div>
    <section class="hero container" aria-labelledby="hero-title">
      <div class="hero-copy">
        <p class="eyebrow"><span class="eyebrow-dot" aria-hidden="true"></span>为 iPhone 原生打造</p>
        <h1 id="hero-title">安静、原生，<span class="gradient-text">始终在手边。</span></h1>
        <p class="hero-lede">Familiar 是一个专注于聊天问答的 iOS AI 助手。使用你自己的 API Key，直接连接模型服务，让每一次提问都简单、清晰、可控。</p>
        <div class="hero-actions">
          <a class="button button-primary" href="#privacy-first">
            了解 Familiar
            <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
              <path d="m7 4 6 6-6 6" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
          </a>
          <a class="button button-secondary" :href="`${base}privacy/`">
            查看隐私政策
            <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
              <path d="M10 2.5 16 5v4.4c0 3.6-2.45 6.9-6 8.1-3.55-1.2-6-4.5-6-8.1V5l6-2.5Z" stroke-linejoin="round" />
            </svg>
          </a>
        </div>
        <p class="hero-note">需要 iOS 18 或更高版本 · App Store 版本准备中</p>
      </div>

      <div class="device-stage" aria-label="Familiar 聊天界面示意图">
        <div class="phone">
          <div class="phone-screen">
            <div class="phone-island" aria-hidden="true"></div>
            <div class="chat-header">
              <div class="chat-brand">
                <img :src="`${base}assets/app-icon.png`" alt="" width="32" height="32">
                <span>Familiar</span>
              </div>
              <span class="icon-button" aria-hidden="true">
                <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 5.5h12M4 10h12M4 14.5h8" stroke-linecap="round" /></svg>
              </span>
            </div>
            <div class="chat-body">
              <div class="model-pill">你的模型 · 直接连接</div>
              <div class="message message-user">帮我把复杂的事情讲清楚一点。</div>
              <div class="message message-assistant">
                <div class="answer-title"><span>✦</span>当然可以</div>
                我会先给出结论，再解释关键原因；需要更多细节时，我们再一步一步展开。
                <div class="privacy-chip">
                  <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M6.5 8V6a3.5 3.5 0 0 1 7 0v2M5 8h10v8.5H5V8Z" stroke-linejoin="round" /></svg>
                  API Key 保存在系统钥匙串
                </div>
              </div>
              <div class="message message-user">很好，就这样。</div>
            </div>
            <div class="composer" aria-hidden="true">
              <span class="composer-text">给 Familiar 发消息</span>
              <span class="send">
                <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2"><path d="m5 11 5-5 5 5M10 6v9" stroke-linecap="round" stroke-linejoin="round" /></svg>
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="trust-strip container" aria-label="Familiar 核心特性">
      <div class="trust-grid">
        <div class="trust-item"><strong>无需账号</strong><span>没有 Familiar 登录流程</span></div>
        <div class="trust-item"><strong>本机历史</strong><span>会话默认保存在这台 iPhone</span></div>
        <div class="trust-item"><strong>自带 Key</strong><span>设备直接连接所选模型服务</span></div>
      </div>
    </section>

    <section id="privacy-first" class="section container" aria-labelledby="features-title">
      <div class="section-heading">
        <p class="section-kicker">简单，但不简陋</p>
        <h2 id="features-title">只保留真正有用的部分。</h2>
        <p>从输入、流式回答到本地渲染，每个细节都围绕一件事：让你更自然地提问，更轻松地理解答案。</p>
      </div>

      <div class="feature-grid">
        <article class="feature-card feature-card-wide">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M5 18.5 3.5 21l4-1A9 9 0 1 0 4 16.5" stroke-linecap="round" stroke-linejoin="round" /><path d="M8 9.5h8M8 13h5" stroke-linecap="round" /></svg>
          </div>
          <h3>流式聊天，回应自然</h3>
          <p>答案会逐步呈现，不必等待完整响应。停止、继续或开始新的会话，都保持清晰直接。</p>
        </article>

        <article class="feature-card feature-card-wide">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M12 3 19 6v5.2c0 4.2-2.86 8-7 9.4-4.14-1.4-7-5.2-7-9.4V6l7-3Z" stroke-linejoin="round" /><path d="m9 12 2 2 4-5" stroke-linecap="round" stroke-linejoin="round" /></svg>
          </div>
          <h3>隐私边界，说得明白</h3>
          <p>本机保存什么、发送给谁、何时需要权限，都以具体功能和你的主动操作为边界。</p>
        </article>

        <article class="feature-card">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><rect x="5" y="3" width="14" height="18" rx="3" /><path d="M9 7h6M9 11h6M9 15h4" stroke-linecap="round" /></svg>
          </div>
          <h3>本地会话历史</h3>
          <p>聊天记录使用 iOS 本地存储，不需要同步到 Familiar 服务器。</p>
        </article>

        <article class="feature-card">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M7 10V7a5 5 0 0 1 10 0v3M5 10h14v11H5V10Z" stroke-linejoin="round" /><circle cx="12" cy="15" r="1" /></svg>
          </div>
          <h3>Keychain 保存密钥</h3>
          <p>每个模型服务的 API Key 分开存入系统钥匙串，可随时在设置中清除。</p>
        </article>

        <article class="feature-card">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M7 3h7l4 4v14H7V3Z" stroke-linejoin="round" /><path d="M14 3v5h5M10 13h5M10 17h4" stroke-linecap="round" /></svg>
          </div>
          <h3>AnyDoc 本地转换</h3>
          <p>Word、PowerPoint、Excel、OpenDocument、RTF、EPUB、CSV 与 PDF 在设备上转为 Markdown；只发送转换后的文字，不上传原始文件。</p>
        </article>
      </div>
    </section>

    <section class="section privacy-section container" aria-labelledby="privacy-title">
      <div class="privacy-panel">
        <div class="section-heading">
          <p class="section-kicker">Privacy by design</p>
          <h2 id="privacy-title">你的设备在中间，Familiar 不在。</h2>
          <p>Familiar 没有账号系统或自有聊天后端。发起请求时，设备按照你的设置直接连接第三方模型服务。</p>
        </div>

        <div class="flow" aria-label="数据流：本机处理后，在用户发送时连接所选模型服务">
          <div class="flow-card">
            <div class="flow-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><rect x="6" y="2.5" width="12" height="19" rx="3" /><path d="M10 18h4" stroke-linecap="round" /></svg>
            </div>
            <h3>这台 iPhone</h3>
            <p>保存会话、附件和设置；API Key 位于系统钥匙串中。</p>
          </div>
          <div>
            <div class="flow-arrow">
              <svg viewBox="0 0 40 20" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M2 10h34M30 4l6 6-6 6" stroke-linecap="round" stroke-linejoin="round" /></svg>
            </div>
            <div class="flow-label">仅在你发送时</div>
          </div>
          <div class="flow-card">
            <div class="flow-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M7 17.5H6a4 4 0 0 1-.4-8A6.5 6.5 0 0 1 18 8a4.5 4.5 0 0 1-.5 9.5H11" stroke-linecap="round" /><path d="m9 14 3 3 3-3M12 10v7" stroke-linecap="round" stroke-linejoin="round" /></svg>
            </div>
            <h3>你选择的模型服务</h3>
            <p>接收完成请求所需的消息内容，并按该服务自己的隐私条款处理。</p>
          </div>
        </div>

        <div class="privacy-links">
          <a class="button button-primary" :href="`${base}privacy/`">阅读完整隐私政策</a>
          <a class="button button-secondary" :href="`${base}support/`">查看常见问题</a>
        </div>
      </div>
    </section>

    <section class="cta container">
      <div class="cta-panel">
        <img :src="`${base}assets/app-icon.png`" alt="Familiar App 图标" width="74" height="74">
        <h2>让复杂的问题，变得熟悉一点。</h2>
        <p>Familiar 的 App Store 版本正在准备中。你可以先查看项目进展，或在 GitHub 提交反馈。</p>
        <a class="button button-primary" href="https://github.com/IsaacHuo/familiar" target="_blank" rel="noreferrer">
          在 GitHub 查看 Familiar
          <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M7 4h9v9M16 4 7 13" stroke-linecap="round" stroke-linejoin="round" /><path d="M13 10v5H4V6h5" stroke-linecap="round" stroke-linejoin="round" /></svg>
        </a>
      </div>
    </section>
  </div>
</template>
