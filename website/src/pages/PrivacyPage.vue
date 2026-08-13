<script setup>
const base = import.meta.env.BASE_URL;
</script>

<template>
  <div>
    <header class="page-hero narrow">
      <p class="eyebrow"><span class="eyebrow-dot" aria-hidden="true"></span>隐私与数据</p>
      <h1>隐私政策</h1>
      <p>我们希望你准确知道 Familiar 在设备上保存什么、何时会发送数据，以及你可以怎样保持控制。</p>
      <div class="meta-row">
        <span>生效日期：2026 年 8 月 13 日</span>
        <span>适用于 Familiar 1.0 及本网站</span>
      </div>
    </header>

    <div class="policy-layout container">
      <aside class="policy-nav" aria-label="隐私政策目录">
        <p>本页目录</p>
        <a href="#overview">概览</a>
        <a href="#local-data">本机数据</a>
        <a href="#provider-data">模型服务请求</a>
        <a href="#permissions">系统权限</a>
        <a href="#website">网站数据</a>
        <a href="#retention">保留与删除</a>
        <a href="#security">安全与责任</a>
        <a href="#changes">政策变更</a>
        <a href="#contact">联系我们</a>
      </aside>

      <article class="policy-article">
        <section id="overview">
          <h2>1. 概览</h2>
          <p>本隐私政策说明 Familiar iOS App（下称“Familiar”或“App”）以及 Familiar 官方 GitHub Pages 网站如何处理信息。</p>
          <div class="notice"><strong>最重要的边界：</strong>Familiar 不要求创建账号，不运营自有聊天后端，也不集成广告或行为分析 SDK。聊天历史默认保存在你的设备上；当你发送消息时，完成请求所需的内容会由设备直接发送给你选择的第三方 AI 模型服务或自定义服务地址。</div>
          <p>“本机保存”不等于“任何数据都不会离开设备”。只要你向模型发起请求，相关消息内容便需要发送到你选择的服务。第三方如何记录、保留、训练或跨境处理这些内容，取决于其自身条款和你的账户配置。</p>
        </section>

        <section id="local-data">
          <h2>2. 保存在设备上的数据</h2>
          <h3>会话与设置</h3>
          <p>Familiar 使用 Apple 提供的本地存储能力，在当前设备上保存会话、消息、模型选择、回答偏好和必要的运行状态。Familiar 不会为了同步这些内容而将它们上传到 Familiar 自有服务器。</p>

          <h3>API Key</h3>
          <p>你提供的 API Key 会按模型服务分别保存在 iOS Keychain 中。Familiar 会在向对应服务发送请求时使用该 Key，并允许你在 App 设置中清除它。</p>

          <h3>文档与图片</h3>
          <p>你主动选择的文档会复制到 App 的本地存储，并由 AnyDoc 在设备上转换为 Markdown；扫描 PDF 的无文本页面会使用 Apple Vision 在本机进行 OCR。发送消息时，只有转换后的文档文字会随请求发送给所选模型服务，原始文件不会上传。相机拍摄或选择的图片只作为本地消息草稿处理；当前版本会阻止图片发送，不创建消息，也不上传图片。</p>
          <p>你从其他 App 使用“共享”发送给 Familiar 的文本、网页链接或文件，会先保存在 Familiar 与 Share Extension 共用的 App Group 本地收件箱中。Familiar 只在当前没有未发送草稿或运行中请求时，将最早一项导入为可编辑草稿；导入或终态失败处理后会删除共享收件箱中的副本。共享操作本身不会向模型服务发送内容。</p>
          <p>你通过 Siri、快捷指令或 Spotlight 使用“询问 Familiar”或“用 Familiar 处理文本”时，明确提供的文字会打开主 App，并沿用当前选择的 BYOK 模型服务完成请求；文字最多保留 20,000 个字符。App Intent 不读取 API Key，也不直接连接模型服务，且不会覆盖未发送草稿。“打开 Familiar”不会创建草稿或发送网络请求。工具写入仍需遵守 App 内现有授权与确认规则。</p>
          <p>模型回复或导入 Markdown 中引用的远程图片不会在 App 内自动加载。Familiar 只显示对应来源链接；只有在你主动点击后，iOS 才会将该地址交给外部应用打开，届时目标网站的隐私政策适用。</p>
        </section>

        <section id="provider-data">
          <h2>3. 发送给模型服务的数据</h2>
          <p>Familiar 支持用户自带 API Key。根据你的模型、对话和主动使用的功能，一次请求可能包含：</p>
          <ul>
            <li>你输入的消息和为保持上下文所需的历史消息；</li>
            <li>你设置的系统提示与所选模型标识；</li>
            <li>你主动附加文档中在本机提取的文本；</li>
            <li>当前版本不会向模型服务发送相机拍摄或相册选择的图片；</li>
            <li>在你主动调用工具、授予系统权限后，与当前问题相关的日历或提醒事项结果；</li>
            <li>完成鉴权和网络连接所需的 API Key、请求头及网络信息（例如 IP 地址会自然暴露给接收服务）。</li>
          </ul>
          <p>这些请求从你的设备直接发送到所选第三方 AI Provider，或你配置的 OpenAI-compatible 自定义 endpoint，不经过 Familiar 自有服务器。</p>
          <div class="notice"><strong>第三方服务提示：</strong>模型服务和自定义 endpoint 的数据保留、日志、内容训练、安全措施及跨境传输政策不受 Familiar 控制。发送敏感内容前，请先阅读并配置相应服务的隐私政策。删除 Familiar 中的本地会话，不能撤回此前已发送给第三方的内容。</div>
        </section>

        <section id="permissions">
          <h2>4. 系统权限</h2>
          <p>Familiar 仅在相关功能需要时请求系统权限。你可以拒绝权限，并随时在 iOS“设置”中更改授权。</p>

          <h3>相机</h3>
          <p>用于拍摄准备添加到消息草稿中的照片。Familiar 不会在后台持续使用相机。</p>

          <h3>麦克风与语音识别</h3>
          <p>用于将你的语音转换为可编辑的文字草稿。Familiar 使用 Apple Speech 框架，并在设备与语言支持时要求端侧识别；并非所有情况下都能保证完全在设备上识别。Familiar 不保存音频录音，但 Apple 对语音数据的处理可能适用 Apple 自身的隐私政策。</p>

          <h3>日历与提醒事项</h3>
          <p>仅在你主动请求相应工具并授予权限后，读取完成当前问题所需的日历或提醒事项数据。创建日历事件或提醒事项前，Familiar 会显示预览并要求逐次确认。与问题相关的数据可能作为工具结果发送给你选择的模型服务，以便生成回答。</p>
        </section>

        <section id="website">
          <h2>5. 本网站的数据处理</h2>
          <p>本网站是托管在 GitHub Pages 上的静态 Vue 网站。网站代码不设置广告 Cookie，不嵌入分析脚本，也不提供账号或表单提交功能。</p>
          <p>GitHub 作为托管服务提供方，可能为了提供、安全维护和统计其服务而处理基础访问日志、IP 地址或设备信息。这部分处理由 GitHub 依据其自身的隐私声明负责。访问外部链接后，对应网站的政策将适用。</p>
        </section>

        <section id="retention">
          <h2>6. 数据保留、删除与控制</h2>
          <ul>
            <li>你可以在 Familiar 中删除会话及其本地附件。</li>
            <li>你可以在设置中清除各模型服务的 API Key。</li>
            <li>你可以在 iOS“设置”中撤销相机、麦克风、语音识别、日历或提醒事项权限。</li>
            <li>卸载 App 通常会删除 App 容器中的会话与附件；Keychain 项可能在卸载后仍由系统保留，因此如需确保清除，请先在 Familiar 设置中移除 API Key。</li>
          </ul>
          <p>Familiar 无法代表第三方模型服务删除其已经接收的数据。相关请求请直接依据该服务提供的控制项或隐私渠道处理。</p>
        </section>

        <section id="security">
          <h2>7. 安全与使用责任</h2>
          <p>Familiar 使用 iOS Keychain 保存 API Key，并通过系统网络框架直接连接你选择的服务。没有任何存储或传输方式能够保证绝对安全；请保护你的设备、API Key 和模型服务账户，并避免向不受信任的自定义 endpoint 发送内容。</p>
          <p>AI 生成内容可能不准确，不应作为医疗、法律、财务或其他高风险决定的唯一依据。第三方模型服务产生的费用、额度和账户行为由你与该服务之间的协议决定。</p>
        </section>

        <section id="changes">
          <h2>8. 政策变更</h2>
          <p>产品功能或数据处理方式发生变化时，我们可能更新本政策。新版本会在本页显示新的生效日期；重大变化也可能在 App 更新说明或项目公告中提示。</p>
        </section>

        <section id="contact">
          <h2>9. 联系我们</h2>
          <p>如对隐私、数据删除或本政策有疑问，请通过 <a href="https://github.com/IsaacHuo/familiar/issues" target="_blank" rel="noreferrer">Familiar GitHub Issues</a> 联系开发者。</p>
          <div class="notice"><strong>请勿在公开 Issue 中提交敏感信息。</strong>不要粘贴 API Key、完整聊天内容、个人日历、提醒事项、文档、图片或其他个人数据。请先描述问题类型，等待开发者提供适合的后续沟通方式。</div>
          <p><a :href="`${base}support/`">前往支持中心</a></p>
        </section>
      </article>
    </div>
  </div>
</template>
