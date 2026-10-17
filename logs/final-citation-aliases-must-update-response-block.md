# 最终引用归一必须同步已有 ResponseBlock

## 症状

重定向页面的两个引用在来源 Sheet 中已合并，但正文只渲染第一个角标，另一个仍显示 `[[sourceID]]`。单独测试引用归一函数可以通过，生产 Chat 页面失败。

## 根因

Agent 流式阶段已经创建相同 ID 的完成态 ResponseBlock。Controller 在最终 Message checkpoint 中传入归一后的正文，`recordResponseBlock` 遇到已有记录时只填 messageID 就返回，没有更新 content/contentHash。Message 与唯一来源已归一，优先渲染的 block 却保留别名，重载后无法解析。

## 修复

在首次将已有 block 关联到最终 Message 的同一保存边界，同步更新归一正文与 hash；保留 block ID、顺序与视图身份，不创建重复 block。事件中的原始工具证据保持独立。回归应先写带别名的无 Message block，再关联最终 Message，使用新的 ModelContext 重读并核对正文、hash、唯一来源及编号；生产页面还要检查两个引用均渲染为同一来源编号。
